# RenderMan + Katana Lighting / Lookdev / Rendering Knowledge Base

A working technical reference for a lighting lead / CG supervisor running **Pixar RenderMan** and **Foundry Katana** together on an animation feature. Covers lighting, lookdev, shading, rendering, render optimization, AOVs/LPEs, color management, and custom tool/shader development.

Compiled June 2026 from official Pixar (`rmanwiki.pixar.com` / `renderman.pixar.com` / `renderman.atlassian.net`) and Foundry (`learn.foundry.com`) documentation, release notes, OpenUSD/MaterialX/OCIO docs, and reputable trade press (CG Channel, Digital Production, fxguide). Every load-bearing fact is cited inline in the topic files.

> **How this was built & how to trust it.** Pixar's and Foundry's documentation servers block automated fetching (HTTP 403), so a number of facts were reconstructed from search-engine indexing of those exact official pages rather than full-page reads. Version numbers, release dates, node names, and architecture are corroborated across multiple independent sources and are solid. **Exact parameter spellings and numeric defaults** should be treated as strongly-indicated-but-verify against the `.args` files in your own licensed install before you bake them into pipeline code. Each file flags its weakest claims explicitly.

---

## Version-at-a-glance (mid-2026)

| Component | Current version | Released | Headline for lighting/lookdev |
|---|---|---|---|
| **RenderMan** | **27.2** | Feb 2026 | XPU is now the production final-frame renderer; RIS marked for deprecation (still ships). 27.0 = "biggest release in 10 years." Textures up to 64 channels; expanded Stylized Looks; OpenPBR/USD refinement. |
| **RenderMan 27.0** | — | Nov 13 2025 | XPU graduates to final-frame: checkpointing, deep data, holdouts/mattes, OSL filters, MaterialX evaluation, multi-GPU, interactive ML denoising all land in XPU. |
| **RenderMan 27.1** | — | Dec 2025 | XPU checkpoint fix; XPU **Lama coating absorption** support (base nodes change absorption as a LamaLayer top). |
| **RenderMan 26** | — | Apr 2024 | Major XPU expansion + first **ML denoiser** (incl. interactive). Lama documented across full node library (RIS). |
| **Katana (your build)** | **6.5v4** | 23 Aug 2024 (6.5v1 = Nov 2023) | The Katana side of this KB is anchored here. USD **23.05**, Python **3.9.x**, **PyQt5 5.15.9** (not PySide6). Hydra "Viewer" default (HdStorm/GL). Has NetworkMaterialCreate/Edit, GafferThree, LookFiles, `UsdIn`, and 6.5's native USD authoring nodes. **Does NOT have** the 8.0 USD round-trip nodes or the 9.0 USD-layer framework. *(6.5 and 7.0 are feature twins — 6.5 on VFX Ref Platform 2022, 7.0 on 2023.)* |
| Katana 9.0 (latest, context only) | 9.0v1 | Feb 2026 | USD-layer node framework: `UsdSuperLayer`, `UsdGaffer` (lighting), `UsdMaterial`; **Hydra 2.0** alpha (`KATANA_ENABLE_HYDRA2=1`). *Not in your 6.5v4.* |
| Katana 8.0 (context only) | last point ≈ 8.0v5 (Oct 2025) | Dec 2024 | Native USD round-tripping (`KatanaToUsd`, `UsdLayerDefine/Export`, `UsdLight`); pattern-based collections; node-graph traversal ported to C++. *Not in your 6.5v4.* |

