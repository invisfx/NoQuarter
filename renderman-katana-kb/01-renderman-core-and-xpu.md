# 01 — RenderMan Core & XPU (anchored on **26.x** for Katana 6.5v4)

> **Your renderer: RenderMan 26.x** (the version that pairs with Katana 6.5v4 via RfK — see [README](README.md) and [07](07-katana-renderman-integration.md)). This file documents 26.x as your working baseline. **RenderMan 27 is covered separately in the appendix at the bottom — it requires Katana 7+ and is NOT available to you.** Pixar wikis 403 automated fetches, so some specifics are from indexed excerpts; sampling/trace-depth parameter names are stable across RenderMan 20–26, but treat exact defaults as version-sensitive and confirm in your installed build.

---

## 1. Versions & release timeline (26.x)

| Version | Date | What it added |
|---|---|---|
| **26.0** | **8 Apr 2024** | Major **XPU** update (area/IES lights, light temperature, camera controls, **adaptive sampling in XPU**, light selection, faster instancing, parallel texture reads); **interactive ML denoiser**; Stylized Looks improvements (artistic toon mode, Canvas layer). ([Pixar RM26 news](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26)) |
| **26.1** | ~26 Apr 2024 | Bugfix; **OpenVDB caching in RIS** (faster reuse of the same VDB grid). ([80.lv 26.1](https://80.lv/articles/pixar-releases-renderman-26-1)) |
| **26.2** | ~24 Aug 2024 | **Advanced JSON denoiser config** (multi-file read/write, custom passes, tiling); automatic denoiser support for **OpenEXR inputs with data windows / single channels**; `denoise_batch` no longer needs `asrgba` for EXRs; `--progress` option; EL9 (RHEL9/Rocky/Alma) builds. ([Fox 26.2](https://www.foxrenderfarm.com/news/the-latest-render-man-26-2-whats-new-and-exciting/)) |
| **26.3** | **19 Dec 2024** | **Denoising in tiles** (lower memory on large images); DCC support updated to **Maya 2025, Katana 8.0, Houdini 20.5**. ([CG Channel 26.3](https://www.cgchannel.com/2024/12/pixar-releases-renderman-26/); [DP 26.3](https://digitalproduction.com/2024/12/20/renderman-26-3/)) |

**Katana fit:** RfK 26 covers Katana 5.0/6.0/6.5; later 26.x point releases added 7.0 and 8.0. Your **6.5v4 is comfortably inside the 26.x supported range.** RenderMan 27 requires Katana 7+, so 26.x is the correct line for you.

---

## 2. RIS vs XPU in 26.x — **RIS is your final-frame engine**

This is the single most important architectural fact for your pipeline:

> **In RenderMan 26.x, XPU is an interactive / look-dev renderer, NOT a production final-frame renderer.** Pixar positions XPU as "targeted for interactive look development on an artist desktop… not the primary use case for batch-mode renders on the farm." **Render your finals in RIS; use XPU for lookdev / IPR / lighting iteration.** RIS is the **primary, fully-featured** engine in 26 and is **not** deprecated (that's a RenderMan 27 statement). ([XPU Differences to RIS, RM26](https://rmanwiki.pixar.com/pages/viewpage.action?pageId=61612794); [General FAQ](https://renderman.pixar.com/general-faq))

**Architecture.** RIS = CPU-only path tracer (full feature set). XPU = hybrid CPU+GPU, **single-GPU** in 26, oriented at fast interactive feedback.

**What XPU in 26.x does NOT support** (all of these are RenderMan **27**-only — don't reach for them on 26.x):

| Capability | In 26.x XPU? |
|---|---|
| Final-frame production rendering | **No** (interactive/lookdev only) |
| Checkpointing | **No** |
| Deep data output | **No** (RM26 docs list it "Coming soon") |
| Holdouts / mattes | **No** |
| Extended OSL filters | **No** (in 26, OSL patterns needing `trace()` — e.g. `PxrDirt`, `PxrCurvature` — are unsupported in XPU) |
| MaterialX / Lama evaluation in XPU | **No** (Lama is **RIS-only** in 26 — see [03](03-renderman-shading.md) §2) |
| Multi-GPU | **No** (single-GPU only) |

**What XPU in 26.x *does* give you (interactive wins):** area/IES lights, light temperature, **adaptive sampling** (same controls as RIS: `PixelVariance`, `darkfalloff`, `exposurebracket`, `adaptall`, `relativepixelvariance`), light selection, faster instancing, and **hundreds of lights** rendered efficiently/interactively (suited to shot layout + key lighting). ([RM26 wiki notes](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661045/RenderMan+26.0))

**GPU requirements (XPU 26):** NVIDIA **Pascal or newer**; VRAM **11 GB minimum, 24 GB suggested**. Note XPU samples textures **one MIP level coarser than RIS** to fit more in GPU memory, so XPU previews are slightly softer than the RIS final. *(Exact GeForce-vs-Quadro support wording could not be confirmed against the blocked tech-specs page.)*

**When to use which (26.x):**
- **XPU** — interactive lookdev, lighting iteration, IPR in the Katana viewer (hdPrman XPU-CPU/XPU-GPU modes).
- **RIS** — **all final frames**, anything Lama-shaded, deep/holdouts/checkpointed renders, caustics (PxrVCM), many-light shots beyond XPU's comfort, scenes exceeding GPU VRAM.

---

## 3. Integrators & key parameters

**PxrPathTracer** — core forward (unidirectional) path tracer; default workhorse (RIS, and XPU for IPR).
- **`maxPathLength`** — absolute ray-depth bound. `1` = direct only; `4` = up to 3 GI bounces. Default **10**. ([PxrPathTracer ref](https://renderman.pixar.com/resources/RenderMan_20/PxrPathTracer.html))
- Per-type sample counts: `numLightSamples`, `numBxdfSamples`, `numIndirectSamples`, `numVolumeAggregateSamples` *(verify exact spelling/defaults in your build)*.
- **`allowCaustics`** — enable caustic paths (off by default).
- **`clampDepth` / `clampLuminance`** — firefly/noise clamping.

**PxrUnified** — VCM-class unified integrator (forward PT + bidirectional/vertex-merging). Doesn't honor separate diffuse/specular trace depths unless **`useTraceDepth`** is enabled. **RIS.**

**PxrVCM** — explicit bidirectional + progressive photon mapping (vertex merging). Full VCM by default, or pure BDPT / unidirectional / progressive photon mapping via **`mergePaths`** / **`connectPaths`**. **RIS-only.** Use for difficult caustics / SDS paths. ([PxrVCM](https://rmanwiki-26.pixar.com/space/REN26/PxrVCM))

**PxrOcclusion** — ambient-occlusion integrator. **PxrVisualizer** — diagnostic (wireframe, normals, ST).

---

## 4. Sampling

RenderMan's raytrace hider supports **fixed** and **adaptive stochastic** sampling, governed primarily by **`PixelVariance`**. In 26, **adaptive sampling is available in both RIS and XPU** with the same controls.

- **`Ri:PixelVariance`** — upper bound on acceptable estimated pixel-value variance. **Non-zero ⇒ adaptive; zero ⇒ fixed.** Lower → more rays (cleaner). ([risOptions](https://renderman.pixar.com/resources/RenderMan_20/risOptions.html))
- **`hider:minsamples`** — min camera rays/pixel; since PRMan 19 **defaults to √(maxsamples)**.
- **`hider:maxsamples`** — max samples/pixel (fixed mode = uniform count). `minsamples == maxsamples` ⇒ fixed.
- **`hider:incremental`** — progressive refinement passes; required for interactive feedback and OpenEXR checkpoint recovery (RIS).
- **Adaptive metric** — `adaptall`, `darkfalloff`, `relativepixelvariance`, `exposurebracket` weight how pixels adapt. *(Confirm names/availability in your build's RIS/XPU options.)*

**Per-object / per-light overrides:** integrators expose per-type sample multipliers; lights and objects can carry sample-count overrides (e.g. `fixedsamplecount` on a light — see [04](04-renderman-lighting.md)). *(Confirm precise attribute names against installed docs.)*

**Trace / ray depth:**
- **`trace:maxdiffusedepth`** — max indirect **diffuse** ray depth (per-object attribute).
- **`trace:maxspeculardepth`** — max indirect **specular/glossy** ray depth (per-object attribute).
- These are **object attributes, not global options** — push specular deeper than diffuse selectively. ([Trace Depth](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661825))
- **`maxIndirectBounces`** — absolute ray-depth bound used by XPU (where the separate diffuse/specular attributes give way to a single control).

---

## 5. Denoising (26.x)

1. **RenderMan ML/AI denoiser** — the **headline 26.0 feature**. Disney Research ML denoiser (trained on Disney/ILM/Pixar data). The **interactive** variant predicts the offline denoiser's result live during IPR, letting artists judge in "two or three samples" vs 64+ previously. ([Foundry: RM26 interactive denoiser in Katana](https://www.foundry.com/insights/film-tv/renderman-26-interactive-denoiser-katana); [80.lv](https://80.lv/articles/pixar-s-renderman-26-introduces-interactive-machine-learning-denoising))
2. **RenderMan spatial denoiser** (`denoise` / `denoise_batch` CLI) — batch post-process; **cross-frame** (`--crossframe`, `-L` for sequences) for temporal stability using **forward + backward motion vectors** (cross-frame only). **26.2** added EXR data-window/single-channel support and the advanced JSON config; **26.3** added **tiled denoising** for lower memory.
3. **NVIDIA OptiX denoiser** — available as an option in the **IPR Denoiser dropdown** alongside the RenderMan ML denoiser. NVIDIA Pascal+.

**Required denoiser AOVs:** `color Ci` (beauty), `color albedo` (+variance), `normal normal` (+variance), `vector forward`/`backward` (cross-frame only); master/variance filename ends in **`_variance.exr`**; AOV `type` = **`raw`** so channel names are preserved. Behavior controlled by the **Advanced Denoise JSON config**. Full channel table in [05](05-aovs-lpes-outputs.md) §5. ([Advanced Denoise JSON Config, REN26](https://rmanwiki-26.pixar.com/space/REN26/19660959))

---

## 6. Stylized Looks (NPR) in 26.x

26.x has the **pre-27.2 Stylized toolset**: 26.0 added easier line detection/remapping/filtering, an **artistic (non-PBR) toon mode**, expanded compositing/detection modes, a new **Canvas layer**, reorganized attributes and AOVs. **The big new-node expansion (`PxrStylizedHatchControl`, curvature/Sobel-edge outlines, 8-layer hatching) is RenderMan 27.2 — not available to you.** Use the 26 toon/line/canvas controls. ([Pixar RM26 news](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26))

---

## 7. Texture channel limit

26.x textures are capped at the **lower per-texture channel count (8)**; the **8 → 64 channel** raise is **RenderMan 27.2** and is not available to you. Plan AOV/utility-texture packing accordingly. *(Baseline "8" inferred from the 27.2 change description; confirm in your install.)*

---

## Appendix — What's in RenderMan 27 (requires **Katana 7+**, not available on 6.5v4)

Documented here only so you know what an upgrade would unlock — **none of this applies to your 26.x + Katana 6.5v4 pipeline:**

- **27.0 (Nov 2025):** XPU **graduates to production final-frame renderer**; **RIS marked for deprecation**. XPU gains checkpointing, deep data, holdouts/mattes, extended OSL filters, **MaterialX evaluation + Lama (Early Access)**, **multi-GPU**, interactive ML denoising. OpenImageIO faster texture conversion + native mipmapped-EXR (skip `.tex`). DCC support: Houdini 21, **Katana 8**, Maya 2026, Blender 4.4.
- **27.1 (Dec 2025):** XPU checkpoint fix; XPU **Lama coating absorption**.
- **27.2 (Feb 2026):** textures **8 → 64 channels**; expanded **Stylized Looks** (`PxrStylizedHatchControl` etc.); USD/Hydra + OpenPBR refinement.

To use any of the above you would need to move to **Katana 7+** and the matching RfK 27 plugin.

---

## 26.x quick-facts
- **Finals → RIS.** XPU → interactive lookdev/lighting only.
- **RIS is NOT deprecated** in 26; it's your primary engine.
- **Lama → RIS only.** **Deep/holdouts/checkpoint/multi-GPU → RIS** (XPU can't in 26).
- **ML denoiser (interactive)** is the big 26 win for fast iteration.
- **Textures: 8-channel cap.** **Stylized: pre-27.2 toon/line/canvas toolset.**
- Adaptive sampling (`PixelVariance`) in both RIS and XPU; per-object trace depth in RIS.
