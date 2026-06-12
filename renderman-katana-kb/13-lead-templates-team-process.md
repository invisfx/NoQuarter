# 13 — Lead: Templates, Conventions & Team Process

> What you set up **as the lighting lead** so a team of artists is fast, consistent, and reviewable. Anchored on **Katana 6.5v4 + RenderMan 26.x**. This is the layer that makes [11](11-shot-lighting-workflow.md) and [12](12-lookdev-workflow.md) repeatable across a crew. Tools to build this are in [14](14-custom-tools-to-build.md).

---

## 1. The shot template (your highest-leverage artifact)

A master Katana recipe every artist opens instead of starting blank. It guarantees structure and frees artists to light, not plumb.

**Contents:**
1. **Standardized ingest** — a `UsdIn`/shot-assembly block with conventional locations for camera, anim, sets, and lookdev bindings.
2. **Render settings preset** — `RenderSettings` (res/crop) + `PrmanGlobalSettings` (integrator, Hider defaults) tuned per show; IPR backend set to XPU, interactive denoiser on.
3. **Base light rig** — the sequence master rig (or a stub) so the artist starts with key/fill/dome in place.
4. **Standard AOV/output graph** — the full channel stack pre-wired (`PrmanOutputChannelDefine → RenderOutputDefine`), so AOVs are identical show-wide.
5. **Render nodes** — preview / disk / live, plus a farm-submit node.
6. **Annotated node layout** — backdrop groups labeled (INGEST / LIGHTING / OUTPUTS / RENDER) so any artist can navigate any artist's scene.

Deliver it as a **template `.katana` file** and/or a **macro/SuperTool** ([14](14-custom-tools-to-build.md)). Version it; communicate changes.

---

## 2. Master light rigs & sequence propagation

1. **Build the sequence "hero" rig once** — dome + key/fill/rim with the established mood, each light **named and on a `__group`**.
2. **Propagate via template inheritance** — shots open from the sequence template carrying the master rig; artists add **per-shot overrides** (Katana's scene-graph-location override model) on top rather than rebuilding.
3. **Keep the rig re-lightable** — because every light is grouped, sequence-wide changes can often be made in comp via light-group AOVs (a half-stop on `key` across the sequence) instead of re-rendering.
4. **When the master rig changes**, decide: re-issue the template (artists re-inherit) vs comp-side fix. Track which shots have diverged.
5. **(9.0 `UsdGaffer` is not available on 6.5)** — your propagation lives in Katana templates + GafferThree + LookFile/USD composition, not the USD-layer gaffer framework.

---

## 3. Naming & convention standards (write them down once)

| Thing | Convention example | Why |
|---|---|---|
| **Lights** | `key`, `fill`, `rim`, `bounce`, `prac_<name>` | predictable, self-documenting |
| **Light `__group`** | matches light role (`key`, `fill`, …) | drives per-group AOVs + comp relight |
| **AOV channels** | the standard lobe set + `lpe:<lobe>_<group>` | identical across show → comp templates "just work" |
| **Render outputs** | `<show>_<seq>_<shot>_<pass>_v###` | farm + comp + review traceability |
| **Versions** | zero-padded `v###`; publish + workfile | clean roll-back |

The single most important rule to enforce: **every light is named and grouped at creation.** Everything downstream (AOVs, relight, dailies notes) depends on it.

---

## 4. AOV / output policy

Define the **one** standard output stack ([05](05-aovs-lpes-outputs.md), [11](11-shot-lighting-workflow.md) §5) so comp gets the same channels every time:
- Beauty + additive lobes (`directDiffuse`, `indirectDiffuse`, `directSpecular`, `indirectSpecular`, `subsurface`, `emissive`, `albedo`).
- Per-light-group AOVs for every `__group`.
- Data: `Z`, `normal`, `P`/world-position, motion vectors.
- IDs: `PxrCryptomatte` (per-object + per-material).
- Denoiser inputs (`Ci`, `albedo`+var, `normal`+var, motion vectors; `raw`; `_variance.exr`).
- **Deep policy:** deep is RIS-only on 26 and costly — define *which* element types get deep (volumes, holdout-heavy) rather than blanket-enabling.

Ship this as the template's output graph + a one-click setup tool ([14](14-custom-tools-to-build.md)).

---

## 5. Color pipeline (lock it early)

- **One OCIO config** (`OCIO` env var) shared by **RenderMan, Katana, and Nuke**; rendering space **ACEScg**, archive **ACES2065-1**, ACES Output Transform applied as a **view** at display/comp only. ([10](10-lookdev-color-workflow.md) §2)
- **Texture color-space tagging** standard so `txmake` conversions are consistent. ([12](12-lookdev-workflow.md) §2)
- Verify the same config on artist workstations and the farm.

---

## 6. Render farm policy (26.x)

- **Finals = RIS.** Standardize a sample budget (`PixelVariance` + `maxsamples`) and the denoiser config; lean on denoiser-driven sample reduction. ([02](02-render-optimization.md))
- **Always checkpoint + recover** (RIS) for resumable/preemptible farm renders. ([02](02-render-optimization.md) §6)
- **Tractor** submission via RfK (batch or local RIB). ([07](07-katana-renderman-integration.md) §5)
- **Texture prep** standard: mipmapped `.tex`, 8-channel cap; budget the texture cache.
- Publish per-asset/per-shot render-time targets so artists know the budget.

---

## 7. Review / dailies process

1. **Slap-comp template** (Nuke) that auto-assembles the standard AOVs → recomposed beauty + per-group relight controls. Because AOV naming is standardized, one template serves the whole show. ([10](10-lookdev-color-workflow.md) §3)
2. **Snapshot convention** — artists save Catalog snapshots at iteration milestones for self-review and lead check-ins.
3. **Turntable/lookdev standard** — fixed rig, conditions, and AOV breakdown for asset sign-off ([12](12-lookdev-workflow.md) §7).
4. **Notes vocabulary tied to light groups** — supe notes reference group names ("warm `key` +½ stop, reduce `rim` spill") so they map directly to gaffer edits or comp relight.
5. **Dailies cadence** — IPR snapshots/slaps for in-progress, RIS finals for finaled shots.

---

## 8. Onboarding & docs

- A short "lighting on this show" doc: where the template lives, conventions, OCIO setup, farm policy, the slap-comp template, and the **26.x rule (RIS finals / XPU IPR / Lama-in-RIS)** so new artists don't reach for 27-only features.
- Point artists at this KB's [11](11-shot-lighting-workflow.md) and [12](12-lookdev-workflow.md) for the step-by-step.

---

## Lead setup checklist
- [ ] Shot template (.katana / macro) with ingest, render settings, base rig, AOV stack, render+farm nodes, labeled layout.
- [ ] Sequence master rig built; propagation + override policy defined.
- [ ] Naming/convention doc published (lights, groups, AOVs, outputs, versions).
- [ ] Single standard AOV/output stack + one-click setup tool.
- [ ] OCIO/ACEScg locked across RenderMan/Katana/Nuke + farm.
- [ ] Farm policy: RIS finals, sample budget, checkpoint/recover, Tractor, texture standard.
- [ ] Slap-comp template + snapshot/dailies/turntable conventions.
- [ ] Onboarding doc with the 26.x ground rules.
