# 11 — Shot-Lighting Artist Workflow (Katana 6.5v4 + RenderMan 26.x)

> The day-to-day click-path a lighting artist follows to take a shot from ingest to comp hand-off. Anchored on **Katana 6.5v4 + RenderMan 26.x** (RIS finals, XPU IPR). Cross-refs: lights → [04](04-renderman-lighting.md), AOVs/LPEs → [05](05-aovs-lpes-outputs.md), RfK setup → [07](07-katana-renderman-integration.md), color/comp → [10](10-lookdev-color-workflow.md).

---

## The shot at a glance

```
ingest → render settings → block lights → IPR iterate → AOVs/outputs →
refine → final (RIS) on farm → slap comp / dailies → publish to comp
```

Mantra for 26.x: **iterate in XPU IPR, render finals in RIS.** Keep the interactive ML denoiser on for fast judgement.

---

## 1. Ingest / scene assembly

1. **Open the sequence lighting template**, not an empty scene (your lead's master recipe — see [13](13-lead-templates-team-process.md)). It already has ingest, render settings, base AOVs, and a master light rig wired up.
2. **Point the ingest at this shot** — usually a `UsdIn` (or the studio's shot-assembly macro) bringing in: published **camera**, **animation caches**, **sets/environments**, and **published lookdev** (materials via assigned LookFiles or USD-bound materials). Confirm frame range.
3. **Verify the scene graph** (Scene Graph tab): cameras under the expected path, geometry present, materials resolved (not red/unassigned). Use a **Working Set** to load only what you need for responsiveness — 6.5 supports Viewer Visibility / Payload / Active-Prim working sets.
4. **Set the look camera** in `RenderSettings` and frame it in the Viewer.

**Gotcha:** if materials show unresolved, the LookFile/USD material binding didn't resolve — check the asset version and the `lookfile.asset` assignment before you start lighting.

---

## 2. Render settings (once per shot, from the template)

1. **`RenderSettings`** — active camera, resolution, crop window, the **outputs** list, and `interactiveOutputs` (which AOVs stream during IPR).
2. **`PrmanGlobalSettings`** — the **Integrator** (`PxrPathTracer` for most shots) and the **Hider**: `PixelVariance` (start ~0.05–0.1 for IPR, tighten for final), `maxsamples` ceiling, `minsamples` (= √maxsamples). See sampling detail in [01](01-renderman-core-and-xpu.md) §4.
3. **Pick the IPR backend:** hdPrman in the Viewer → **XPU-GPU** (or XPU-CPU if VRAM-bound) for fast feedback. Remember **Lama-shaded assets need RIS to evaluate correctly on 26** — if your hero assets are Lama, do look-critical judgement in **RIS IPR**, use XPU for blocking. ([07](07-katana-renderman-integration.md) §3)
4. **Interactive denoiser ON** — the RenderMan **interactive ML denoiser** lets you read the image in a few samples instead of waiting for convergence. (OptiX is the alternative in the IPR denoiser dropdown.)

---

## 3. Block the lights (GafferThree)

Work big-to-small. Build inside one **`GafferThree`** node (or the template's existing gaffer).

1. **Environment / key fill first.** Add a **`PxrDomeLight`** with the shot's HDRI (rotation-only — orient to match the plate). This gets you most of the way.
2. **Key light** — `PxrRectLight` or `PxrDistantLight` (sun). Set with **exposure** (stops) first, then **intensity** for fine trim; **temperature** for warm/cool.
3. **Fill, rim/kick, practicals** — add as needed; `PxrMeshLight` for emissive shapes/neon.
4. **Name every light and put it on a `__group`** (e.g. `key`, `fill`, `rim`, `bounce`) — this is what makes per-light AOVs and comp relighting possible later. **Do this as you create them**, not retroactively. ([04](04-renderman-lighting.md) §4, [05](05-aovs-lpes-outputs.md) §3)
5. **Place interactively** with **Lighting Tools** (press **`L`** in the Viewer) against a live render — click to position lights in screen space.
6. **Light linking** — use the **`LightLink`** node (GafferThree does this internally) to include/exclude specific objects from specific lights.
7. **Shaping** — add light filters as needed: barn doors (`PxrBarnLightFilter`), blockers/rods (`PxrBlockerLightFilter`/`PxrRodLightFilter`), gobos/cookies, ramps, intensity multipliers. ([04](04-renderman-lighting.md) §3)
8. **Interiors:** put a **`PxrPortalLight`** over every window/skylight feeding the dome — the single biggest noise/time win for indirectly-lit interiors.

---

## 4. The IPR iteration loop

This is where you spend most of your time.

1. **Start the live render** (XPU IPR, denoiser on). Edits stream live: light params/transforms, material params, adding lights, ROI/crop/res.
2. **Solo to diagnose** — solo individual lights/groups to see each contribution; solo AOVs to check diffuse vs specular balance.
3. **A/B with snapshots** — **"Create Snapshot in Catalog"** in the Monitor's Live Render menu. Snapshot a version, make a change, compare in the Catalog. This is your visual history during a session.
4. **Use ROI / crop** to iterate fast on a hero region (faces, hero materials) without re-rendering the full frame.
5. **Check exposure against neutral** — keep a grey/chrome ball or the comp's reference handy; judge mid-grey, not just "looks nice."
6. **Watch noise sources** — fireflies from small bright lights → pin them with **`fixedsamplecount`** instead of raising the global budget; caustics/glass noise → note these for a RIS pass (XPU can't VCM on 26).

**Tip:** keep `interactiveOutputs` to a lean set (beauty + a couple of diagnostic AOVs) so IPR stays fast; the full AOV stack is for the final render.

---

## 5. AOVs / outputs setup

In Katana, AOVs are **`PrmanOutputChannelDefine`** (declares the channel + its `lpe:` source) wired into **`RenderOutputDefine`** (the file/driver). See [05](05-aovs-lpes-outputs.md) for LPE grammar.

**Standard shot stack:**
- **Beauty** (`Ci`) + the additive lobe set: `directDiffuse`, `indirectDiffuse`, `directSpecular`, `indirectSpecular`, `subsurface`, `emissive`, `albedo`.
- **Per-light-group AOVs** for every `__group` (`lpe:diffuse_key`, `lpe:specular_key`, …) — your relight controls in comp. Always `<L.'name'>`, never bare `L`.
- **Data passes:** `Z` (depth/DOF), `normal`, world position (PxrSurface U3 / `P`), motion vectors (`forward`/`backward` for comp motion blur + cross-frame denoise).
- **IDs:** `PxrCryptomatte` (one filter per-object, another per-material) for comp mattes.
- **Denoiser inputs:** `Ci`, `albedo`(+var), `normal`(+var), motion vectors; `raw` channel type; `_variance.exr` master. ([05](05-aovs-lpes-outputs.md) §5)
- **Deep** only where comp needs depth merging (volumes, holdout-heavy layers) — RIS-only on 26, costly.

Drive these from the lead's standard output template so naming/channels are consistent across the show ([13](13-lead-templates-team-process.md)).

---

## 6. Final render (RIS) + farm

1. **Switch the render to RIS** for finals (XPU is interactive-only on 26).
2. **Tighten sampling:** lower `PixelVariance`, set the final `maxsamples`; lean on the denoiser to cut samples (denoiser-driven reduction — [02](02-render-optimization.md) §1).
3. **Checkpoint + recover:** enable `-checkpoint` and rely on `-recover 1` for resilient, resumable farm renders (RIS). ([02](02-render-optimization.md) §6)
4. **Submit to the farm** via **Tractor** (RfK batch render, or local RIB generation). ([07](07-katana-renderman-integration.md) §5)
5. **Spot-check the first frames** before committing the full range — confirm AOVs present, no clipping, denoise clean.

---

## 7. Slap comp, dailies, hand-off

1. **Slap comp** — assemble the per-lobe/per-group AOVs into a recomposed beauty in the studio Nuke template; relight by scaling/tinting light-group AOVs without re-rendering. ([10](10-lookdev-color-workflow.md) §3–4)
2. **Dailies** — submit the slap (or rendered) frames; capture supe notes against named light groups ("warm the key half a stop, kill the rim spill") which map directly back to your gaffer.
3. **Comp hand-off** — deliver the multichannel EXR (Shuffle-ready), Cryptomatte (+ JSON manifest), and deep where flagged. Confirm the **same OCIO config** is used end-to-end (ACEScg working space). ([10](10-lookdev-color-workflow.md) §4)

---

## Per-shot checklist
- [ ] Opened from sequence template; shot ingested; materials resolved; look camera set.
- [ ] RenderSettings + PrmanGlobalSettings from template; XPU IPR + interactive denoiser.
- [ ] Dome/key/fill/rim built; **every light named + on a `__group`**; portals on interiors.
- [ ] Light links and filters set; exposure judged against neutral.
- [ ] Full AOV stack wired (lobes + per-group + data + crypto + denoiser inputs).
- [ ] Final = **RIS**, tightened samples, checkpoint/recover, farm-submitted.
- [ ] Slap comp built; dailies submitted; comp hand-off delivered (EXR/crypto/deep, ACEScg).