> ### ⚠️ Critical compatibility constraint: Katana 6.5v4 → RenderMan **26.x** (not 27)
> **RenderMan-for-Katana 27 is Katana 7+ only.** RenderMan **27 dropped Katana 5/6 support**, so a real Katana 6.5v4 pipeline tops out at **RenderMan 26.x** (RfK 26 supports Katana 5.0 / 6.0 / 6.5; RenderMan **26.3** later extended RfK up to Katana 8.0). For the **hdPrman render delegate in the 6.5 Viewer** you must use the **RenderMan 26** build of the 6.5 plugin — the RenderMan 25 build of the 6.5 plugin does **not** include it. ([rmanwiki XPU in Katana, RFK26](https://renderman.atlassian.net/wiki/spaces/RFK26/pages/20218708); [CG Channel RM27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))
>
> **How this KB handles that:** you originally asked for "the latest RenderMan," so files **01–05** document RenderMan through **27.2** in full — that's the forward-looking knowledge and is accurate for the renderer in isolation. But **in your integrated Katana 6.5v4 pipeline, the renderer is RenderMan 26.x.** Everything in 01–05 that is flagged as a **27.0/27.1/27.2** feature (XPU-as-final-frame, XPU checkpointing/deep/holdouts/MaterialX, Lama coating in XPU, 64-channel textures, expanded Stylized Looks) is **not available to you until you move to Katana 7+**. On 26.x: XPU exists but RIS is still the primary final-frame engine, Lama runs in RIS, and the ML denoiser (new in 26) is available. **If your renderer is actually 26.x, tell me and I'll re-anchor 01–05 to drop the 27-only material.**

> **Katana architecture is stable 6.5 → 9.0.** The core you rely on — Ops/Geolib3(-MT), OpScript, the Python API (NodegraphAPI), GafferThree, NetworkMaterialCreate/Edit, LookFiles, Args files, `KATANA_RESOURCES` — is unchanged in shape across these releases, so files 06–08 apply directly to 6.5v4. The genuinely **newer, absent-from-6.5** pieces are the native-USD *round-trip/authoring-export* layer: **8.0** nodes (`KatanaToUsd`, `UsdLayerDefine`, `UsdLayerExport`, `UsdLight`, pattern-based collections) and the **9.0** USD-layer framework (`UsdSuperLayer`, `UsdGaffer`, `UsdMaterial`, Hydra 2.0). In 6.5 you read USD through **`UsdIn` / KatanaUsdPlugins** and author with 6.5's native USD nodes (`UsdSublayerAdd`, `UsdReferenceSet`, `UsdPayloadSet`, `UsdLayerWrite`, `UsdPrimCreate`, `UsdSchemaSet`, `UsdPrimvarSet`, …). Newer items are marked *(8.0+/9.0 — not in 6.5)* wherever they appear.

---

## The big strategic shifts to internalize

1. **XPU is the future; RIS is legacy.** As of RenderMan 27, the hybrid CPU+GPU **XPU** engine is the production final-frame renderer and **RIS is officially marked for deprecation** (maintenance mode). Plan migration, but keep RIS in your back pocket for the few things XPU still can't do — see #2.
2. **Keep RIS for: VCM/bidirectional/photon-mapped caustics, extreme many-light shots (hundreds+), and scenes that exceed GPU VRAM** (XPU has no out-of-core; multi-GPU does **not** pool memory — the scene must fit in *each* GPU). CPU-only XPU is the over-budget fallback and yields matching pixels.
3. **MaterialX Lama is the strategic material path.** Author new looks in **LamaSurface + LamaLayer** stacks for energy-conserving layering and USD/MaterialX portability; keep **PxrSurface** for the proven monolithic uber-shader and **PxrLayerSurface** for native (non-MaterialX) layering of legacy assets.
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

---

## Cross-cutting cheat-sheet

**Engine choice per shot**
- Look-dev / interactive lighting, GPU final frames, scenes that fit VRAM → **XPU**
- Caustics (VCM/BDPT/photon), 100s+ of lights, over-VRAM scenes → **RIS**

**Material choice**
- New / layered / portable look → **Lama** (LamaSurface + LamaLayer)
- Proven single uber-shader → **PxrSurface**
- Native layering of legacy PxrSurface assets → **PxrLayerSurface / PxrLayer / PxrLayerMixer**
- Hair → **LamaHairChiang** (modern) over **PxrMarschnerHair** (legacy)
- Hero skin → **path-traced (exponential) SSS**; cheap translucency → dipole/Burley

**Relighting in comp** = per-light **light groups** (`__group` parameter) → per-group AOVs via LPE (`lpe:diffuse_key` short form or `lpe:CD<L.'key'>` long form — always `<L.>`, never bare `L`).

**Color** = render & store EXRs in **scene-linear ACEScg**, archive in **ACES2065-1**, apply the ACES Output Transform only as a display/view at comp time; drive RenderMan, Katana, and Nuke from the **same `config.ocio`** (`OCIO` env var).
