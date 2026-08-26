# 16 — Katana/RfK Quick Reference (session-verified)

> Facts verified the hard way — each entry here was either confirmed against docs/search or corrected after a wrong first guess in production use. When memory and this file disagree, trust this file. Companion to [08](08-katana-customization.md) and [15](15-primvar-aovs-katana.md).

---

## Parameter expressions (Python)

| Fact | Detail |
|---|---|
| **`getParam('Node.args.path.value')`** | Returns a **parameter reference object**, NOT a string/number. Coerces to number in math; has **no string methods** (`.split()` fails). Wrap in `str(...)` for string ops. |
| **`getresdict(name)`** | The expression-native resolution resolver. Takes a resolution string (`'1920x1080'` **or** named format `'HD_1080'`/`'hd'`) → dict with `'xres'`, `'yres'`, `'aspectRatio'`, `'name'`, `'fullname'`, `'groupname'`, `'proxyname'`. **Use this, not string parsing.** |
| `getXRes()` / `getYRes()` | NOT defined in 6.5v4 expression namespace (despite some doc references). |
| Bare `ResolutionTable` | NOT defined in expressions. Script/Python-tab form: `from Katana import ResolutionTable; ResolutionTable.GetResolutionTable().getResolution(name)` → entry → `.getXRes()/.getYRes()`. In an expression use `__import__('Katana', {}, {}, ['ResolutionTable']).ResolutionTable...` (fromlist required). |
| No `import` statements | Expressions are single expressions. Use `__import__('re')`, `__import__('fnmatch')` inline. |
| One number per field | An expression returns one scalar per parameter component — parse/index per field (i0–i3), never "two numbers" from one expression. |

**5% overscan from resolution** (one per component; swap node name):
```python
int(getresdict(str(getParam('RenderSettings.args.renderSettings.resolution.value')))['xres'] * 0.05)  # i0/i2
int(getresdict(str(getParam('RenderSettings.args.renderSettings.resolution.value')))['yres'] * 0.05)  # i1/i3
```

**Switch-by-variable with wildcard:**
```python
1 if (getGraphStateVariable("shot") or "").startswith("102") else 0
1 if __import__('fnmatch').fnmatch(getGraphStateVariable("shot") or "", "102*") else 0
```
`==` is exact match — `"102*"` in an equality test matches nothing. `VariableSwitch` node = declarative wildcard patterns per port, no code.

---

## CEL

| Fact | Detail |
|---|---|
| Type test | `//*{@type == "polymesh"}` (`@type` ≡ `attr("type")`) |
| **OR inside predicate** | `//*{@type == "polymesh" or @type == "subdmesh"}` |
| Set ops | `+` union (or adjacency), `-` difference, `^` intersection |
| Only `*` and `//` | No `?`, no numeric ranges, no regex. |
| **Perf rule 1** | CEL fast-path compares the **last token** — keep it specific. Wildcard mid-path (`geo/*/render`) beats trailing wildcard (`geo/car*`). |
| **Perf rule 2** | Recursion is the cost: `//car*` may test every location. Anchor to a known parent. Attribute predicates `{...}` are most expensive — scope them tight. |
| Explicit paths beat wildcards up to ~100 paths | Above thousands, wildcard rules win. Collections of explicit paths stay fast. |
| **No cross-location lookup** | A CEL test sees only the tested location's own attrs. `/root{attr("renderSettings.resolution") == "HD_1080"}` works *at /root only*. To condition other locations on resolution: OpScript + `Interface.GetGlobalAttr("renderSettings.resolution", "/root")`, or drive the CEL string with a parameter expression. |
| CEL selects, never converts | Type changes are `Interface.SetAttr("type", StringAttribute("polymesh"))` in an OpScript (guard with `Interface.GetType()`). |

---

## Attribute & primvar conventions

