# 08 — Katana Customization & Tool Writing (anchored on **6.5v4**)

> The Katana plugin/scripting architecture is **stable from 6.5 through 9.0**, so everything here applies to your 6.5v4 build. **Two version-specific things to burn in for 6.5:** UI plugins use **PyQt5 5.15.9** (NOT PySide2, NOT PySide6 — PySide6 only arrives at 8.0), and you're on **Python 3.9.x**. Foundry docs 403 automated fetch; API names are from indexed pages — confirm less-common method casing against `$KATANA_HOME/docs` in your install. **[VERIFY]** marks items not directly page-rendered.

---

## 1. OpScript (Lua) — procedural scene-graph manipulation

OpScript is Katana's Lua node for per-location scene-graph processing. Lua/OpScript exposes the **Op API**, which is "both faster and more powerful than Python" — it can delete locations, create children, and set/edit attributes, multi-threaded inside Geolib3. ([Scripting & Programming in Katana](https://learn.foundry.com/katana/Content/ug/script_editing/scripting_programming_in_katana.html))

**Decision rule — OpScript (Lua) vs Python:**
- **OpScript/Lua** for anything *inside the cook* (per-location scene-graph evaluation): create/delete locations, read/write attributes, geometry processing. Multithreaded; the recommended default "wherever possible."
- **Python (NodegraphAPI etc.)** for *node-graph authoring and UI* — building/wiring nodes, parameters, tools, callbacks. Python does **not** run in the cook.

