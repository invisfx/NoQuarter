# 15 — Primvar → AOV Recipes in Katana (Houdini FX caches, velocity & arbitrary data)

> How to get arbitrary per-point data from a Houdini FX cache (velocity, Cd, id, age, world position…) out as render AOVs in **Katana 6.5v4 + RenderMan 26.x (RfK)**. Written from a real debugging session — every gotcha here cost time. Cross-refs: AOVs/LPEs → [05](05-aovs-lpes-outputs.md), shading → [03](03-renderman-shading.md), Katana customization/OpScript → [08](08-katana-customization.md).

---

## 0. Why you're here: `dPdtime` doesn't work on velocity-blurred particles

If you're chasing a motion-vector pass for an FX cache and `dPdtime` renders **exactly black** while `dPcameradtime` and forward/backward vectors work — that's expected, not a bug:

- **`dPdtime`** is computed by **differentiating geometry motion samples** (real sub-frame positions, i.e. transformation/deformation blur). A keyframed/deforming object populates it.
- **Velocity blur** (single geometry sample + a `v` primvar — standard for particles/sims with changing topology) gives the renderer **no motion samples to differentiate**, so `dPdtime` = 0.
- `dPcameradtime`, fwd/back vectors, and the rendered blur all come from the renderer **sampling** the velocity-displaced points, so they work — different code path.

**Conclusions:**
- On a **locked camera**, `dPcameradtime` *is* `dPdtime` (camera contributes zero) — just use it.
- For changing-topology FX (particles, RBD, volumes), deformation blur is impossible, so `dPdtime` structurally can't populate. **Output the `v` velocity primvar directly as an AOV** (`dP/dt` *is* velocity). The rest of this doc is how.

---

## 1. Promote the point attribute to a readable primvar

RenderMan/RfK reads primvars from **`geometry.arbitrary.*`**, *not* from `geometry.point.*` (only `geometry.point.P` is special-cased). So `geometry.point.v` must be promoted before any `PxrPrimvar`/`PxrVariable` can see it.

**`OpScript`** on the particle location (`CEL` = the points location):

```lua
local v = Interface.GetAttr("geometry.point.v")
if v ~= nil then
    Interface.SetAttr("geometry.arbitrary.v.scope",     StringAttribute("point"))
    Interface.SetAttr("geometry.arbitrary.v.inputType", StringAttribute("vector3"))
    Interface.SetAttr("geometry.arbitrary.v.value",     v)
end
```

### ⚠️ Gotcha #1 — `inputType` convention: `vector3`, not `vector`
This is the one that silently breaks everything. Katana has two conventions:
- RenderMan-style: `vector`, `color`, `point`, `normal`, `float`
- **USD-style: `vector3`, `color3`, `point3`, `normal3`**

If your cache came in via USD, the importer uses the **USD style**, and declaring `inputType = "vector"` means **RfK never declares the primvar** → `PxrPrimvar` silently falls back to its default (black). **Match what your importer used** — check a sibling primvar (`geometry.arbitrary.Cd.inputType`, `…N.inputType`) and copy that exact string. In a USD pipeline it's almost always `vector3` / `color3`.

The three sub-attributes must all be present together at **render time** (verify at the *bottom* of the node graph, not just at the OpScript — a downstream node can strip them):
- `scope` = `point` (per-point) — `value` data laid out `[p0.x,p0.y,p0.z, p1.x,…]`, tuple size 3
- `inputType` = `vector3` (or whatever the importer uses)
- `value` = the flat float array, length `numPoints × 3`

---

## 2. ONE primvar → AOV (the `userColor` / U4 route)

PxrSurface exposes two **data lobes**: **U3 = world position**, **U4 = `userColor`**. Use `userColor` for a single value. (For more than one, skip to §3 — `userColor` only holds one.)

