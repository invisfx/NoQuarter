# 02 — Render Optimization at Animation Scale (RenderMan 27.x)

> Companion to [01-renderman-core-and-xpu](01-renderman-core-and-xpu.md). Parameter names are stable across RenderMan 20–27; confirm exact 27.x defaults in your install. Pixar wikis 403 automated fetches — some specifics are from indexed excerpts.

---

## 1. Sampling strategy & denoiser-driven sample reduction

- Drive quality with **`PixelVariance`** (adaptive) rather than brute-force fixed samples; set a **`maxsamples`** ceiling and let **`minsamples` (= √maxsamples)** floor it; raise `minsamples` only when adaptive sampling shows artifacts. ([risOptions](https://renderman.pixar.com/resources/RenderMan_20/risOptions.html))
- **Denoiser-driven reduction is the core animation-scale lever:** render to a *higher* `PixelVariance` / lower sample budget and let the ML/OptiX denoiser clean residual noise. Pair with the required variance/albedo/normal AOVs and **forward+backward motion vectors** for temporal stability across a shot (see [05](05-aovs-lpes-outputs.md) §1.5). ([news/26](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26); [risDenoise](https://renderman.pixar.com/resources/RenderMan_20/risDenoise.html))
- Spend samples where they matter via **per-light / per-object sample overrides** and per-type integrator sample counts (light vs indirect vs volume) instead of globally raising `maxsamples`.

---

## 2. Ray depth, MIS/importance sampling, caustics

- Keep ray depth as low as the look allows. **RIS:** tune `trace:maxdiffusedepth` and `trace:maxspeculardepth` **per object** — push depth only where needed. **XPU:** only the global **`maxIndirectBounces`** is available. ([Trace Depth](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661825))
- Integrators use **MIS / importance sampling** for direct lighting (combining light and BxDF sampling); per-light sample counts balance many-light noise.
- **Caustics:** forward PxrPathTracer needs **`allowCaustics`** and still struggles with hard caustics. Production caustics → **PxrVCM** (BDPT + photon mapping/vertex merging), which is **RIS-only** — so caustic-heavy shots are a reason to stay on RIS rather than XPU. ([PxrVCM](https://rmanwiki-27.pixar.com/display/REN/PxrVCM); [DP](https://digitalproduction.com/2025/09/25/renderman-27-xpu-graduates-ris-retires/))

---

## 3. Geometry: subdivision, displacement, instancing, procedurals

- **Subdivs** adaptively tessellate to micropolygons sized in screen pixels; key control is **micropolygon length**, default **1 pixel**. Increase (coarser dicing) to save memory/time where fine detail is unneeded. ([Modeling Guidelines](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661435/Modeling+Guidelines))
- **Displacement bounds:** set a tight-but-sufficient displacement bound — too large wastes dicing/memory, too small clips displacement. (Bound attribute on the displaced primitive.) ([RIS Attributes](https://renderman.pixar.com/resources/RenderMan_20/risAttributes.html))
- **Instancing dicing:** tune with **`instancestrategy`** (default **`worlddistance`**) and **`instanceworlddistancelength`** — important for memory on heavily instanced scenes (foliage, crowds).
- **Render-time procedurals** (`RiProcedural`) generate geometry on demand during render; graphics state is restored per procedural before subdividing. Use for memory-bounded crowds/instances/hair so geometry materializes only when hit. ([Procedural Primitives](https://renderman.pixar.com/resources/RenderMan_20/proceduralPrimitives.html))

---

## 4. Texture pipeline

- **`txmake`** converts source images to RenderMan **`.tex`**: tiled + **mipmapped** pyramids (each level halved in S and T), improving antialiasing and letting the renderer load only the appropriate mip level per shading grid. A mipmapped `.tex` is ~⅓ larger than the source. ([txmake(1)](https://renderman.pixar.com/resources/RenderMan_20/txmake.1.html))
- **RenderMan 27** added **OpenImageIO-based** faster conversion and **native mipmapped-EXR support** — render directly from mipmapped EXR and **skip the `.tex` step**. **27.2** raised textures from **8 to 64 channels** each. ([CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/); [CG Channel 27.2](https://www.cgchannel.com/2026/02/pixar-releases-renderman-27-2/))
- **RtxPlugin / RtxTexture (on-demand texturing):** the **RtxPlugin** C++ API responds to texture requests by filling cache tiles on demand at the resolution appropriate to the shading grid; the renderer reuses cached tiles and applies its own filtering/AA — the basis of out-of-core texturing for huge budgets. ([RtxPlugin](https://renderman.pixar.com/resources/RenderMan_20/rtxPlugin.html))
- **Texture-cache budget:** the renderer keeps a bounded in-RAM texture cache and pages tiles; budget so the working set fits without thrashing. *(Exact 27 option name for the cache-size budget not confirmed here — verify in your build's options reference.)*

---

## 5. Trace sets / subsets (selective ray visibility)

- **Grouping membership** via the **`grouping:membership`** string attribute (Maya: selection sets / shading groups); the **`categories`** parameter tags geometry/lights. A primitive can belong to multiple groups. ([Grouping Membership](https://rmanwiki.pixar.com/display/RFH22/Grouping+Membership))
- **Trace subsets** are set on the *affected* object: **Trace Subset** is inclusive (trace only these), **Exclude Subset** is exclusive (trace everything except these). Control which objects appear in reflections/refractions/shadows/AO — both a look tool and an optimization (skip expensive irrelevant geometry in secondary rays). ([Trace Sets](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661865))

---

## 6. Checkpointing, recover/resume, incremental rendering

- Enable via the checkpoint **Option** or **`-checkpoint`** on `prman` (time- or pass-interval based). Checkpoints embed extra recovery state, so they're slightly larger than normal images. ([Checkpointing & Recovery](https://renderman.pixar.com/resources/RenderMan_20/risRecovery.html))
- Resume an interrupted render with **`-recover 1`**: PRMan inspects existing images and continues near where it stopped; if images are finished/missing/mismatched it silently restarts.
- **Incremental rendering** (`hider:incremental`) refines the whole image over repeated passes; **checkpointing of incremental renders requires OpenEXR** + the checkpoint option.
- **27 milestone:** **XPU now supports checkpointing** (essential for farm management); **27.1** fixed XPU's post-checkpoint command to run after a successful render like RIS. ([CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/); [DP 27.1](https://digitalproduction.com/2025/12/09/checkpoint-fixed-pixar-ships-renderman-27-1/))

---

## 7. Deep vs flat; threading, RAM, farm strategy

- **Deep EXR** stores multiple depth samples per pixel for correct depth-composited holdouts and volume merging; substantially heavier than flat output in **file size and write/merge cost** — reserve deep for elements that need depth compositing (volumes, holdout-heavy layered comps), not every pass. ([DeepEXR](https://rmanwiki-26.pixar.com/space/REN26/19661873/DeepEXR); [Holdouts](https://rmanwiki-26.pixar.com/space/REN26/19661827)) *(Specific flat-vs-deep cost multipliers not found in an official source — qualitative.)*
- **27 deep workflow:** full support for **OpenEXR Deep IDs** and auto-generated **OpenEXR 3.0-style ID manifests** for deep compositing; XPU supports deep output. ([CG Channel 27](https://www.cgchannel.com/2025/11/pixar-releases-renderman-27/))
- **Threading/RAM/farm:** RIS scales across CPU cores; budget RAM for the texture cache (§4) plus diced geometry/displacement working set. On the farm, combine **checkpointing + `-recover`** for resilient long renders and to free preemptible nodes. For **XPU farms, schedule by GPU/VRAM** as the binding constraint (§8).

---

## 8. XPU GPU memory at scale

- **No out-of-core:** scene must fit in VRAM; **multi-GPU does NOT pool memory** — it must fit in **each** GPU. Plan VRAM budget per node; **12 GB min, 24 GB+ recommended**. CPU(-only) XPU is the over-budget fallback (matching pixels). ([general-faq](https://renderman.pixar.com/general-faq))
- Lever VRAM down with: tighter texture working set (mip/RtxPlugin), instancing, render-time procedurals, and trace subsets to limit secondary-ray geometry.

---

## Practical optimization checklist

1. **Adaptive sampling** on (`PixelVariance` ≠ 0), sensible `maxsamples` ceiling, `minsamples` = √maxsamples.
2. **Denoise** (ML/OptiX) to cut samples; emit `Ci`+`albedo`(+var)+`normal`(+var)+motion vectors; `_variance.exr`, `raw` channel type.
3. **Trace depth** minimal; per-object overrides in RIS; `maxIndirectBounces` in XPU.
4. **Caustics?** → RIS + PxrVCM.
5. **Textures** mipmapped (`.tex` or native mip-EXR in 27); RtxPlugin for huge sets; budget the cache.
6. **Trace subsets** to drop irrelevant geometry from secondary rays.
7. **Checkpoint + `-recover`** on every farm render; OpenEXR for incremental.
8. **Deep** only where depth comp needs it.
9. **XPU**: confirm scene fits per-GPU VRAM; else CPU-only fallback.
