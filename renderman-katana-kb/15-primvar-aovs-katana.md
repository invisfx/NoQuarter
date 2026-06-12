# Why Your Motion-Vector AOV Is Black: Chasing `dPdtime` Through Katana and RenderMan

*A debugging story about Houdini FX caches, velocity primvars, and the half-dozen places RenderMan-for-Katana will silently hand you nothing.*

**Stack:** Katana 6.5v4 · RenderMan 26.x (RfK) · a particle cache out of Houdini.
**TL;DR:** `dPdtime` renders black for velocity-blurred particles *by design*. Don't fight it — output the `v` primvar yourself. But getting an arbitrary primvar into an AOV in RfK means clearing about six tripwires, each of which fails **silently to black**. This is all of them, in the order you'll hit them.

---

## The setup

I had an FX cache from Houdini — particles — rendering through RenderMan in Katana. Camera locked off. I needed a motion-vector pass. The forward/backward vectors were working. `dPcameradtime` was working. `dPdtime`? **Pure black.** Pixel-probe it, every component reads `0`.

That's a weird failure, because on a locked camera `dPdtime` and `dPcameradtime` should be *identical* — the camera contributes nothing, so both are just object motion. One works, the other is zero. So the data clearly exists somewhere; one channel just isn't being fed.

## Why `dPdtime` is black (and why that's correct)

Here's the thing nobody tells you up front: those four "motion" outputs don't come from the same place.

- **`dPdtime`** is computed by **differentiating the geometry's motion samples** — actual sub-frame positions, i.e. transformation or deformation blur. A keyframed sphere has these. It populates beautifully.
- A particle cache uses **velocity blur**: one geometry sample plus a `v` primvar. The renderer fakes the motion by displacing points along `v` *while it samples*. There are **no motion samples to differentiate**, so `dPdtime` is genuinely `0`.
- `dPcameradtime`, the fwd/back vectors, and the rendered blur all fall out of that *sampling* step — a totally different code path — which is why they work.

I proved this to myself by accident earlier: the exact same AOV setup, copied from a scene where I'd animated a sphere, worked there and died here. The only variable was geometry-motion vs. velocity-motion. That's the whole story.

**So two takeaways:**

1. On a **locked camera**, `dPcameradtime` *is* `dPdtime`. Just use it. A camera-relative vector is what 2D VectorBlur wants anyway.
2. For changing-topology FX — particles, RBD, volumes — deformation blur is impossible (point counts change frame to frame), so `dPdtime` *structurally cannot* populate. Stop chasing it. **`dP/dt` is just velocity, and you already cached `v`.** Output that.

That decision — output the `v` primvar directly — is where the real adventure began.

---

## Tripwire 1: `geometry.point.v` is not a primvar the renderer can see

My cache had `geometry.point.v` sitting right there in the scene graph. Tuple-3, real values, `(-175.2, -189.0, -14.6)` on particle 0. Looked perfect.

But RenderMan/RfK reads primvars from **`geometry.arbitrary.*`**, not `geometry.point.*` (only `geometry.point.P` is special-cased). So `PxrPrimvar` looking up `v` found nothing. You have to *promote* it.

An `OpScript` on the particle location does it:

```lua
local v = Interface.GetAttr("geometry.point.v")
if v ~= nil then
    Interface.SetAttr("geometry.arbitrary.v.scope",     StringAttribute("point"))
    Interface.SetAttr("geometry.arbitrary.v.inputType", StringAttribute("vector3"))
    Interface.SetAttr("geometry.arbitrary.v.value",     v)
end
```

Three sub-attributes, all required, all of which must survive to the **bottom** of your node graph (check there, not at the OpScript — a downstream node can quietly strip them):

- `scope = point` — per-point data, laid out `[p0.x,p0.y,p0.z, p1.x,…]`, tuple 3
- `inputType = vector3` — **read the next section before you type `vector` here**
- `value` — the flat float array, length `numPoints × 3`

## Tripwire 2: `vector3`, not `vector` — the one that cost me the most