### 2a. Read the primvar
**`PxrPrimvar`** (inside the particle material's NetworkMaterial):
| Field | Value |
|---|---|
| `varname` | `v` |
| `Type` | `vector` (direction, gets space-transformed) **or** `color` (raw, untransformed — see Gotcha #4) |
| `defaultColor` | `0 0 0` |

Connect **`resultRGB` → `PxrSurface.userColor`** (in the **Input AOVs** section). `userColor` does **not** affect the beauty.

### 2b. Register the U4 lobe — **mandatory in Katana**
RfM does this automatically; **RfK does not**. Without it, the `userColor` AOV is **black even with a constant** plugged in.

**`OpScript`**, `CEL = /root`:
```lua
Interface.SetAttr('prmanGlobalStatements.options.lpe.user4', StringAttribute("UserColor"))
```

### 2c. Declare the channel + output
**`PrmanOutputChannelDefine`:**
| Field | Value |
|---|---|
| `name` | `userColor` (freeform) |
| `type` | `color` |
| `source` | `lpe:nothruput;noinfinitecheck;noclamp;unoccluded;overwrite;CU4L` |

**`RenderOutputDefine`:** `type` = `raw`, `channel` = `userColor` (appears in the dropdown only **after** the channel node is wired in). Make the file **32-bit float, no view transform** — it's data.

### ⚠️ Gotcha #2 — the U4 registration (§2b) is the usual cause of a black `userColor` AOV.
### ⚠️ Gotcha #3 — `noclamp` is mandatory. Velocity is large and **negative** (e.g. `-175, -189, -14.6`); without `noclamp` in the LPE those values are clipped and you lose data.

---

## 3. MANY primvars → AOVs (the `PxrTee` route)

`userColor` is a single lobe — a second primvar through it overwrites the first. For multiple arbitrary AOVs use **`PxrTee`**: it passes its input through *and* writes that value to a channel named in **`aovName`**. No lobe limit, no U4 registration.

**Per primvar:**
1. `PxrPrimvar` (`varname`, Type) → **`PxrTee.inputRGB`**
2. `PxrTee.aovName` = the channel name (e.g. `velocity`)
3. `PrmanOutputChannelDefine`: `name` = `velocity`, `type` = `color`, `source` = `velocity`
4. `RenderOutputDefine`: `channel` = `velocity`

### ⚠️ Gotcha #5 — keep-alive: every PxrTee must reach the bxdf or it writes **nothing**
> "If its result does not eventually feed into an active Bxdf downstream, the PxrTee will not be invoked and will not write to its AOV."

And you **can't daisy-chain** different primvars through one line — each PxrTee tees off *its own* input, so chaining makes them all output the first value. Instead, **combine all the `resultRGB` outputs and dump them into `userColor` as a single sink:**

```
PxrPrimvar_v   → PxrTee(aovName=velocity) ┐
PxrPrimvar_Cd  → PxrTee(aovName=Cd)       ┼→ PxrAdd / PxrBlend → PxrSurface.userColor   (sink only)
PxrPrimvar_id  → PxrTee(aovName=id)       ┘
```

- One connection keeps **all** tees alive; each still writes its **own** named AOV.
- `userColor` here is just a harmless sink (doesn't affect beauty) — **don't** create an output for it.
- **Scalar** primvars (`age`, `pscale`, `id`) → use PxrTee's **float** side (`inputF`/`resultF`, float AOV name), `type = float` on the channel.

For a **single** PxrTee, the sink is direct: `PxrPrimvar → PxrTee(aovName) → PxrSurface.userColor`.

---

## 4. Units & coordinate space (get these right or comp will be wrong)

- **Units — ⚠️ Gotcha #6:** Houdini `v` is **units per *second***. Motion-vector/comp workflows want **units per *frame*** → multiply by **`1/FPS`**. Cleanest place is in the §1 promotion OpScript (scale `value` before setting it); or do it in comp — just pick one and be deliberate. Skip it and vectors are ~`FPS×` too long.
- **Space — ⚠️ Gotcha #4:** reading the primvar as **`Type = vector`** makes RenderMan **coordinate-transform** it (object→shading space) — values come out rotated/shuffled vs. what's in the attribute. To ferry the **raw authored world-space values**, read as **`Type = color`** (and optionally `inputType = color3`); `color` carries 3 floats with no spatial math. Use `vector` only if you actually want it transformed into shading space.

---

## 5. Diagnostic recipes (how we localized each failure)

Bisect the pipeline instead of guessing — these are the tests that found each bug:

| Test | How | If it works → | If it fails → |
|---|---|---|---|
| **Constant into `userColor`** | Type `1 2 3` directly into `PxrSurface.userColor`, render, probe | output side OK; problem is the primvar read | output/LPE side broken → U4 registration (§2b) or channel source/`RenderOutputDefine` mapping |
| **Nonexistent primvar + default** | `PxrPrimvar.varname = doesnotexist`, `defaultColor = 1 2 3` | connections OK; patterns read fine — your real primvar isn't being **found** (→ §1, esp. Gotcha #1) | connecting any pattern breaks the lobe (rare) |
| **Read a known primvar** | point `PxrPrimvar` at `P` | PxrPrimvar can bind primvars here → it's *your* primvar's declaration | can't bind any primvar → geometry/instancing issue |
| **Primvar survives to render** | select the particle location at the **bottom** of the graph; check `geometry.arbitrary.v.{scope,inputType,value}` all intact | reaches the renderer → it's scope/class/`inputType` | a downstream node strips it → fix branch/order |
| **Probe G & B numerically** | don't trust the viewer (negative values display as red/black through a view transform) | data may already be correct | true 3→1 collapse |

**Key reasoning shortcut:** a 1-channel ("red only") result usually means a 3→1 collapse — check `PrmanOutputChannelDefine.type` (must be `color`, not `float`), the `PxrPrimvar` Type, and the actual `value` tuple size. And negative data through a display view transform *looks* red/black even when the AOV is fine — **probe the numbers, don't eyeball it.**

---

## Quick checklist
- [ ] Velocity-blur particles → don't fight `dPdtime`; output the `v` primvar (or use `dPcameradtime` on a locked cam).
- [ ] `geometry.point.v` promoted to `geometry.arbitrary.v` with `scope=point`, **`inputType=vector3`** (match importer), tuple-3 `value` — verified at the **bottom** of the graph.
- [ ] One primvar: `PxrPrimvar → userColor`; **U4 registered** via `lpe.user4`; channel source = the `CU4L` LPE with **`noclamp`**.
- [ ] Many primvars: `PxrPrimvar → PxrTee(aovName)` each; all `resultRGB` **combined into `userColor` as a sink** (keep-alive); per-channel `PrmanOutputChannelDefine` + `RenderOutputDefine`.
- [ ] Units `×1/FPS`; choose `Type=color` (raw) vs `Type=vector` (transformed) deliberately.
- [ ] Data outputs: `RenderOutputDefine type=raw`, 32-bit float, no view transform.