In-app examples: `Help > Example Projects`, and `$KATANA_HOME/demos/katana_files/opscript_tutorial.katana`. ([OpScript Tutorials](https://learn.foundry.com/katana/Content/ug/working_with_attributes/opscript_tutorials.html))

### The `Interface` (cook) object — key methods
([Cook Interface (OpScript)](https://learn.foundry.com/katana/dev-guide/OpsAndOpScript/CookInterface/OpScript.html))
- **`Interface.getAttr(name [, locationPath] [, inputIndex])`** — reads from the Op's **input** scene graph. **`getAttr()` only sees the input; values you `setAttr()` are not visible to it** — read those back with `getOutputAttr()`.
- **`Interface.setAttr(name, attribute)`** — set an attribute on the current output location (e.g. `Interface.setAttr("geometry.point.P", DoubleAttribute(...))`).
- **`Interface.getOutputAttr(name)`** — read an attribute already set during *this* Op's run.
- **`Interface.copyAttr(...)`**, **`Interface.getOpArg([name])`** (reads the Op's args group).
- **`Interface.createChild(name [, opType] [, opArgs])`** — create a child; if `opType` omitted the child inherits the parent's opType.
- **`Interface.execOp(opType, opArgs)`** — run another Op at the current location.
- **`Interface.deleteSelf()`** — delete the current location (prefer **`deleteChild()`** from the parent — more efficient).
- **`Interface.stopChildTraversal()`**, **`Interface.replaceChildTraversalOp(...)`** **[VERIFY casing]**, **`Interface.copyLocationToChild(...)`** **[VERIFY]**.
- **Input enumeration:** `getInputLocationPaths()` / input-index querying. **[VERIFY `getInputLocations()` vs `getInputLocationPaths()` for your build]**

### Attributes
([Attributes (OpScript)](https://learn.foundry.com/katana/dev-guide/OpsAndOpScript/Attributes/OpScript.html))
- **Data attrs:** `IntAttribute`, `FloatAttribute`, `DoubleAttribute`, `StringAttribute` (typed, possibly time-sampled, multi-valued).
- **`GroupAttribute`** — named hierarchy (`geometry`, `material`, `xform`).
- **`GroupBuilder`** — incrementally assemble a group; call **`build()`** then `setAttr` it.
- **Gotcha:** OpScript arrays are modeled on C++ `std::vector` — **indexed from 0, not 1** (unlike native Lua tables). Confirm accessor names (`getValue`, `getNearestSample`, `getNumberOfValues`, tuple size) in your docs **[VERIFY]**.

### Patterns & performance
- An OpScript node's **`CEL`** parameter scopes which locations it runs at; `applyWhere`/run-mode controls per-location vs subtree. **[VERIFY exact param names]** ([OpScript node ref](https://learn.foundry.com/katana/Content/rg/3d_nodes/opscript.html))
- Prefer parent-side edits (`deleteChild` over `deleteSelf`); keep per-location work small (Ops cook on demand, in parallel). ([Improving Op Performance](https://learn.foundry.com/katana/7.0/dev-guide/PerformanceOptimizationGuide/Ops.html))

---

## 2. C++ Ops (Geolib3)

A **Geolib3 Op** is the lowest-level scene-graph processing unit; the same public Op API underlies all of Katana's internal processing. Subclass **`Foundry::Katana::GeolibOp`** and implement two statics: ([Cook Interface (C++)](https://learn.foundry.com/katana/dev-guide/OpsAndOpScript/CookInterface/Cpp.html))
- **`static void setup(GeolibSetupInterface&)`** — declares Op characteristics (threading mode).
- **`static void cook(GeolibCookInterface&)`** — stateless per-location cook (same surface the OpScript `Interface` binds).

**Register** with **`DEFINE_GEOLIBOP_PLUGIN(<Class>)`** + a free `registerPlugins()` calling **`REGISTER_PLUGIN(<Class>, "<Name>", <major>, <minor>)`**. Deploy compiled Ops under a `KATANA_RESOURCES` **`Ops`** dir (`Libs` for compiled libs). The **KatanaUsdPlugins** repo (`TheFoundryVisionmongers/KatanaUsdPlugins`, the `PxrUsdIn` family) is the canonical buildable example. ([KatanaUsdPlugins](https://github.com/TheFoundryVisionmongers/KatanaUsdPlugins/blob/main/BUILDING.md))

---

## 3. Python API

### NodegraphAPI (authoring)
([Working with Nodes](https://learn.foundry.com/katana/dev-guide/Scripting/WorkingWithNodes/index.html))
- **Create:** `NodegraphAPI.CreateNode('<Type>', parent)` (parent = `GetRootNode()` for top level, or a Group to nest).
- **Retrieve:** `NodegraphAPI.GetNode('<name>')`, `GetRootNode()`.
- **Connect:** get ports (`getInputPort`/`getOutputPort`), call **`Port.connect(otherPort)`**.
- **Params:** `node.getParameter('<name>')`; `getValue(frame)` / `setValue(value, frame)`.
- **Expressions:** `parameter.setExpression('<python expr>')`. Dynamic params covered separately.

### Callbacks & events
- **`Callbacks.addCallback(Callbacks.Type.<event>, fn)`** — fire on app launch, project load, node creation, etc. (`Callbacks.Type.onStartupComplete` existence **[VERIFY]** in your build's enum). ([Callbacks & Events](https://learn.foundry.com/katana/2.5/dev-guide/Scripting/CallbacksAndEvents.html))
- **`Utils.EventModule.RegisterEventHandler(handler, 'event_name')`** — lower-level events (`'pref_changed'`, node/param events).

### Rendering
- **`RenderingAPI`** drives renders from Python (batch/preview/live); **`LiveRenderAPI`** for live-render control. ([RenderingAPI](https://learn.foundry.com/katana/dev-guide/Scripting/RenderingAScene/RenderingAPI.html))

### UI4 — custom tabs (⚠️ **PyQt5** on 6.5)
- Subclass **`UI4.Tabs.BaseTab`**, build the layout with **PyQt5** (your 6.5 binding — **5.15.9**), register as a plug-in of type **`KatanaPanel`** via a module-level `PluginRegistry` (e.g. `PluginRegistry = [('KatanaPanel', 2.0, 'TabName', YourTabClass)]`), drop the `.py` into a `KATANA_RESOURCES`/**`Tabs`** dir. ([Custom Tabs](https://learn.foundry.com/katana/dev-guide/Scripting/CustomizingUserInterface/CustomTabs.html))
- **Do NOT write 6.5 UI plugins against PySide6/PySide2** — Foundry moved Katana to PySide6 only at **8.0**. The [Qt5→Qt6 Migration guide](https://learn.foundry.com/katana/dev-guide/Qt6Migration.html) is relevant only when you eventually upgrade. **[VERIFY exact `KatanaPanel` tuple shape for 6.5]**

---

## 4. Custom nodes: Macros, Group nodes, SuperTools

| Mechanism | Authored in | Stored as | Internals |
|---|---|---|---|
| **Group node** | UI | in scene | static wrapped nodes |
| **Macro** | UI ("Save as Macro") | `.macro` file | static, fixed at save |
| **SuperTool** | **Python** | Python package | **dynamically built** Op chain + custom PyQt UI |

([Groups, Macros, SuperTools](https://learn.foundry.com/katana/Content/ug/groups_macros_super_tools/groups_macros_super_tools.html))

- **Macros** load from **`Macros`** dirs of `KATANA_RESOURCES`, **suffixed by the parent directory name** (`<name>_studio`).
- **SuperTools** — Python packages in a **`SuperTools`** dir, registered via module-level **`PluginRegistry`**. Convention: two classes **`XxxNode`** (defines node + scripting API + builds the internal network) and **`XxxEditor`** (Parameters-tab PyQt UI). **`NodeTypeBuilder`** defines/registers the node type and the function that builds its **Op chain**; **`PackageSuperToolAPI`** provides core functionality. ([How To Write a SuperTool](https://learn.foundry.com/katana/dev-guide/Scripting/CustomizingNodeTypes/CustomNodeTypes/SuperTools/HowToWriteASuperTool.html); [NodeTypeBuilder](https://learn.foundry.com/katana/dev-guide/Scripting/CustomizingNodeTypes/CustomNodeTypes/NodeTypeBuilder.html))

### GafferThree custom packages (studio light rigs)
1. **Package class** — derive from `PackageSuperToolAPI.Packages.Package` (or `LightPackage`); implement `create()` to build/wire the package's nodes.
2. **UI delegate** — derive from `PackageSuperToolAPI.UIDelegate.UIDelegate` (or `LightUIDelegate`).
3. **Register** with `GafferThreeAPI.RegisterPackageClass(<YourClass>)`. **[VERIFY signature for 6.5]**

([Creating a Custom GafferThree Package Class](https://learn.foundry.com/katana/3.0/Content/tg/gafferthree_api/create_gafferthree_package.html))

---

## 5. Custom shader integration — Args files, GenericAssign, renderer plug-ins

### Args files (`.args`)
XML files that provide the **shader-parameter UI**. Originally a Katana hinting mechanism, **adopted and extended by RenderMan** as the standard shader-introspection format. ([Args File Reference, RMan 26](https://rmanwiki-26.pixar.com/display/REN24/Args+File+Reference); [Args Files for Shaders](https://learn.foundry.com/katana/dev-guide/ArgsFiles/ForShaders.html))

Structure:
- Root **`<args>`**; **`<param>`** elements (presence/order/type — **file order = UI order**); **`<output>`**; **`<page>`** (collapsible groups, map to attribute groups); **`<help>`**.
- **`shaderType`** element (values `bxdf`, `pattern`, `displacement`, `integrator`, `light`) — **required for RIS/plugin shaders** (no `sloinfo` query for plugins).
- **Widgets & hints:** the `widget` attribute picks the control; hints like **Conditional Visibility** (`conditionalVisOp` / `conditionalVisPath` / `conditionalVisValue` **[VERIFY spelling]**) and **Locking** are honored by most widgets; many can be set in Katana and **exported back to the Args file**. ([Widgets and Hints](https://learn.foundry.com/katana/dev-guide/ArgsFiles/WidgetsAndHints.html))

**RenderMan specifics:** Args files are **required for plugin (C++) shaders** — the only source of param types/defaults to the DCC. **Must share the shader's base name** (`PxrSurface.args` ↔ `PxrSurface`). RfK searches: the **`Args`** subdir of the shader dir (recommended), `../Args`, or `Args` under `$KATANA_RESOURCES`; at startup RfK **auto-loads all discoverable shaders** with an Args file. ([Args File Reference, RMan 26](https://rmanwiki-26.pixar.com/display/REN24/Args+File+Reference))

### GenericAssign
GenericAssign Args files specify **attribute conventions** and define node types that edit them; `<page>` groups → attribute groups. The mechanism for exposing renderer-/pipeline-specific attribute sets in node UIs. ([Args Files for GenericAssign](https://learn.foundry.com/katana/dev-guide/ArgsFiles/ForGenericAssign.html))

### Material attribute conventions
Shaders attach to `material` locations via the **`material`** group; shading nodes under **`material.nodes`** with terminal assignments wiring outputs to renderer terminals. Per-renderer prefixes (e.g. `prmanGlobalStatements.*`). **[VERIFY exact terminal-attribute spellings]**

### Renderer / RendererInfo plug-ins
- **Render plug-in** — extend abstract **`Render`**; register with `DEFINE_RENDER_PLUGIN` + `REGISTER_PLUGIN`. Advertise render methods (batch/preview/live) via `RendererInfo::RendererInfoBase::fillRenderMethods(...)`. ([Render API](https://learn.foundry.com/katana/dev-guide/Plugins/Renderer/RenderAPI.html))
- **RendererInfo plug-in** — subclass **`RendererInfo::RendererInfoBase`** for renderer metadata; key overrides `fillRendererObjectNames(...)`, `buildRendererObjectInfo(...)`, shader/output enumeration. ([Renderer Plug-ins Overview](https://learn.foundry.com/katana/dev-guide/Plugins/Renderer/Overview.html))

---

## 6. Bootstrap — `KATANA_RESOURCES` & startup

`KATANA_RESOURCES` is the master plugin search list (`:`-separated on Linux). **Katana doesn't search the paths directly — it looks for named subdirectories** within each. ([Katana Resources](https://learn.foundry.com/katana/Content/ug/installation_licensing/katana_resources.html))

| Subdir | Contents |
|---|---|
| **`Startup`** | startup Python — **`init.py`** is the one file auto-run (call everything else from it; a per-user `init.py` can live in `~/.katana`) |
| **`SuperTools`** | Python SuperTool packages |
| **`Tabs`** | PyQt5 UI tab plug-ins (`KatanaPanel`) |
| **`Macros`** | `.macro` files (suffixed by parent dir name) |
| **`Shelves`** / `ShelvesNodeSpecific` / `ShelvesScenegraph` | toolbar / Parameters-tab / Scene-Graph-tab shelf scripts (`.py`) |
| **`UIPlugins`** | UI plug-ins |
| **`ViewerManipulators`** | Python viewer manipulators |
| **`Ops`** / `Libs` | C++ Op plug-ins / compiled libs |
| **`Args`** | Args files |

**Precedence:** most dir types take the **first** registration scanning left-to-right; some (SuperTools, Tabs) are searched **right-to-left** so local paths override studio defaults; duplicate shelves take items from the **last** shelf of that name. **[VERIFY full per-dir precedence table for 6.5]**

---

## Customization quick-facts for 6.5v4
- **UI = PyQt5 5.15.9**, Python **3.9.x**. Never PySide6 (that's 8.0+).
- **In-cook procedural work → OpScript (Lua)**; **node/UI authoring → Python (NodegraphAPI)**.
- **Reusable tools → SuperTools** (`NodeTypeBuilder`, `XxxNode`/`XxxEditor`); simple ones → Macros.
- **Studio light rigs → custom GafferThree packages** (`RegisterPackageClass`).
- **Custom RenderMan shaders → `.args` files** (name-matched, `shaderType` set) auto-loaded by RfK 26.
- **Everything deploys via `KATANA_RESOURCES`** named subdirs; bootstrap from `Startup/init.py`.
