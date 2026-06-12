# 14 — Custom Tools to Build for the Team (Katana 6.5v4)

> Practical pipeline tools a lighting lead/TD builds to make the [11](11-shot-lighting-workflow.md)/[12](12-lookdev-workflow.md) workflows fast and the [13](13-lead-templates-team-process.md) conventions enforceable. Anchored on **Katana 6.5v4**: **Python 3.9.x, PyQt5 5.15.9** (NOT PySide6), USD 23.05, RfK 26. API reference + how-to → [08](08-katana-customization.md).

> **6.5 ground rules for everything below:** UI in **PyQt5**; in-cook procedural work in **OpScript (Lua)**; node/UI authoring in **Python (NodegraphAPI)**; deploy via **`KATANA_RESOURCES`** named subdirs, bootstrap from `Startup/init.py`. ([08](08-katana-customization.md))

---

## Build priority (highest ROI first)

1. **Shot/template builder** — one click to assemble a correct scene.
2. **AOV/output setup tool** — generate the standard channel stack from config.
3. **Light-group + naming enforcer / checker** — keep conventions honest.
4. **Custom GafferThree light-rig packages** — studio rigs as first-class lights.
5. **Scene validator** — catch problems before the farm.
6. **Relight slap-comp exporter** — auto-build the Nuke script from light groups.

---

## 1. Shot / template builder (Python tool or SuperTool)

**Goal:** artist picks a shot; tool builds the ingest + render settings + base rig + AOV stack from the sequence template.

- **Build with `NodegraphAPI`** — `CreateNode`, wire ports with `Port.connect`, set params via `getParameter().setValue(...)`, drive shot-specific values with `setExpression`. ([08](08-katana-customization.md) §3)
- **Package as a Shelf script** for a button, or a **SuperTool** (`NodeTypeBuilder`, `XxxNode`/`XxxEditor`) if it needs persistent UI/state.
- **Read shot data** (camera/anim/asset versions) from your asset system; populate `UsdIn`/ingest params.
- Deploy under `KATANA_RESOURCES/Shelves/Lighting/` or `KATANA_RESOURCES/SuperTools/`.

---

## 2. AOV / output setup tool

**Goal:** stamp the show-standard output stack ([13](13-lead-templates-team-process.md) §4) into any scene, including a per-group AOV for **every** light group present.

- **Discover light groups** by scanning the scene graph (via a render/Python pass or an OpScript that collects `__group` values), then generate one `PrmanOutputChannelDefine` per group (`lpe:diffuse_<group>`, `lpe:specular_<group>`) wired into `RenderOutputDefine`.
- **Drive from a config file** (JSON/YAML) listing the standard channels + LPE sources so the stack is data-defined and version-controlled, not hand-built.
- Add the standard data/ID/denoiser channels (`Z`, `normal`, `P`, motion vectors, `PxrCryptomatte`, denoiser inputs) and set `interactiveOutputs` to a lean IPR subset.
- **Build with `NodegraphAPI`**; expose a "rebuild AOVs" button so artists re-sync after adding lights.

---

## 3. Light-group + naming enforcer / checker

**Goal:** guarantee [13](13-lead-templates-team-process.md) §3 conventions — every light named and grouped.

- **OpScript (Lua) check** over the light locations: read each light's name + `__group`; flag unnamed/ungrouped/duplicate-named lights. ([08](08-katana-customization.md) §1)
- **Auto-fix helper** (Python): assign a `__group` from a light-name pattern, or batch-rename to convention.
- Surface results in a small **PyQt5 panel** (custom Tab, `UI4.Tabs.BaseTab`, registered as a `KatanaPanel`) listing offenders with click-to-select.

---

## 4. Custom GafferThree light-rig packages

**Goal:** studio rigs (3-point studio, sky-dome+sun, interior portal kit) as one-click GafferThree items with the right defaults + naming/grouping baked in.

- **Package class** — derive from `PackageSuperToolAPI.Packages.Package` (or the GafferThree `LightPackage`); implement `create()` to build/wire the rig's lights (already named + grouped) inside the gaffer. ([08](08-katana-customization.md) §4)
- **UI delegate** — derive from `PackageSuperToolAPI.UIDelegate.UIDelegate`/`LightUIDelegate` for the parameter UI.
- **Register** with `GafferThreeAPI.RegisterPackageClass(<YourClass>)`; deploy via `KATANA_RESOURCES`.
- Result: artists drop a "Studio Rig" into GafferThree and get conventions for free.

---

## 5. Scene validator (pre-farm checker)

**Goal:** catch issues before a farm submit wastes hours.

Checks (mix of Python scene queries + OpScript scans):
- **Materials resolved** (no unassigned/missing-texture locations); textures exist as `.tex`.
- **Lights** named + grouped (reuse §3); no zero-intensity/orphan lights.
- **Render settings** sane (resolution, frame range, integrator, sample budget within policy).
- **AOV stack** matches the show standard; denoiser inputs present if denoising.
- **Color** — OCIO config present; texture color-space tags set.
- **Output paths** follow the naming convention and are writable.
- Present a **PyQt5 report panel**: pass/warn/fail with jump-to-node. Optionally gate farm submit on no failures.

---

## 6. Relight slap-comp exporter

**Goal:** turn the standardized per-group AOVs into a ready Nuke relight script automatically.

- Read the scene's light groups + output paths (Python), emit a **Nuke `.nk`** that reads the multichannel EXR, shuffles each group/lobe AOV, and wires the studio relight/recomp template ([10](10-lookdev-color-workflow.md) §3–4).
- Because naming is standardized ([13](13-lead-templates-team-process.md)), one generator serves the whole show.

---

## Supporting utilities worth having

- **OpScript library** — reusable Lua snippets: procedural light-linking by CEL, attribute-convention stampers, primvar fixups. ([08](08-katana-customization.md) §1)
- **Custom `.args` files** for any in-house OSL patterns/shaders so they get proper UI in Katana and auto-load via RfK 26. ([08](08-katana-customization.md) §5)
- **Shelf of one-click actions** — version-up, snapshot-with-naming, toggle IPR backend (XPU/RIS), open slap comp.
- **`Startup/init.py` bootstrap** — register all the above, set studio defaults, extend `KATANA_RESOURCES`. ([08](08-katana-customization.md) §6)

---

## Deployment & maintenance notes
- **Everything ships via `KATANA_RESOURCES`** named subdirs (`Shelves`, `SuperTools`, `Tabs`, `Ops`, `Args`, `Macros`, `Startup`). ([08](08-katana-customization.md) §6)
- **Target PyQt5 5.15.9 / Python 3.9** — do not write PySide6 (that's an 8.0 upgrade concern; the [Qt5→Qt6 migration](https://learn.foundry.com/katana/dev-guide/Qt6Migration.html) matters only when you move off 6.5).
- **Prefer OpScript (Lua) for in-cook work** (multithreaded, fast); Python for authoring/UI only.
- Version your tools alongside the show template; document them in the onboarding doc ([13](13-lead-templates-team-process.md) §8).

---

## Tooling checklist
- [ ] Shot/template builder (shelf or SuperTool).
- [ ] Config-driven AOV/output setup tool (per-group AOVs auto-generated).
- [ ] Light-group/naming checker + auto-fix (OpScript + PyQt5 panel).
- [ ] Custom GafferThree rig packages (named/grouped by default).
- [ ] Pre-farm scene validator (gate submit).
- [ ] Relight slap-comp `.nk` exporter.
- [ ] OpScript utility library + in-house `.args` + one-click shelf + `init.py` bootstrap.
