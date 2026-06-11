# 01 — RenderMan Core & XPU (27.x)

> Sourcing: official Pixar pages (renderman.pixar.com, rmanwiki, renderman.atlassian.net) + trade press (CG Channel, Digital Production, CGW, Animation Magazine). Pixar wikis 403 automated fetches, so some specifics are from indexed search excerpts of those exact pages — flagged where a parameter default/behavior could not be confirmed against a live read. Sampling/trace-depth parameter names are stable across RenderMan 20–27; treat exact **defaults** as version-sensitive and confirm in your installed `rmanwiki-27` build.

---

## 1. Versions & release timeline

- **RenderMan 26** — **April 2024**. Major XPU expansion; first **machine-learning denoiser**, including an interactive ML denoiser. ([renderman.pixar.com/news/26](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26); [animationmagazine](https://www.animationmagazine.net/2024/04/pixar-releases-renderman-26-with-xpu-updates-machine-learning-denoising/))
- **RenderMan 27.0** — **Nov 13 2025**. Pixar's "most significant RenderMan release in ten years… a complete rewrite to take full advantage of today's modern hardware." Central change: **XPU graduates to a production final-frame renderer**, and **RIS is officially marked for deprecation** (still ships, maintenance mode). ([renderman.pixar.com/news/27](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-27); [DP 27.0](https://digitalproduction.com/2025/11/14/pixars-renderman-27-0/); [CG Channel](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/); [cgw](https://www.cgw.com/Press-Center/News/2026/A-new-era-in-rendering-Pixar-Animation-Studios-r.aspx))
- **RenderMan 27.1** — **Dec 2025**. Fix/refinement release: **XPU checkpointing corrected** to match RIS (post-checkpoint command runs after a successful render, not only per-checkpoint); **MaterialX Lama** coating support extended in XPU. ([DP 27.1](https://digitalproduction.com/2025/12/09/checkpoint-fixed-pixar-ships-renderman-27-1/); [CG Channel 27.1](https://www.cgchannel.com/2025/12/pixar-releases-renderman-27-1/))
- **RenderMan 27.2** — **Feb 2026**. XPU stability/perf; **textures raised from 8 to 64 channels** and larger max user-attribute sizes; expanded **Stylized Looks** (new NPR nodes); continued USD/Hydra refinement and improved **OpenPBR** parameter mapping. ([CG Channel 27.2](https://www.cgchannel.com/2026/02/pixar-releases-renderman-27-2/); [DP 27.2](https://digitalproduction.com/2026/03/03/renderman-27-2-adds-usd-and-xpu-updates/))

**As of mid-2026, 27.2 is the current line. No RenderMan 28 announced** (absence of evidence — not positively confirmed).

Other 27.0 headline items: MaterialX shading-graph evaluation in XPU; OpenImageIO-based faster texture conversion with native mipmapped-EXR support (skip `.tex` conversion); DCC support for Houdini 21, **Katana 8**, Maya 2026, Blender 4.4. ([CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))

---

## 2. RIS vs XPU — architecture & feature parity

**Architecture.** RIS is the long-standing **CPU-only** path tracer. XPU is the **hybrid CPU+GPU** engine; in 27 it supports **multi-GPU** in hybrid and GPU-only modes. Design promise: identical pixels — if a scene doesn't fit in VRAM, run it CPU-only and get the same result. ([DP: XPU graduates, RIS retires](https://digitalproduction.com/2025/09/25/renderman-27-xpu-graduates-ris-retires/); [renderman.pixar.com/general-faq](https://renderman.pixar.com/general-faq))

**XPU now supports (formerly RIS-only):** final-frame rendering; **checkpointing**; **deep data** output; **holdouts & mattes**; additional AOV options; **OSL filters**; interactive ML denoising; **MaterialX** graph evaluation; multi-GPU. ([CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/); [DP](https://digitalproduction.com/2025/09/25/renderman-27-xpu-graduates-ris-retires/))

**Remaining XPU parity gaps vs RIS** (verify against the live [XPU Features and Limitations — REN27](https://renderman.atlassian.net/wiki/spaces/REN27/pages/542236818/XPU+Features+and+Limitations)):

- **Specialized integrators are RIS-only.** Manifold walk, **bidirectional path tracing**, photon mapping, **VCM (PxrVCM)** are not available in XPU — XPU is forward-path-tracing oriented. **Practical consequence: caustic-heavy shots stay on RIS.**
- **Many-light convergence.** XPU may not converge as well as RIS on shots with very many lights; scene-dependent, but **above several hundred lights RIS begins to outperform XPU** (26 already improved XPU to handle "hundreds of lights" interactively).
- **No out-of-core GPU memory.** Scene must fit in each GPU's VRAM; CPU fallback is the workaround.

**Integrators in XPU:** **PxrOcclusion** available in XPU; **PxrVisualizer** XPU version improved toward RIS parity (added alpha output).

**When to use which**
- **XPU** — default going forward: interactive lookdev/lighting, key/shot lighting, GPU final frames, scenes that fit VRAM, modern feature set (deep, holdouts, MaterialX, OSL filters).
- **RIS** — VCM/bidirectional/photon-mapped caustics; extreme many-light shots; scenes exceeding VRAM where you don't want CPU-only XPU; any feature still flagged unsupported in your XPU build. RIS is maintenance-mode — plan migration.

---

## 3. GPU memory (XPU)

- **NVIDIA only**, Pascal or newer (same floor as the OptiX denoiser). RTX cards suit XPU well (RT-core acceleration). ([renderman.pixar.com/tech-specs](https://renderman.pixar.com/tech-specs); XPU Technical Specifications page)
- **VRAM: 12 GB minimum; 24 GB+ recommended** for complex production assets. *(From search excerpts of the XPU Technical Specifications page — confirm against your 27.2 build.)*
- **No out-of-core; multi-GPU does NOT pool memory** — the scene must fit in **each** GPU. CPU(-only) XPU is the over-budget fallback (matching pixels). ([general-faq](https://renderman.pixar.com/general-faq))

---

## 4. Integrators & key parameters

**PxrPathTracer** — core forward (unidirectional) path tracer; default workhorse for RIS and XPU.
- **`maxPathLength`** — absolute upper bound on ray depth. `1` = direct only; `4` = up to 3 GI bounces. Default **10**. ([PxrPathTracer ref](https://renderman.pixar.com/resources/RenderMan_20/PxrPathTracer.html))
- Per-type sample counts: `numLightSamples`, `numBxdfSamples`, `numIndirectSamples`, `numVolumeAggregateSamples` *(standard integrator controls; verify exact spelling/defaults in your build)*.
- **`allowCaustics`** — enable caustic paths (off by default in forward PT).
- **`clampDepth` / `clampLuminance`** — firefly/noise clamping (aligns noise handling across RIS and XPU).

**PxrUnified** — VCM-class unified integrator (forward PT + bidirectional/vertex-merging).
- Does **not** honor separate diffuse/specular trace depths by default (`trace:maxdiffusedepth`/`trace:maxspeculardepth` ignored) unless **`useTraceDepth`** is enabled.
- In 27, `transparencyAccum` became a **color**, so it outputs a correctly colored `Oi` for volumes with colored extinction.
- In 27, PxrPathTracer and PxrUnified **treat subsurface as diffuse** w.r.t. `maxIndirectBounces` and `trace:maxdiffusedepth` (so `maxIndirectBounces = 0` = direct diffuse + "direct" SSS).

**PxrVCM** — explicit bidirectional + progressive photon mapping (vertex merging). Full VCM by default, or pure BDPT / pure unidirectional / pure progressive photon mapping by toggling **`mergePaths`** / **`connectPaths`**. **RIS-only (no XPU).** Use for difficult caustics / specular-diffuse-specular (SDS) paths. ([PxrVCM](https://rmanwiki-27.pixar.com/display/REN/PxrVCM))

**PxrOcclusion** — ambient-occlusion integrator, **now in XPU**.
**PxrVisualizer** — diagnostic integrator (wireframe, normals, ST); XPU version improved (alpha output).

---

## 5. Sampling

RenderMan's raytrace hider supports **fixed** and **adaptive stochastic** sampling, governed primarily by **`PixelVariance`**:

- **`Ri:PixelVariance`** — upper bound on acceptable estimated pixel-value variance. **Non-zero ⇒ adaptive; zero ⇒ fixed.** Lower → more rays (cleaner); raise → allow more undersampling. ([risOptions](https://renderman.pixar.com/resources/RenderMan_20/risOptions.html); [risSampling](https://renderman.pixar.com/resources/RenderMan_20/risSampling.html))
- **`hider:minsamples`** — minimum camera rays/pixel. Since PRMan 19 **defaults to √(maxsamples)**. Raise if adaptive sampling shows artifacts.
- **`hider:maxsamples`** — max samples/pixel (in fixed mode, the uniform count). **`minsamples == maxsamples` ⇒ fixed** (but `PixelVariance` always takes precedence).
- **`hider:incremental`** — progressive refinement passes; required for interactive feedback and OpenEXR checkpoint recovery.
- **Adaptive metric** — `hider:adaptall`, `hider:darkfalloff` weight how pixels adapt (e.g. handling of dark regions). *Exact names/availability vary by version — confirm in RIS Options.*

**Per-object / per-light overrides:** integrators expose per-type sample multipliers (light vs indirect/BxDF vs volume); lights and objects can carry sample-count overrides for budgeted noise. *(Confirm precise attribute/param names against installed docs — see also `fixedsamplecount` on lights in [04-renderman-lighting](04-renderman-lighting.md).)*

**Trace / ray depth (per-object attributes):**
- **`trace:maxdiffusedepth`** — max indirect **diffuse** ray depth.
- **`trace:maxspeculardepth`** — max indirect **specular/glossy** ray depth.
- These are **object attributes, not global options** — push, e.g., specular depth deeper than diffuse selectively. ([Trace Depth](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661825))
- **`maxIndirectBounces`** — the **only** ray-depth knob in **XPU**; absolute upper bound (`1` = direct only, `4` = 3 GI bounces). In XPU the separate diffuse/specular attributes give way to this single control.

---

## 6. Denoising

Several paths:

1. **RenderMan spatial denoiser** (`denoise` command-line tool) — original cross-frame-capable filter. ([risDenoise](https://renderman.pixar.com/resources/RenderMan_20/risDenoise.html); [Denoise Tool](https://renderman.pixar.com/resources/RenderMan_20/risDenoiseTool.html))
2. **Machine-learning (ML/AI) denoiser** — introduced RenderMan 26, with an **interactive** variant for live lookdev; carried/expanded in 27. ([news/26](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26); [CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))
3. **NVIDIA OptiX denoiser** — GPU AI denoiser; NVIDIA Pascal+. OptiX 7.2+ supports layered AOV denoising (consistent with beauty) at ~10–20% extra time per added AOV layer. ([NVIDIA OptiX 7.2](https://developer.nvidia.com/blog/the-nvidia-optix-sdk-release-7-2/))

**Interactive vs batch:** ML/OptiX run interactively in viewport/IPR; the `denoise` tool runs as a batch post-process (single- or cross-frame).

**Cross-frame / temporal (animation):** `denoise` supports **`--crossframe`** (with **`-L`** to process a sequence). Best temporal stability needs **forward + backward motion vectors** (used **only** in cross-frame mode). Motion-vector files are located by name-substituting the variance filename, or `-v variance` reads them from the variance file.

**Required denoiser AOVs / DisplayChannels** (so the tool can find them): `color Ci` (beauty), `color albedo` (+ variance), `normal normal` (+ variance), `vector forward`/`backward` (cross-frame only). The master/variance image filename must end in **`_variance.exr`**; AOV `type` should be **`raw`** so the channel name is preserved. Advanced behavior is controlled by the **Advanced Denoise JSON config**. See [05-aovs-lpes-outputs](05-aovs-lpes-outputs.md) §1.5 for the full channel table. *(Channel list & `_variance.exr` convention confirmed from classic `denoise` docs — the mechanism is stable; the ML denoiser's exact channel set in 27 may differ slightly, confirm on the 27 Denoising page.)*

---

## 7. Stylized Looks (NPR) — quick note for art-directed lighting

Stylized Looks (added RenderMan 24) expanded again in 27/27.2: **`PxrStylizedHatchControl`** (up to 8 hatching layers, screen-space/triplanar), **`PxrStylizedLightControl`** (artistic lighting effects evaluated *before* standard lights), plus curvature/Sobel-edge outlines. Full treatment in [03-renderman-shading](03-renderman-shading.md) §1.7. ([CG Channel 27.2](https://www.cgchannel.com/2026/02/pixar-releases-renderman-27-2/); [DP 27.2](https://digitalproduction.com/2026/03/03/renderman-27-2-adds-usd-and-xpu-updates/))

---

## Confidence flags

| Claim | Confidence |
|---|---|
| 27.0 Nov 2025 / 27.1 Dec 2025 / 27.2 Feb 2026; XPU final-frame, RIS deprecated | High |
| No RenderMan 28 as of mid-2026 | Medium (absence of evidence) |
| XPU lacks VCM/BDPT/photon mapping; caustics ⇒ RIS | High |
| XPU 12 GB min / 24 GB rec; Pascal+; no out-of-core; per-GPU fit | Medium-High (XPU Tech Specs page 403'd) |
| Sampling params & `minsamples`=√`maxsamples` | High mechanism / Medium exact 27 defaults |
| `trace:maxdiffusedepth/maxspeculardepth` per-object; XPU uses `maxIndirectBounces` | High |
| Per-light/per-object sample override exact param names | Low (mechanism real, names unconfirmed) |