| Fact | Detail |
|---|---|
| Primvars for shaders live in **`geometry.arbitrary.*`** | `geometry.point.*` is native geometry (only `P` special-cased). Promote with `value`/`scope`/`inputType` triplet. See [15](15-primvar-aovs-katana.md). |
| **`inputType` convention varies** | USD-imported scenes use `vector3`/`color3`/`point3`; match a sibling primvar, don't assume `vector`. |
| **Three type-name schemes in play** | Katana `inputType`: `vector3`/`color3`/`point3` (USD-style). `PxrVariable.type`: `float`/`float2`/`float3`. `PxrPrimvar.Type` (RfK 26 UI): also USD-style (`vector3`…). Semantics still matter regardless of spelling: `color*` = raw pass-through (data AOVs), `vector*` = rotates/scales but **no translation**, `point*` = full transform. A position primvar (Pref) read as `vector3` loses translation — fine only on identity-xform geo. |
| **`v` is a reserved name** | RenderMan built-in parametric V — a primvar named `v` reads as scalar grayscale. Rename (`vel`). Also reserved: `u, s, t, P, N, Ng, Cs, Os, du, dv, time`. |
| Scope mapping | Houdini point→`point`, vertex→`vertex`, primitive→`face`, detail→`primitive`. Per-particle data is always `point`. |
| **`visible`** (int, location root) | Alembic visibility property: `1` visible, `0` hidden (all rays), `-1` inherit. Animatable, inherited from parents. Distinct from RfK ray-visibility flags and from `viewer.default.drawOptions.hide` (viewport-only). |
| Multi-sample (motion) attribute | `FloatAttribute({ [t0] = arr0, [t1] = arr1 }, 3)` — table keyed by sample time. |
| **User attributes need a declared TYPE** | `prmanStatements.attributes.user.*` are consumed as *typed* Ri user attrs. A bare `FloatAttribute({1,0,0},3)` is NOT enough for `PxrMatteID` (it queries a **color**-typed attr → silently black). Write the typed group form: `gb = GroupBuilder(); gb:set("type", StringAttribute("color")); gb:set("value", FloatAttribute({1,0,0},3)); Interface.SetAttr("prmanStatements.attributes.user.MatteID0", gb:build())`. Same value+metadata pattern as primvars (`scope`/`inputType`/`value`). AttributeSet can't author this shape — use OpScript. |
| **PxrMatteID recipe** | Typed color user attr `user.MatteID0` per object (3 objects/slot via R/G/B, slots 0–7) → one `PxrMatteID` node (no inputs, all defaults) with `resultAOV → PxrSurface.utilityPattern[0]` on **every** contributing material → channel `name`/`source` = `MatteID0`, type `color`, **default filter** (mattes must match beauty AA — never `zmin`). Displacement/MB preserved (same render). Trimmed `interactiveOutputs` hides matte AOVs from IPR — check disk renders. Shipped example: RfK `Examples/katana_files/matteid.katana`. |
| **✅ VERIFIED: refracted mattes via U4 through transmission** | Production-tested on 26: the userColor (U4) lobe **does collect along transmitted paths**. `PxrAttribute` (attribute string `user:MatteID0` — namespaced colon form) → `PxrSurface.userColor`; channel source `lpe:nothruput;noinfinitecheck;noclamp;overwrite;C<TS>+U4L`, type color, default filter → RGB mattes of objects **seen through refraction**, distortion/displacement/MB intact, same render. Requires U4 registration (`lpe.user4`). If userColor doubles as the PxrTee keep-alive sink: `matteColor + 0×teeSum → userColor`. Cryptomatte can NOT do this (sample filter, primary-hit only, no LPE to edit) — U4 is the refracted-matte vehicle. |
| Read global attr from any location (OpScript) | `Interface.GetGlobalAttr("renderSettings.resolution", "/root")` |
| **Resolution table — two different APIs** | Python: `from Katana import ResolutionTable` → `ResolutionTable.GetResolutionTable().getResolution(name)`. **OpScript/Lua:** `ResolutionTable.GetResolution(name)` directly (no `GetResolutionTable()` — it's nil in Lua). Entry: `getXRes()`/`getYRes()`. |
| RenderSettings params are GenericAssign-style | `getParam('Node.args.renderSettings.X.value')` returns that node's **local/default** value unless X is *enabled there* — the resolved scene value can come from a different node. To read what actually won, use an OpScript on the resolved `/root` attrs. |
| Current cook time (OpScript) | `Interface.GetCurrentTime()`; OpScripts re-cook per frame (and per shutter sample under MB). |

---

## Adaptive sampling (RIS)

| Fact | Detail |
|---|---|
| **What PixelVariance actually tests** | The **change in the accumulated pixel value** as samples are added ("has the running estimate stopped moving?") — NOT the spread between individual samples. Docs: *"as each sample is added… the renderer looks to see how much the sample changes the pixel; if enough samples are added without changing the pixel much, it stops."* Selectable error metrics also exist (`contrast`, `variance`, `relativevariance`, `halfbuffer` = split-buffer comparison). |
| `minsamples` | Floor before termination is permitted; **default = √maxsamples** (docs-confirmed). Too low → fluke plateaus pass the stillness test → blotches, missed small brights, animation flicker (worst symptom; invisible on stills). Too high → flat tax on easy pixels, no quality gain. Raise above √max for heavy DOF/MB/tiny-light shots; near-zero acceptable for IPR only. |
| Tuning method | Step `minsamples` up until the image stops changing — if changing it changes the image, the lower value was terminating on unreliable evidence. Verify spend with the **sample-count AOV** (probe, don't eyeball). |
| Per-object light samples | **No per-receiver override exists** in RIS. Levers: per-LIGHT `fixedSampleCount`/importance, light linking, or adaptive sampling naturally concentrating on noisy pixels. |

---

## Motion blur (RfK)

| Fact | Detail |
|---|---|
| **`VelocityApply` node** | THE standard velocity-blur node — reads point `v`, builds motion samples, no shift. Use this, not hand-rolled P-synthesis (that's only a `dPdtime` forcing tool — [15](15-primvar-aovs-katana.md) coda). |
| Enable MB | `RenderSettings.maxTimeSamples > 1` **and** `shutterOpen < shutterClose`. For Alembic, `maxTimeSamples` is only an on/off switch (samples come from the cache/VelocityApply). |
| Velocity vs geometry blur | Single P sample + `v` = velocity blur; multi-sample P = geometry blur. Multi-sample P wins; deleting `v` guarantees no velocity blur (but kills `motionFore/Back`). |
| `motionFore`/`motionBack` | Velocity-derived, full-frame vectors. Broken by P-synthesis/deleting `v`. **Data AOVs need `filter = zmin`** (shutter-averaging inverts apparent motion: fast=diluted, slow=full). |
| Terminology | **Subframe / motion / time samples** within the shutter; 3+ samples = **multi-segment** (curved) blur. "Multi-frame" = wrong (full-frame apart → over-blur). |
| Motion vectors for Nuke VectorBlur | Must be **raster/pixel space** ("1 unit = 1 pixel"). World/camera-space velocity is wrong tool. OSL: `transform("raster", P + vel/fps) - transform("raster", P)`; watch the **Y-flip** vs Nuke. Locked cam ⇒ `dPcameradtime` ≡ `dPdtime`. |

---

## AOVs & channels (RfK 26)

| Fact | Detail |
|---|---|
| Special channel filters | `min`, `max`, `average`, `zmin`, `zmax` on `PrmanOutputChannelDefine.filter` — single-sample selection instead of convolution. **RIS honors them; XPU does not.** For depth, `min`≡`zmin`. **Default `zmin` for all data passes** (N, P, vel, IDs, Z). |
| No RIS `depthfilter` | The hider `depthfilter` is REYES-era; RIS = raytrace hider only. Per-channel filter IS the RIS mechanism. |
| zmin vs zmax identical? | They only differ on pixels whose subpixel samples span ≥2 depths; these filters sample the **front opaque surface only** (opacity thresholding) — `zmax` can't see behind opaque geo. |
| userColor (U4) | Needs **registration in Katana**: OpScript at `/root`: `Interface.SetAttr('prmanGlobalStatements.options.lpe.user4', StringAttribute("UserColor"))`. Channel source: `lpe:nothruput;noinfinitecheck;noclamp;unoccluded;overwrite;CU4L` (**`noclamp`** mandatory for signed data). U3 = world position (`user3`). |
| Multiple data AOVs | `PxrTee` per value (`aovName`), all results combined → `userColor` as keep-alive sink. See [15](15-primvar-aovs-katana.md). |
| **No `PxrOSL` node** | Compiled OSL **is** the node: `oslc` → `.oso` on `RMAN_SHADERPATH` → appears in NMC Tab menu by shader name; params auto-read from the `.oso` (no Args file). Restart/rescan to see new shaders. |
| Lights can't take pattern inputs | GafferThree lights have no network-material inputs — no wiring `raytype()` gains into `lightColor`. Per-light indirect control = LPE AOVs + comp, or surface-side `raytype("diffuse")` boost (per-material, non-physical). |

### LPE gotchas (all fail silently to black)

| Trap | Detail |
|---|---|
| **`0` vs `O`** | The emissive-object token is letter **O**. A zero parses fine and matches nothing. |
| **Mesh lights are `L`, not `O`** | `PxrMeshLight` terminates as a light (`<L.>`/`<L.'group'>`); PxrSurface glow = `O`. `...O` channels are black for mesh lights. |
| **Opacity/presence "glass" ≠ transmission** | Opacity continuation is not a scattering event — `<TS>` never matches. Only refractive lobes (PxrSurface glass, Lama dielectric) create `T` events. With opacity glass, emission-behind-glass lands in plain `lpe:CO`. |
| **No arithmetic in LPEs** | Grammar = events/operators/modifiers only. No gain/multiply — LPEs select paths, never scale them. Brightening happens at recombine, sample/display filter, or shader. |
| **Indirect per light** | `lpe:C[DS][DS]+<L.'g'>` (all indirect); `lpe:C[DS][DS][DS]+<L.'g'>` (2nd+ bounces); exact-Nth = N+1 explicit `[DS]` tokens, no `+`. Emission through glass: `lpe:C<TS>+O` (cap: `<TS><TS>` = one pane). |
| **`lpegroup`** | Tag geo via `prmanStatements.attributes.identifier.lpegroup`; reference as `<.D'foo'>`, any-event `<..'foo'>`, negate `[^'foo']`, multi `['foo''bar']`. **PxrPathTracer only.** Grouping the glass (`<TS'heroGlass'>`) is the doc-verified way to isolate per-object transmission. |
| **Debug ladder** | `lpe:C.*` (machinery) → `lpe:CO` (emitter kind) → `lpe:CS[<L.>O]` (any specular link) → target expression. First black rung names the failure. |
| **No volume token — volumes are `D`** | RenderMan LPEs have only two scattering classes (D, S) + user events; there is no `V` (that's Karma/others). Volume scattering registers as **`D`**, so `lpe:C[DS]*[<L.>O]` is the complete beauty *including* volumes — and `lpe:C[DS]*<L.'key'>` gives per-light volume contribution. |

---

## Look Files

| Fact | Detail |
|---|---|
| Lights/constraints through KLF | Bake rig location (NOT `/root/world`) → in lighting: resolve (`LookFileManager`/`LookFileResolve`) → **`LookFileLightAndConstraintActivator`** downstream (rebuilds the `/root/world` light+constraint lists — without it, baked lights don't light). Overrides go after. |
| `rootLocations` | Match the location the asset/rig was imported at. Lights under a geo group: activator still finds them (by type), but scope `rootLocations` to the light locations to avoid baking geometry deltas. |
| AttributeSet vs LookFile | Downstream wins. Implicit resolvers run at render time (after your whole recipe) — to override a look, use explicit `LookFileResolve` and put the AttributeSet after it. Material param overrides MUST be post-resolve. |

---

## Environment / meta

- **This sandbox cannot reach `learn.foundry.com` or Pixar's rmanwiki** (proxy policy denies CONNECT; only search snippets available). To make doc lookups exact: **copy the offline Katana docs into the repo** (e.g. `docs/katana/`) — then they're grep-able directly.
- Deferring OpScripts to render-resolve: AOV-primvar and P-synthesis scripts are ideal candidates; deferred attrs don't show in the interactive scene graph (view with implicit resolvers to verify). Still evaluate in IPR.