This is the nasty one, because it fails *completely silently*. I dutifully set `inputType = "vector"` (because that's the RenderMan type name), and the AOV stayed black. No error. No warning. Nothing.

Katana has **two competing conventions** for `inputType`:

- RenderMan-style: `vector`, `color`, `point`, `normal`, `float`
- **USD-style: `vector3`, `color3`, `point3`, `normal3`**

My cache came in through USD. So the importer — and every other primvar in my scene — used the **USD style**. Declaring `inputType = "vector"` meant RfK simply **never declared the primvar to the renderer**, and `PxrPrimvar` fell back to its (black) default.

The fix isn't to memorize which convention is "right." It's to **match what your importer already used**. Open a sibling primvar the cache brought in — `geometry.arbitrary.Cd`, `geometry.arbitrary.N` — and read *its* `inputType`. Copy that exact string. Mine said `vector3`. The moment I changed `vector` → `vector3`, the primvar started binding.

**Lesson: when an arbitrary primvar reads as default/black, suspect the `inputType` convention before anything else.**

---

## Getting ONE primvar to an AOV: the `userColor` route

PxrSurface gives you exactly two "data lobes" you can hijack for arbitrary output: **U3** (world position) and **U4** (`userColor`). Neither renders into the beauty. For a single value, `userColor` is the path.

**Read the primvar** — `PxrPrimvar`:

| Field | Value |
|---|---|
| `varname` | `v` |
| `Type` | `vector` (transformed) or `color` (raw — see below) |
| `defaultColor` | `0 0 0` |

Wire **`resultRGB` → `PxrSurface.userColor`** (Input AOVs section).

### Tripwire 3: in Katana, you must register the U4 lobe yourself

RenderMan-for-Maya does this automatically. **RfK does not.** Until you register it, `userColor` is black *even if you plug a flat constant straight in* — which is exactly how I confirmed the data wasn't the problem. (More on that test below; it's the single most useful debugging move in this whole saga.)

One more `OpScript`, this time at `CEL = /root`:

```lua
Interface.SetAttr('prmanGlobalStatements.options.lpe.user4', StringAttribute("UserColor"))
```

That line is what makes the `CU4L` light-path expression actually collect anything.

### Declare the channel and output

`PrmanOutputChannelDefine`:

| Field | Value |
|---|---|
| `name` | `userColor` |
| `type` | `color` |
| `source` | `lpe:nothruput;noinfinitecheck;noclamp;unoccluded;overwrite;CU4L` |

`RenderOutputDefine`: `type = raw`, `channel = userColor` (it only appears in the dropdown *after* you wire the channel node in). Write it **32-bit float, no view transform** — it's data, not a picture.

### Tripwire 4: `noclamp` is not optional

Velocity is large and **negative** (`-175, -189, -14.6`). Without `noclamp` in that LPE, those values get clipped and you lose your data. It's baked into the string above for a reason.

---

## Getting MANY primvars to AOVs: `PxrTee`

`userColor` is *one* lobe. Route a second primvar through it and you just overwrite the first. So the moment you want velocity *and* Cd *and* id, you switch tools — to **`PxrTee`**, which passes its input straight through *and* writes that value to a channel you name in `aovName`. No lobe limit, no U4 registration.

Per primvar:

1. `PxrPrimvar` (`varname`, `Type`) → `PxrTee.inputRGB`
2. `PxrTee.aovName` = `velocity`
3. `PrmanOutputChannelDefine`: `name = velocity`, `type = color`, `source = velocity`
4. `RenderOutputDefine`: `channel = velocity`

### Tripwire 5: every `PxrTee` must reach the bxdf, or it writes nothing

> *"If its result does not eventually feed into an active Bxdf downstream, the PxrTee will not be invoked and will not write to its AOV."*

And you **can't daisy-chain** different primvars through one line — each `PxrTee` tees off *its own* input, so chaining would make them all spit out the first value. The clean trick: run each `PxrTee.resultRGB` into a combine node and dump the lot into `userColor` as a single throwaway **sink**:

