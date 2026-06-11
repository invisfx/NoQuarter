# 02 — Render Optimization at Animation Scale (anchored on RenderMan **26.x**)

> Companion to [01-renderman-core-and-xpu](01-renderman-core-and-xpu.md). **Anchored on RenderMan 26.x** (your Katana 6.5v4 pairing). Parameter names are stable across RenderMan 20–26; confirm exact 26.x defaults in your install. Items that are 27-only are labeled as such. Remember the core 26.x rule: **finals render in RIS; XPU is interactive-only** — so all farm/checkpoint/deep/holdout optimization below is **RIS** on your pipeline.

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

- **`txmake`** converts source images to RenderMan **`.tex`**: tiled + **mipmapped** pyramids (each level halved in S and T), improving antialiasing and letting the renderer load only the appropriate mip level per shading grid. A mipmapped `.tex` is ~⅓ larger than the source. **On 26.x this `.tex` conversion is your standard texture-prep step** (the native mipmapped-EXR "skip conversion" path is a 27 feature). ([txmake(1)](https://renderman.pixar.com/resources/RenderMan_20/txmake.1.html))
- **Channel cap:** 26.x textures carry up to **8 channels** each (the 8→64 raise is 27.2) — pack utility/AOV textures accordingly.
- *(27-only, not on your pipeline: OpenImageIO-based faster conversion + native mipmapped-EXR support that lets you skip `.tex`; 64-channel textures.)*
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
- **On 26.x, checkpointing is a RIS feature.** Since your finals run in RIS anyway, this is exactly where you want it — combine **checkpoint + `-recover`** on every farm render. *(XPU checkpointing is 27-only.)*

---

## 7. Deep vs flat; threading, RAM, farm strategy

- **Deep EXR** stores multiple depth samples per pixel for correct depth-composited holdouts and volume merging; substantially heavier than flat output in **file size and write/merge cost** — reserve deep for elements that need depth compositing (volumes, holdout-heavy layered comps), not every pass. **On 26.x, deep output is a RIS feature** (XPU deep is "Coming soon" in 26 / lands in 27) — another reason finals go through RIS. ([DeepEXR, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661873); [Holdouts, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661827)) *(Flat-vs-deep cost multipliers qualitative.)*
- **Threading/RAM/farm:** RIS scales across CPU cores; budget RAM for the texture cache (§4) plus diced geometry/displacement working set. On the farm, combine **checkpointing + `-recover`** (RIS) for resilient long renders and to free preemptible nodes.

---

## 8. XPU GPU memory (26.x — interactive use)

Since XPU on 26.x is for **interactive lookdev/IPR**, GPU memory is about keeping your viewer sessions responsive, not farm finals:
- **Single-GPU** in 26 (multi-GPU is 27). NVIDIA **Pascal+**; VRAM **11 GB min, 24 GB suggested**. **No out-of-core** — the interactive scene must fit in VRAM. ([XPU Tech Specs, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661989))
- XPU samples textures **one MIP coarser than RIS** to fit more in VRAM (previews slightly softer than the RIS final).
- Lever VRAM down with: tighter texture working set (mip/RtxPlugin), instancing, render-time procedurals, trace subsets.
- For over-budget or final scenes, **use RIS** (your final-frame engine anyway).

---

## Practical optimization checklist

1. **Adaptive sampling** on (`PixelVariance` ≠ 0), sensible `maxsamples` ceiling, `minsamples` = √maxsamples.
2. **Denoise** (ML/OptiX) to cut samples; emit `Ci`+`albedo`(+var)+`normal`(+var)+motion vectors; `_variance.exr`, `raw` channel type.
3. **Trace depth** minimal; per-object overrides in RIS; `maxIndirectBounces` in XPU.
4. **Caustics?** → RIS + PxrVCM.
5. **Textures** mipmapped via `.tex` (txmake); 8-channel cap; RtxPlugin for huge sets; budget the cache.
6. **Trace subsets** to drop irrelevant geometry from secondary rays.
7. **Checkpoint + `-recover`** (RIS) on every farm render; OpenEXR for incremental.
8. **Deep** (RIS) only where depth comp needs it.
9. **Finals → RIS**; XPU for interactive lookdev (single-GPU, fits VRAM).
