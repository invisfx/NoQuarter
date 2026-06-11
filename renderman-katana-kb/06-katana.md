# 06 — Katana (anchored on **6.5v4**)

> **Your build: Katana 6.5v4 (released 23 Aug 2024; 6.5v1 = 1 Nov 2023).** USD **23.05**, Python **3.9.x**, **PyQt5 5.15.9**, VFX Reference Platform **2022**. Katana **6.5 and 7.0 are feature twins** (same Nov-2023 launch, same features; 6.5 = Ref Platform 2022, 7.0 = 2023). Foundry docs (learn.foundry.com) 403 automated fetches; facts below are from the Foundry release-notes mirror + indexed pages. Newer 8.0/9.0 items are marked *(not in 6.5)*.

---

## 1. Version context

| Version | Date | Ref Platform | For your purposes |
|---|---|---|---|
| 5.0 | 14 Dec 2021 | 2020 | Hydra "Viewer" renamed, OSG deprecated; Nuke Bridge; Foresight+. |
| 6.0 | 15 Dec 2022 | 2022 | Material Solo, LiveShadingGroups, Performance tab. |
| **6.5 / 6.5v4** | 1 Nov 2023 / **23 Aug 2024** | 2022 | **Your build.** Native USD framework (USD 23.05), Foresight+ multithreaded live rendering, OpenVDB-in-Hydra. |
| 7.0 | 1 Nov 2023 | 2023 | Twin of 6.5 (newer dependencies only). |
| 8.0 | Dec 2024 | 2024 | *(not in 6.5)* USD round-trip nodes; PySide6. |
| 9.0 | Feb 2026 | 2025 | *(not in 6.5)* UsdSuperLayer/UsdGaffer; Hydra 2.0 alpha. |

