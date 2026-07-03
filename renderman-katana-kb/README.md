# RenderMan + Katana Lighting / Lookdev / Rendering Knowledge Base

A working technical reference for a lighting lead / CG supervisor running **Pixar RenderMan** and **Foundry Katana** together on an animation feature. Covers lighting, lookdev, shading, rendering, render optimization, AOVs/LPEs, color management, and custom tool/shader development.

Compiled June 2026 from official Pixar (`rmanwiki.pixar.com` / `renderman.pixar.com` / `renderman.atlassian.net`) and Foundry (`learn.foundry.com`) documentation, release notes, OpenUSD/MaterialX/OCIO docs, and reputable trade press (CG Channel, Digital Production, fxguide). Every load-bearing fact is cited inline in the topic files.

> **How this was built & how to trust it.** Pixar's and Foundry's documentation servers block automated fetching (HTTP 403), so a number of facts were reconstructed from search-engine indexing of those exact official pages rather than full-page reads. Version numbers, release dates, node names, and architecture are corroborated across multiple independent sources and are solid. **Exact parameter spellings and numeric defaults** should be treated as strongly-indicated-but-verify against the `.args` files in your own licensed install before you bake them into pipeline code. Each file flags its weakest claims explicitly.

---

## Version-at-a-glance (mid-2026)

| Component | Your version | Released | Headline for lighting/lookdev |
|---|---|---|---|
| **RenderMan (your renderer)** | **26.x** (26.0–26.3) | Apr–Dec 2024 | The renderer that pairs with Katana 6.5v4. **RIS is your final-frame engine; XPU is interactive/lookdev only.** First **ML denoiser** (incl. interactive — the big 26.0 win). **Lama runs in RIS only.** Textures capped at 8 channels. Files 01–05 are anchored here. |
| RenderMan 27.0 (context only) | — | Nov 13 2025 | *Requires Katana 7+.* XPU **graduates to final-frame** (RIS marked for deprecation): checkpointing, deep, holdouts/mattes, OSL filters, MaterialX/Lama-in-XPU, multi-GPU. |
| RenderMan 27.1 / 27.2 (context only) | — | Dec 2025 / Feb 2026 | *Requires Katana 7+.* XPU Lama coating; textures 8→64 channels; expanded Stylized Looks (`PxrStylizedHatchControl`). |
| **Katana (your build)** | **6.5v4** | 23 Aug 2024 (6.5v1 = Nov 2023) | The Katana side of this KB is anchored here. USD **23.05**, Python **3.9.x**, **PyQt5 5.15.9** (not PySide6). Hydra "Viewer" default (HdStorm/GL). Has NetworkMaterialCreate/Edit, GafferThree, LookFiles, `UsdIn`, and 6.5's native USD authoring nodes. **Does NOT have** the 8.0 USD round-trip nodes or the 9.0 USD-layer framework. *(6.5 and 7.0 are feature twins — 6.5 on VFX Ref Platform 2022, 7.0 on 2023.)* |
| Katana 9.0 (latest, context only) | 9.0v1 | Feb 2026 | USD-layer node framework: `UsdSuperLayer`, `UsdGaffer` (lighting), `UsdMaterial`; **Hydra 2.0** alpha (`KATANA_ENABLE_HYDRA2=1`). *Not in your 6.5v4.* |
| Katana 8.0 (context only) | last point ≈ 8.0v5 (Oct 2025) | Dec 2024 | Native USD round-tripping (`KatanaToUsd`, `UsdLayerDefine/Export`, `UsdLight`); pattern-based collections; node-graph traversal ported to C++. *Not in your 6.5v4.* |

