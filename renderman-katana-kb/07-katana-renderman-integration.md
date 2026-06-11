# 07 — Katana 6.5v4 + RenderMan Integration (RfK)

> **Your pairing: Katana 6.5v4 → RenderMan-for-Katana (RfK) 26.x.** RenderMan **27 dropped Katana 5/6 support** (RfK 27 is **Katana 7+ only**), so a 6.5v4 pipeline runs **RenderMan 26.x** as the renderer. This is the single most important integration fact for your setup. ([XPU in Katana, RFK26](https://renderman.atlassian.net/wiki/spaces/RFK26/pages/20218708); [CG Channel RM27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))

---

## 1. RfK plugin, versions, install

- **RenderMan for Katana (RfK)** is Pixar's plugin integrating RenderMan into Katana.
- **Compatibility for you:** **RfK 26 supports Katana 5.0 / 6.0 / 6.5.** RenderMan **26.3** later extended RfK support up to Katana 8.0. RenderMan 25 also had a 6.5 plugin — **but the hdPrman Viewer render delegate on Katana 6.5 requires the RenderMan 26 build of the 6.5 plugin; the RenderMan 25 build of 6.5 does not include it.** ([RenderMan 26.0, rmanwiki](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661045); [CG Channel RM 26.3](https://www.cgchannel.com/2024/12/pixar-releases-renderman-26/))
- **Install:** RfK needs both **RenderMan Pro Server** and the **RfK plugin**; the RenderMan installer sets this up, and Katana auto-discovers/loads the modules once configured. ([RfK Getting Started](https://renderman.pixar.com/resources/RenderMan_20/rfkGettingStarted.html))
- **On the path:** add the RfK plugin tree to `KATANA_RESOURCES`, e.g. `KATANA_RESOURCES=${KATANA_RESOURCES}:${RFKTREE}/plugins/katana6.5` (version-suffixed dir matching your Katana). Set **`RMAN_RIXPLUGINPATH`** to include `$RMANTREE/lib/RIS` and **`RMAN_SHADERPATH`** for shaders — these **replace** rather than append to defaults, so include the defaults too. ([Configuring Katana, RFK26](https://renderman.atlassian.net/wiki/spaces/RFK26/pages/20218604)) *(Confirm the exact `plugins/katanaX.Y` folder name in your RfK 26 install.)*

---

## 2. Render configuration nodes

Settings split into two categories ([Render Settings in Katana, RFK26](https://rmanwiki-26.pixar.com/display/RFK/Render+Settings+in+Katana)):
- **Render output** — camera, resolution, crop window → primarily the **`RenderSettings`** node.
- **Render input** — RenderMan options/attributes + RfK config → primarily **`PrmanGlobalStatements` / `PrmanGlobalSettings`** and **`PrmanObjectStatements` / `PrmanObjectSettings`**.

**`PrmanGlobalSettings`** carries the **Hider** and **Integrator** settings (sampling / integration controls — `PixelVariance`, min/max samples, integrator choice & params). **`PrmanObjectSettings`** carries per-object RenderMan attributes (trace depth, subdivision, visibility, trace subsets). *(Modern RfK is RIS/XPU-only; any legacy Reyes layout toggles are vestigial.)*

---

## 3. Interactive / live rendering with RenderMan

- **Live (IPR) rendering** skips RIB generation for fastest feedback. Supported live edits: **material parameters; add/delete/edit shading nodes; light & light-filter attribute/transform edits; adding lights and objects; live `renderSettings` updates (ROI, cropWindow, resolution)**. ([Render Settings in Katana, RFK26](https://rmanwiki-26.pixar.com/display/RFK/Render+Settings+in+Katana))
- **hdPrman in the Viewer:** supported on Katana **4.5+** with RenderMan **24.3+**; on your 6.5 you need the **RenderMan 26** build. Backend modes: **RIS, XPU-CPU, XPU-GPU, XPU**. ([hdPrman in Katana, RFK24](https://renderman.atlassian.net/wiki/spaces/RFK24/pages/21430700)) Use **XPU-GPU / XPU** for fast interactive lookdev/lighting feedback; switch to **RIS** for caustics or final-frame parity on 26.x (where RIS is still the primary batch engine).

> On **RenderMan 26.x** (your renderer): XPU exists and is great for interactivity, but RIS remains the production final-frame engine — the "XPU graduates to final-frame" change is a **RenderMan 27** event you don't have on Katana 6.5. See [01](01-renderman-core-and-xpu.md).

---

## 4. AOVs / IDs / output setup in Katana

- RfK drives AOVs via **Light Path Expressions (LPE)** — see [05](05-aovs-lpes-outputs.md) for the grammar.
- In Katana the output is split across two nodes: **`PrmanOutputChannelDefine`** (maps to `RiDisplayChannel` — declares the channel + its `lpe:` source) wired into **`RenderOutputDefine`** (maps to `RiDisplay` — the file/driver). ([Setting up AOVs in Katana, RFK](https://rmanwiki.pixar.com/display/RFK/Setting+up+AOVs+in+Katana))
- To make an AOV render **interactively**, add it to **`interactiveOutputs`** in the `RenderSettings` node.
- **Cryptomatte / deep:** add `PxrCryptomatte` sample filters and deep outputs through the same output-define mechanism (see [05](05-aovs-lpes-outputs.md) §1.4).

---

## 5. Render farm dispatch

- Katana's **Farm API** (Farm plug-ins) dispatches jobs by project file, frame range, and render outputs. ([Render Farm Plug-ins, Dev Guide](https://learn.foundry.com/katana/dev-guide/Plugins/FarmAPI.html))
- With RfK + **Tractor** + RenderMan Pro Server you get desktop-to-farm dispatch; Tractor distributes queued jobs with dependencies/scheduling. RfK can render from **Katana batch** directly or generate **RIB** locally for farm distribution. ([RenderMan for Katana](https://rmanwiki.pixar.com/display/RFK26/RenderMan+26+for+Katana))
- **On 26.x farms:** combine **checkpoint + `-recover`** (RIS) for resilient long renders. XPU checkpointing is a **27** feature — not available to you on 6.5, so for resumable final frames lean on **RIS** (see [02](02-render-optimization.md) §6).

---

## Integration quick-facts for 6.5v4
- Renderer = **RenderMan 26.x** (not 27).
- Sampling/integrator settings live on **`PrmanGlobalSettings`** (Hider + Integrator).
- Per-object RenderMan attrs on **`PrmanObjectSettings`**.
- AOVs = **`PrmanOutputChannelDefine` → `RenderOutputDefine`**, `lpe:` sources, `interactiveOutputs` for live.
- Viewer IPR via **hdPrman** (RenderMan 26 build) — modes RIS / XPU-CPU / XPU-GPU / XPU.
- Final-frame resumable renders → **RIS + checkpoint/recover** (XPU checkpointing needs 27).
- Farm via **Tractor** (batch render or local RIB).