Sources: [CG Channel 5.0](https://www.cgchannel.com/2021/12/foundry-ships-katana-5-0/) · [6.0](https://www.cgchannel.com/2022/12/foundry-ships-katana-6-0/) · [6.5v4 RN](https://learn.foundry.com/katana/Content/release_notes/6.5/Katana_6.5v4_ReleaseNotes.html) · [7.0](https://www.cgchannel.com/2023/11/foundry-releases-katana-7-0/).

### What 6.0 / 6.5 / 6.5v4 added (relevant to you)
- **6.0:** **Material Solo** (short-circuit a NetworkMaterial to preview sections, keys 1–9); **LiveShadingGroups** (`LiveShadingGroup` node inside NetworkMaterialCreate for sharing material sections); **Performance tab** (scene stats + cook-time heat map); Geolib3-MT improvements.
- **6.5:** **Native USD framework** (USD 23.05) for large-asset performance; native USD authoring/composition nodes (`UsdSublayerAdd`, `UsdInheritSet`, `UsdReferenceSet`, `UsdPayloadSet`, `UsdSpecializeSet`, `UsdLayerWrite`, `UsdPythonWrite`, `UsdPrimCreate`, `UsdSchemaSet`, `UsdPrimvarSet`); **`FnUsdAbstraction`** for custom USD frameworks; **multi-threaded Live Rendering via Foresight+** (cache-eviction modes: Dependency-protecting (default) / Continual / Relaxed); **OpenVDB volumes in Hydra** via `UsdVol`; USD property values in the Attributes tab; expansion-based USD working sets.
- **6.5v4 specifically:** `NetworkMaterialLayoutFilter` (perf editing in multi-material contexts), `MaterialInterfaceResolve` (propagate interface changes downstream), `NetworkMaterialMultiSplice` (wildcarded multi-location splicing); manipulator scaling via `=`/`-` keys; ASCII USD syntax highlighter for `UsdLayerWrite`.

---

## 2. Architecture — deferred scene graph, Ops, recipe vs scene graph

- **Deferred / recursive scene graph.** Katana's scene graph is **lazily evaluated** — a location contains *potential* work, learned only as the location and its children are expanded. Procedures are deferred until the renderer needs them. ([Generating Scene Graph Data](https://learn.foundry.com/katana/Content/ug/scene_data/generating_scene_graph_data.html))
- **Ops and the Op API.** Ops are the lowest-level scene-graph processing unit and a **superset of the old geometry APIs incl. Scene Graph Generators**. Each Op registers a **stateless Cook function** called on demand at each location, receiving two inputs: the upstream **scene-graph input** and **Op arguments** (CEL, file paths, child lists). Ops do the minimum work per location to be a "good citizen" in the deferred system. ([The Op API Explained](https://learn.foundry.com/katana/Content/tg/op_api/op_api_explained.html))
- **Recipe (node graph) vs scene graph.** The **node graph is the recipe**: each node adds/deletes/modifies scene-graph locations or data. 3D nodes drive Ops → Op graphs → **Geolib** processes them → the **scene graph** (inspected in the Scene Graph tab).
- **Geolib3-MT.** Multi-threaded scene-graph expansion using an internal thread pool + shared caching to reduce **time-to-first-pixel (TTFP)**. At render time the scene graph is traversed with an `FnScenegraphIterator` from `/root`. ([Geolib3-MT & Cache Optimization](https://learn.foundry.com/katana/Content/ug/optimization/geolib3-eviction.html))
- **Working Sets** scope which parts of the scene graph are expanded/active (Viewer Visibility / Payload / Active Prim working sets in 6.5).

---

## 3. Viewport — Hydra "Viewer", Monitor, Catalog

- **Hydra is the default and only viewer by 6.5.** Hydra arrived in 3.0; **5.0 renamed it "Viewer" and deprecated the legacy OpenSceneGraph (OSG) viewer** — treat OSG as gone. By 6.x, **HdStorm is the default GL renderer** (labelled **"GL"** in the Viewer's Render Delegates menu). ([Using the Hydra Viewer (6.0)](https://learn.foundry.com/katana/6.0/Content/ug/using_hydra_viewer/using_hydra.html))
- **Render delegates in the Viewer:** **HdStorm (GL)** default; Foundry **AVP** (Advanced Viewport); third-party delegates incl. **RenderMan / hdPrman** (see [07](07-katana-renderman-integration.md)).
- **Manipulators:** transform/2D/3D manipulators on scene-graph locations (lights, cameras, geo); 6.5v4 added manipulator scaling via `=`/`-`.
- **Monitor / Catalog / snapshots:** render output appears in the **Monitor tab**, the **Catalog tab**, and the **Monitor Layer** in the Viewer. Add a Catalog entry via **"Create Snapshot in Catalog"** in the Monitor's Live Render menu. ([Monitor Layer & Monitor Tab](https://learn.foundry.com/katana/content/ug/viewing_renders/monitor_tab.html))

---

## 4. Lookdev workflow — NetworkMaterial, shading graphs, LookFiles

- **`NetworkMaterialCreate` (NMC)** — container for building a material network; press **Tab inside** to add shading nodes; left-to-right layout with exposed/labeled ports. Legacy networks paste in and re-lay-out correctly. ([Building Materials Using NMC](https://learn.foundry.com/katana/Content/ug/adding_assigning_materials/using_networkmaterialcreate.html))
- **`NetworkMaterialEdit` (NME)** — non-destructively edits materials made via NMC *or brought in through LookFiles*, adding/removing nodes or changing params. Interior mirrors the NMC layout. ([Editing with NME](https://learn.foundry.com/katana/Content/ug/adding_assigning_materials/using_networkmaterialedit.html))
- **6.0 lookdev aids you have:** **Material Solo** (preview sections of a network) and **LiveShadingGroups** (`LiveShadingGroup` to reuse/share material sections).
- **Material attribute conventions:** materials live under `material.*`; `material.layout` preserves node-graph layout; shading nodes under `material.nodes`. ([Materials, Dev Guide](https://learn.foundry.com/katana/dev-guide/AttributeConventions/Materials.html))
- **LookFiles:**
  - **`LookFileBake`** — bakes the *differences* between the `orig` input and the `pass` inputs into a Look File. ([Creating a Look File](https://learn.foundry.com/katana/Content/ug/look_development/creating_look_file.html))
  - **`LookFileManager`** — a SuperTool that resolves Look Files with global settings/overrides; internally composed of `LookFileResolve`, `LookFileOverrideEnable`, `LookFileGlobalsAssign`. ([Look File Manager](https://learn.foundry.com/katana/Content/ug/look_files/look_file_manager.html))
  - Resolution maps source→target by root-location names / unique `rootIds`; assignment referenced via a `lookfile.asset` attribute (not inlined).

---

## 5. Lighting workflow — GafferThree, LightLink, Lighting Tools

- **`GafferThree`** — the **SuperTool** packaging light creation + management. Create a light, then add a light shader. Lights can alternatively be built from atomic nodes (`LightCreate` + `Material`). ([Creating a Light Using GafferThree](https://learn.foundry.com/katana/Content/ug/lighting_scene/creating_light_gafferthree.html))
- **Light linking** via the **`LightLink`** node, which manipulates the `lightList` attribute to selectively illuminate objects; **GafferThree uses a LightLink internally**. ([Linking Lights to Objects](https://learn.foundry.com/katana/Content/ug/lighting_scene/linking_lights_specific_objects_gafferthree.html))
- **Lighting Tools** — in-viewer overlay to create/place lights against a live render: activate via the **Lighting Tools** button in the Viewer or press **`L`**; a GafferThree dropdown picks the target. ([Creating Lights using Lighting Tools](https://learn.foundry.com/katana/Content/ug/lighting_scene/creating_light_lighting_tools.html))
- *(The 9.0 `UsdGaffer` USD-native lighting node is **not in 6.5** — use GafferThree.)*

---

## 6. Render settings, outputs, live rendering

- **`RenderSettings`** node — controls render *output*: active camera, resolution, crop window, and the **outputs** list. `interactiveOutputs` selects which outputs (e.g. AOVs) render during live sessions. ([RenderSettings ref](https://learn.foundry.com/katana/Content/rg/misc_nodes/rendersettings.html))
- **`Render`** node — each Render node is a single invocation of RenderMan (or another renderer); used for preview/disk/live renders. ([Render ref](https://learn.foundry.com/katana/Content/rg/3d_nodes/render.html))
- **Live rendering** streams material/transform/light edits at specified locations to the renderer, shown in Monitor/Catalog/Monitor Layer. **6.5's Foresight+ makes live rendering multi-threaded** with three cache-eviction modes (Dependency-protecting default / Continual / Relaxed). ([Controlling Live Rendering](https://learn.foundry.com/katana/Content/ug/rendering_scene/controlling_live_rendering.html))

See [07](07-katana-renderman-integration.md) for RenderMan-specific render settings and AOV setup in Katana.

---

## Katana 6.5v4 gotchas (vs a "latest" mental model)
1. **No `KatanaToUsd` / `UsdLayerExport` / `UsdLight`** — those are 8.0. 6.5 has native USD *authoring* nodes but no round-trip export and no native USD light node.
2. **No `UsdSuperLayer` / `UsdGaffer` / `UsdMaterial` / Hydra 2.0** — all 9.0.
3. **UI dev = PyQt5**, not PySide6 (8.0+). See [08](08-katana-customization.md).
4. **USD 23.05, Python 3.9.x** — not the newer USD/Python of 8/9.
5. **RenderMan pairing = 26.x**, not 27 (RfK 27 is Katana 7+). See [07](07-katana-renderman-integration.md).