> ### ⚠️ Pipeline anchor: Katana 6.5v4 → RenderMan **26.x**
> **RenderMan-for-Katana 27 is Katana 7+ only.** RenderMan **27 dropped Katana 5/6 support**, so your Katana 6.5v4 pipeline runs **RenderMan 26.x** (RfK 26 supports Katana 5.0 / 6.0 / 6.5; RenderMan **26.3** later extended RfK up to Katana 8.0). For the **hdPrman render delegate in the 6.5 Viewer** use the **RenderMan 26** build of the 6.5 plugin — the RenderMan 25 build does **not** include it. ([rmanwiki XPU in Katana, RFK26](https://renderman.atlassian.net/wiki/spaces/RFK26/pages/20218708); [CG Channel RM27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))
>
> **Files 01–05 are anchored on RenderMan 26.x** — they describe your actual renderer. The single biggest thing this changes vs a "latest renderer" mental model: **on 26.x, XPU is interactive/lookdev only and RIS is your production final-frame engine (and is NOT deprecated).** These are all **27-only and unavailable to you**: XPU final-frame, XPU checkpointing/deep/holdouts/OSL-filters, **MaterialX/Lama-in-XPU** (so **Lama renders in RIS** for you), multi-GPU, 64-channel textures, and the expanded Stylized Looks (`PxrStylizedHatchControl`). Each 01–05 file labels 27-only items explicitly, and [01](01-renderman-core-and-xpu.md) carries a short "what's in 27" appendix purely as upgrade context. Your big 26.x win for iteration speed is the **interactive ML denoiser** (new in 26.0).

> **Katana architecture is stable 6.5 → 9.0.** The core you rely on — Ops/Geolib3(-MT), OpScript, the Python API (NodegraphAPI), GafferThree, NetworkMaterialCreate/Edit, LookFiles, Args files, `KATANA_RESOURCES` — is unchanged in shape across these releases, so files 06–08 apply directly to 6.5v4. The genuinely **newer, absent-from-6.5** pieces are the native-USD *round-trip/authoring-export* layer: **8.0** nodes (`KatanaToUsd`, `UsdLayerDefine`, `UsdLayerExport`, `UsdLight`, pattern-based collections) and the **9.0** USD-layer framework (`UsdSuperLayer`, `UsdGaffer`, `UsdMaterial`, Hydra 2.0). In 6.5 you read USD through **`UsdIn` / KatanaUsdPlugins** and author with 6.5's native USD nodes (`UsdSublayerAdd`, `UsdReferenceSet`, `UsdPayloadSet`, `UsdLayerWrite`, `UsdPrimCreate`, `UsdSchemaSet`, `UsdPrimvarSet`, …). Newer items are marked *(8.0+/9.0 — not in 6.5)* wherever they appear.

---

## The big strategic shifts to internalize

1. **On 26.x, RIS is your final-frame engine; XPU is interactive only.** Render all finals in **RIS** (fully featured, not deprecated in 26). Use **XPU** for fast lookdev/lighting iteration in the Katana viewer (hdPrman XPU-CPU/XPU-GPU IPR). The "XPU graduates to final-frame, RIS deprecated" story is a **RenderMan 27** event that needs Katana 7+ — it's your future upgrade path, not your current reality.
2. **Reach for RIS specifically for** (all of which XPU can't do on 26): **VCM/bidirectional/photon-mapped caustics**, **deep output**, **holdouts/mattes**, **checkpointed farm renders**, **Lama-shaded** everything, **many-light** shots beyond a few hundred lights, and scenes exceeding GPU VRAM. Since finals are RIS anyway, this is rarely a constraint.
3. **MaterialX Lama is the strategic material path — but render it in RIS on 26.** Author new looks in **LamaSurface + LamaLayer** stacks for energy-conserving layering + USD/MaterialX portability; keep **PxrSurface** for the proven uber-shader and **PxrLayerSurface** for native layering of legacy assets. Just remember XPU IPR won't evaluate Lama on 26 — lean on RIS for Lama lookdev.
4. **USD is the pipeline backbone.** In **your Katana 6.5v4**, USD comes in through **`UsdIn` / KatanaUsdPlugins** (the classic import/translation path); native USD *authoring/round-trip* nodes are an 8.0+/9.0 feature you don't yet have. RenderMan participates as the **hdPrman** Hydra render delegate. Solaris (Houdini/LOPs) and Katana both read the same USD — common pattern is Solaris for procedural set-dressing/layout → USD hand-off → Katana for hero lighting/lookdev.
5. **OSL is the pattern language; Bxdf/Displace plugins replace closures.** You write OSL *patterns* (compiled with `oslc`), not OSL *materials*. RSL/Reyes are long retired (RSL deprecated in RenderMan 21, 2016).

---

## Contents

| # | File | What's inside |
|---|---|---|
| 01 | [`01-renderman-core-and-xpu.md`](01-renderman-core-and-xpu.md) | Versions & release timeline; RIS vs XPU architecture & parity gaps; integrators (PxrPathTracer/PxrUnified/PxrVCM/PxrOcclusion); sampling (PixelVariance, min/max samples, trace depth); denoising (ML / OptiX / cross-frame). |
| 02 | [`02-render-optimization.md`](02-render-optimization.md) | Sampling strategy & denoiser-driven sample reduction; ray-depth/MIS/caustics; geometry/displacement/instancing/procedurals; texture pipeline (txmake/.tex/RtxPlugin); trace sets; checkpointing & recover; deep vs flat; threading/RAM/farm; XPU VRAM at scale. |
| 03 | [`03-renderman-shading.md`](03-renderman-shading.md) | PxrSurface lobe set; MaterialX **Lama** (full node library + layering model); PxrLayerSurface/PxrLayer/PxrLayerMixer; OSL & the Pxr pattern library; RSL→RIS→OSL history; hair/skin-SSS/glass/fabric; Stylized Looks / NPR. |
| 04 | [`04-renderman-lighting.md`](04-renderman-lighting.md) | Light types (Rect/Disk/Sphere/Cylinder/Distant/Dome/Portal/Mesh/EnvDayLight); common params (intensity/exposure/temperature/MIS); light filters (Blocker/Rod/Gobo/Cookie/Barn/Ramp/IntMult/Combiner); light linking, light groups, IES, dome+portal IBL. |
| 05 | [`05-aovs-lpes-outputs.md`](05-aovs-lpes-outputs.md) | LPE grammar (event letters, operators, examples); standard AOV preset set & beauty decomposition; per-light AOVs / light groups; holdouts, Cryptomatte, deep EXR; display drivers (`d_openexr`); denoiser AOV requirements. |
| 06 | [`06-katana.md`](06-katana.md) | Katana 8.x/9.0 versions & what's new; architecture (deferred scene graph, Ops/Geolib3-MT, recipe vs scene graph, working sets); Hydra viewer/Monitor/Catalog; lookdev (NetworkMaterialCreate/Edit, LookFiles); lighting (GafferThree, LightLink, Lighting Tools); render settings & live rendering. |
| 07 | [`07-katana-renderman-integration.md`](07-katana-renderman-integration.md) | RenderMan for Katana (RfK): install/path; PrmanGlobalSettings/PrmanObjectSettings; hdPrman in the viewer (RIS/XPU-CPU/XPU-GPU); interactive/live rendering; AOV/ID setup in Katana; farm dispatch (Tractor/Farm API). |
| 08 | [`08-katana-customization.md`](08-katana-customization.md) | OpScript (Lua) & the cook `Interface`; C++ Geolib Ops; Python API (NodegraphAPI, Callbacks, RenderingAPI, UI4 tabs); Macros/SuperTools/NodeTypeBuilder; GafferThree custom packages; Args files & GenericAssign; renderer plug-ins; `KATANA_RESOURCES` bootstrap. |
| 09 | [`09-usd-solaris-pipeline.md`](09-usd-solaris-pipeline.md) | Katana's USD support (KatanaUsdPlugins/usdKatana/UsdIn); read/write/layer USD; USD vs Katana scene graphs; Solaris/LOPs vs Katana; MaterialX as interchange; Hydra render delegates incl. hdPrman. |
| 10 | [`10-lookdev-color-workflow.md`](10-lookdev-color-workflow.md) | Lookdev rigs & calibration (grey/chrome ball, Macbeth); color management (ACES / OCIO v2 in RenderMan, Katana, Nuke); multi-shot/template lighting; relighting via light groups; slap comp; Nuke comp (multichannel/cryptomatte/deep). |

### Artist workflow guides (process & tools — start here for day-to-day)

| # | File | What's inside |
|---|---|---|
| 11 | [`11-shot-lighting-workflow.md`](11-shot-lighting-workflow.md) | The shot-lighting artist's click-path: ingest → render settings → block lights (GafferThree) → XPU IPR loop → AOV/output setup → RIS final on farm → slap comp/dailies → comp hand-off. Per-shot checklist. |
| 12 | [`12-lookdev-workflow.md`](12-lookdev-workflow.md) | The lookdev artist's process: turntable rig, material build (NetworkMaterialCreate, Lama/PxrSurface, Material Solo), calibration, IPR iteration, multi-environment QC, LookFile publish, sign-off. Per-asset checklist. |
| 13 | [`13-lead-templates-team-process.md`](13-lead-templates-team-process.md) | What you set up as lead: the shot template, master rigs & sequence propagation, naming/AOV/version conventions, color pipeline, farm policy, review/dailies, onboarding. Lead setup checklist. |
| 14 | [`14-custom-tools-to-build.md`](14-custom-tools-to-build.md) | Tools to build for the team (PyQt5/Python/OpScript on 6.5): shot/template builder, AOV setup tool, light-group/naming checker, custom GafferThree rig packages, scene validator, relight slap-comp exporter. Tooling checklist. |

### Deep-dive recipes & troubleshooting

| # | File | What's inside |
|---|---|---|
| 15 | [`15-primvar-aovs-katana.md`](15-primvar-aovs-katana.md) | Getting Houdini FX-cache primvars (velocity, Cd, id, age, world position) out as AOVs in RfK. Why `dPdtime` fails on velocity-blur particles; promoting `geometry.point.v` → `geometry.arbitrary.v` (the **`vector3` vs `vector` inputType** trap); single-AOV via `userColor`/U4 (incl. the **mandatory U4 lobe registration** + `CU4L`/`noclamp` LPE); multi-AOV via `PxrTee` (+ the keep-alive gotcha); units (`1/FPS`) & coordinate-space (`color` vs `vector`); a bisection-test troubleshooting table. |
| 16 | [`16-katana-quick-reference.md`](16-katana-quick-reference.md) | Session-verified quick reference: parameter-expression facts (`getParam` returns a reference, `getresdict()` for resolution, `__import__` in expressions), CEL syntax + performance rules, primvar/attribute conventions (reserved names, `inputType`, `visible`), motion blur (`VelocityApply`, filters for data AOVs), AOV/channel filters (`zmin`, RIS-only), OSL-as-node workflow, Look File lights/constraints activator, AttributeSet-vs-resolve ordering. |

---

## Cross-cutting cheat-sheet

**Engine choice (26.x)**
- Interactive lookdev / lighting iteration in the viewer → **XPU** (IPR)
- **All final frames**, Lama, caustics (VCM), deep, holdouts, checkpointing, many-light → **RIS**

**Material choice**
- New / layered / portable look → **Lama** (LamaSurface + LamaLayer)
- Proven single uber-shader → **PxrSurface**
- Native layering of legacy PxrSurface assets → **PxrLayerSurface / PxrLayer / PxrLayerMixer**
- Hair → **LamaHairChiang** (modern) over **PxrMarschnerHair** (legacy)
- Hero skin → **path-traced (exponential) SSS**; cheap translucency → dipole/Burley

**Relighting in comp** = per-light **light groups** (`__group` parameter) → per-group AOVs via LPE (`lpe:diffuse_key` short form or `lpe:CD<L.'key'>` long form — always `<L.>`, never bare `L`).

**Color** = render & store EXRs in **scene-linear ACEScg**, archive in **ACES2065-1**, apply the ACES Output Transform only as a display/view at comp time; drive RenderMan, Katana, and Nuke from the **same `config.ocio`** (`OCIO` env var).
