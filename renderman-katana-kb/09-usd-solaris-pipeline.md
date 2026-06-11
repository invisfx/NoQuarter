# 09 — USD / Solaris Pipeline Context (Katana 6.5v4)

> **Your USD stack: Katana 6.5v4 ships USD 23.05.** 6.5 has a **native USD framework with authoring/composition nodes**, but **not** the 8.0 round-trip/export nodes or the 9.0 USD-layer framework. You read USD via **`UsdIn` / KatanaUsdPlugins** and author with 6.5's native USD nodes. Foundry/Pixar docs 403 automated fetch — facts from indexed pages + release-note mirror.

---

## 1. Katana's USD support in 6.5

- **KatanaUsdPlugins** — node types + libraries to load/manipulate USD in Katana, matching Pixar's original `usdKatana`. Originally authored by Pixar, **removed from core USD in USD 20.05**, now **Foundry-maintained** (`TheFoundryVisionmongers/KatanaUsdPlugins`). ([KatanaUsdPlugins](https://github.com/TheFoundryVisionmongers/KatanaUsdPlugins); [OpenUSD: Katana USD Plugins](https://openusd.org/docs/Katana-USD-Plugins.html))
- **`UsdIn`** — imports USD assets into Katana's scene graph (the "classic" translation path); imports `material.layout` so USD shading nodes are editable in NME. ([UsdIn ref](https://learn.foundry.com/katana/Content/rg/misc_nodes/usdin.html))
- **6.5 native USD authoring/composition nodes:** `UsdSublayerAdd`, `UsdInheritSet`, `UsdReferenceSet`, `UsdPayloadSet`, `UsdSpecializeSet`, `UsdLayerWrite`, `UsdPythonWrite`, `UsdPrimCreate`, `UsdSchemaSet`, `UsdPrimvarSet`, plus **`FnUsdAbstraction`** for custom USD frameworks. ([Katana 6.5v1 RN](https://learn.foundry.com/katana/Content/release_notes/6.5/Katana_6.5v1_ReleaseNotes.html))

### What 6.5 does NOT have (so you don't reach for it)
- **8.0:** `KatanaToUsd`, `UsdLayerDefine`, `UsdLayerExport`, `UsdLight` (native USD round-trip/export + native USD light), pattern-based collections.
- **9.0:** `UsdSuperLayer`, `UsdGaffer`, `UsdMaterial`, Hydra 2.0.

> Practical consequence: in 6.5 you **read/compose** USD and can author layers with the native nodes, but full Katana→USD **round-tripping/export of your Geolib edits** as USD is an 8.0 capability. Plan your USD authoring around the native composition nodes you have, or bake to Look Files for downstream.

---

## 2. USD scene graph vs Katana scene graph

- **Read:** `UsdIn` / KatanaUsdPlugins translate USD prims into Katana scene-graph locations + attributes.
- **Two models coexist:** USD's stage/layer **composition** vs Katana's **deferred Geolib** scene graph. In 6.5 the native USD framework lets you author on a USD layer (composition nodes), while Geolib remains the evaluation engine for the recipe.
- **Interop fidelity** (which attribute conventions survive a round-trip) is workflow-dependent — test in your pipeline. Full bidirectional round-trip tooling is 8.0+.

---

## 3. Solaris (Houdini/LOPs) vs Katana

- **Solaris/LOPs** is SideFX's USD context for "lookdev, layout and lighting of shots" — node-based USD creation/management/execution. ([Solaris, SideFX](https://www.sidefx.com/products/houdini/lookdev/solaris/); [How LOPs work](https://www.sidefx.com/docs/houdini/solaris/about_lops.html))
- **Complement, not just compete.** Solaris excels at *procedurally generating* USD (expressions, procedural instancing/crowds). Both tools read the same USD, so a common pattern is **Solaris for procedural set-dressing/layout/instancing → USD hand-off → Katana for hero lighting/lookdev**. ([odforce discussion](https://forums.odforce.net/topic/42246-houdini-or-katana/))
- **Adoption reality:** studios invested in Katana cite high switching cost and still need Houdini for sim/procedural work, so the two coexist. *(Forum/vendor sourcing — directional, not benchmarked.)*

---

## 4. MaterialX as interchange; Hydra render delegates (hdPrman)

- **UsdPreviewSurface** is USD's baseline interchange shading model (via `UsdShade` networks); a **MaterialX implementation of UsdPreviewSurface** exists, making MaterialX the cross-renderer shading-interchange layer over USD. ([Simple Shading in USD](https://openusd.org/release/tut_simple_shading.html); [MaterialX PBR Spec](https://materialx.org/assets/MaterialX.v1.38.PBRSpec.pdf))
- **RenderMan + MaterialX:** RenderMan ships **MaterialX Lama** and supports MaterialX networks (via ShaderGen→OSL); see [03](03-renderman-shading.md) §2, §5.
- **Hydra render delegates** are the pluggable bridge between the Hydra viewport (and Hydra render paths) and a renderer. Katana's delegate system swaps the Viewer backend: **HdStorm (GL)** default, Foundry **AVP**, and third-party delegates including **hdPrman** (RenderMan), Arnold, 3Delight, Redshift. On your 6.5, **hdPrman in the Viewer requires the RenderMan 26 build** of the RfK 6.5 plugin (see [07](07-katana-renderman-integration.md)). ([Hydra Render Delegates, Dev Guide](https://learn.foundry.com/katana/dev-guide/Plugins/HydraRenderDelegates/index.html))
- *(The Katana 9.0 **Hydra 2.0** end-to-end "viewport to final frame" path is not in 6.5.)*

---

## USD quick-facts for 6.5v4
- USD **23.05**; read via **`UsdIn`**, author via 6.5 native USD composition nodes.
- **No** `KatanaToUsd`/`UsdLayerExport`/`UsdLight` (8.0) or `UsdSuperLayer`/`UsdGaffer` (9.0).
- Solaris ↔ Katana coexist on a shared USD backbone (Solaris procedural → Katana hero lighting).
- MaterialX = the portable shading interchange; **hdPrman** = RenderMan's Hydra delegate (RenderMan 26 build for your 6.5 Viewer).