```
PxrPrimvar_v   → PxrTee(aovName=velocity) ┐
PxrPrimvar_Cd  → PxrTee(aovName=Cd)       ┼→ PxrAdd / PxrBlend → PxrSurface.userColor   (sink only)
PxrPrimvar_id  → PxrTee(aovName=id)       ┘
```

That one connection keeps every tee alive; each still writes its own named AOV. `userColor` here is just a sink — you don't even create an output for it. (For a *single* tee, skip the combine: `PxrPrimvar → PxrTee(aovName) → PxrSurface.userColor`.)

Scalar primvars (`age`, `pscale`, `id`) use the **float** side: `inputF`/`resultF` and a `type = float` channel.

---

## Two things that aren't bugs but will make comp wrong

### Units (Tripwire 6)
Houdini `v` is in **units per *second***. Comp wants **units per *frame***. Multiply by **`1/FPS`** — cleanest done right in the promotion OpScript before you set `value`, or in comp. Pick one, be deliberate. Skip it and your vectors are `FPS×` too long.

### Coordinate space
Reading the primvar as **`Type = vector`** makes RenderMan **coordinate-transform** it into shading space — so the numbers come out rotated/shuffled versus what's in the attribute. If you want the **raw, world-space** values you authored, read it as **`Type = color`** instead; `color` carries three floats with no spatial math. Use `vector` only when you genuinely want it transformed.

---

## The debugging move that actually mattered

Every failure in this story was silent-to-black, which is maddening — but it's also *bisectable*. The trick is to test the pipe and the data separately:

| Test | How | Pass means | Fail means |
|---|---|---|---|
| **Constant into `userColor`** | type `1 2 3` straight into `userColor`, render, probe | the whole output side works → the problem is reading the primvar | output/LPE side is broken → U4 registration or channel source |
| **Nonexistent name + default** | `PxrPrimvar.varname = doesnotexist`, `defaultColor = 1 2 3` | pattern path is fine → your real primvar isn't being *found* (→ `inputType`!) | connecting a pattern breaks the lobe (rare) |
| **Read `P`** | point `PxrPrimvar` at `P` | it can bind *some* primvar here → yours is mis-declared | can't bind anything → geometry/instancing issue |
| **Check the bottom of the graph** | select the particle location at the render node; inspect `geometry.arbitrary.v.*` | reaches the renderer intact → scope/`inputType` | a node upstream strips it |

The "constant into `userColor`" test is the one that broke this case open. It came back black — which immediately told me the data was innocent and the **lobe wasn't registered**. Without that test I'd still be staring at the primvar.

And one perceptual trap worth its own line: **probe the numbers, don't trust the viewer.** Negative velocity values pushed through an sRGB/ACES view transform display as red or black even when the AOV is perfectly fine. I nearly chased a "red channel only" ghost that was just the display clamping negatives.

---

## The short version

- `dPdtime` is black on velocity-blur particles **on purpose** — there are no motion samples to differentiate. Output the `v` primvar (or, on a locked cam, just use `dPcameradtime`).
- Promote `geometry.point.v` → `geometry.arbitrary.v`. **`inputType = vector3`** (match your importer — this is the silent killer).
- One primvar → `userColor`, but **register U4** (`lpe.user4`) or it's black, and keep **`noclamp`** in the `CU4L` LPE.
- Many primvars → **`PxrTee`** (one `aovName` each), all results **combined into a `userColor` sink** so they stay alive.
- **`×1/FPS`** for units; **`color`** type for raw values, **`vector`** for transformed.
- When it's black, **bisect**: constant-into-userColor, fake-name-with-default, probe the actual numbers.

Six tripwires, every one of them silent. Now they're written down.

---

*Filed under: RenderMan 26.x, Katana 6.5v4, things that should throw an error but don't. Related KB: [05 — AOVs & LPEs](05-aovs-lpes-outputs.md), [03 — Shading](03-renderman-shading.md), [08 — Katana customization / OpScript](08-katana-customization.md).*
