# 03 — RenderMan Shading (anchored on RenderMan **26.x**)

> Merges three research passes (PxrSurface/materials, MaterialX Lama, OSL/patterns). **Anchored on RenderMan 26.x** (your Katana 6.5v4 pairing). The shading model — PxrSurface, Lama, OSL patterns, the material types — is the same on 26 as on 27; the one thing that differs for you is **where Lama runs: RIS only on 26.x** (XPU Lama is a 27 feature). Pixar wikis 403 automated fetches; node names/roles are corroborated across official URLs, but **verify exact parameter spellings/defaults against your installed `.args` files**. `REN26` = RenderMan 26 doc space.

---

## 1. PxrSurface — the monolithic uber-shader

A single Bxdf composed of a fixed, ordered stack of physically based lobes, each independently maskable. ([PxrSurface, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661415/PxrSurface); [REN/27](https://rmanwiki.pixar.com/display/REN/PxrSurface))

| Lobe | Purpose | Key parameter families |
|---|---|---|
| **Diffuse** | Lambert/Oren-Nayar base | `diffuseColor`, `diffuseGain`, `diffuseRoughness`, `diffuseExponent`, `diffuseTransmit`, `diffuseBackColor` |
| **Primary Specular** | Main glossy/metal reflection | `specularFaceColor`, `specularEdgeColor`, `specularFresnelMode` (Artistic/Physical), `specularIor`, `specularExtinctionCoeff`, `specularRoughness`, `specularAnisotropy`, `specularModelType` (Beckmann/GGX) ([Specular Parameters, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661441/Specular+Parameters)) |
| **Rough Specular** | Second independent specular lobe (dual-spec) | `roughSpecular*` mirror of primary |
| **Clearcoat** | Transparent coat over spec/diffuse | `clearcoatFaceColor`, `clearcoatEdgeColor`, `clearcoatIor`, `clearcoatRoughness`, `clearcoatThickness`, `clearcoatAbsorptionTint` |
| **Iridescence** | View-dependent thin-film | `iridescenceFaceGain`, `iridescenceEdgeGain`, `iridescenceMode`, `iridescenceThickness` |
| **Fuzz** | Retroreflective fabric/dust edge | `fuzzGain`, `fuzzColor`, `fuzzConeAngle` (corresponds to the Marschner R cone angle) |
| **Subsurface (SSS)** | Multiple-scatter translucency | `subsurfaceGain`, `subsurfaceColor`, `subsurfaceDmfp`, `subsurfaceDmfpColor` + model selector (§1.6) ([SSS Parameters, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661417)) |
| **Single Scatter** | Anisotropic forward scatter (skin dermis, marble) | `singlescatterGain`, `singlescatterColor`, `singlescatterMfp(Color)`, `singlescatterDirectionality` |
| **Glass** | Spec + rough refraction dielectric | `reflectionGain`, `refractionGain`, `glassRoughness`, `glassIor`, `glassAnisotropy`, `mediaColor`, `mediaTransmitColor`, `thinGlass` ([Glass Parameters, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661445/Glass+Parameters)) |
| **Glow** | Self-emission (non-light) | `glowGain`, `glowColor` |

**Other controls:** `presence` (cutout/opacity), `bumpNormal`, shadow/holdout & matte controls ([PxrSurface Mattes and Position](https://rmanwiki.pixar.com/display/REN24/PxrSurface+Mattes+and+Position)). Enabling subsurface or single-scatter forces *uncached presence* internally. The `...FresnelMode` switch (Artistic = face/edge tints; Physical = IOR/extinction) appears on specular, rough-specular, and clearcoat.

> PxrSurface also exposes user lobes useful for utility AOVs: **U3** can output world position, **U4** a user color/pattern (extract via LPE — see [05](05-aovs-lpes-outputs.md)).

---

## 2. MaterialX Lama — the strategic layering system

**What it is.** Component-based **material layering** developed at **ILM**, contributed to the open **MaterialX** standard, integrated into RenderMan (shipped in RenderMan 24, 2021). Instead of an uber-shader you build a graph of small physically-based BxDF nodes combined by dedicated layering/combiner nodes — energy-conserving and physically plausible by construction. ([MaterialX Lama, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661457); [Fundamentals: Materials](https://renderman.pixar.com/fundamentals-materials))

### Structural nodes
- **`LamaSurface`** — terminal/root node assigned to geometry; carries shared surface controls (`presence`, displacement, `inputAOV`). Confirmed params include `presence` (default `1.0`, antialiasable cutout) and `presenceCached`. **On 26.x, render Lama through RIS.** ([LamaSurface, REN26](https://rmanwiki-26.pixar.com/space/REN26/19662379))
- **`LamaLayer`** — the core combiner. Takes a **top** (`material`) and a **base** (`layer`) plus a **weight**; combines them in a Fresnel-driven, energy-conserving way (base attenuated by the top's transmission). ([LamaLayer, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661467))
- **`LamaAdd`** — adds two materials, each with its own weight. If weights sum > 1.0 you can reflect more light than received (breaks energy conservation, harms convergence). ([LamaAdd](https://rmanwiki.pixar.com/display/REN24/LamaAdd))
- **`LamaMix`** — blends two materials like a compositing "over": `mix` 0 → material1, 1 → material2; can be texture-driven (grey values cost more). ([LamaMix](https://rmanwiki.pixar.com/display/REN25/LamaMix))

### BxDF / component node library
| Node | Role |
|---|---|
| **LamaDiffuse** | Lambert/Oren-Nayar diffuse |
| **LamaConductor** | Metals (complex-IOR Fresnel); anisotropy. Coated base for car paint |
| **LamaDielectric** | Glass/acrylic/gems; colored absorption + correctly colored shadows; single scattering + `volumeAggregate` binding; **changes absorption when used as a LamaLayer top** |
| **LamaGeneralizedSchlick** | Flexible Schlick Fresnel reflection/transmission; anisotropy, glass single-scatter; also changes absorption as a LamaLayer top |
| **LamaSSS** | Subsurface scattering (skin, wax, chocolate, candles) |
| **LamaTriColorSSS** | Tri-color (RGB free-path) SSS — **the one base node NOT yet XPU-supported** |
| **LamaTranslucent** | Thin translucency / diffuse transmission (paper, leaves) |
| **LamaSheen** | Cloth/velvet/dust sheen; view-dependent (roughness ≈1.0 → near-diffuse, ≈0.0 → thin rim) |
| **LamaEmission** | Emissive contribution |
| **LamaIridescence** | Thin-film iridescence |
| **LamaHairChiang** | Layerable Chiang hair/fur BxDF (see §1.6) |

Sources: ([MaterialX Lama, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661457); [LamaConductor](https://rmanwiki-26.pixar.com/space/REN26/19661511); [LamaDielectric](https://rmanwiki-26.pixar.com/space/REN26/19661513); [LamaSheen](https://rmanwiki-26.pixar.com/space/REN26/19661523); [XPU Features & Limitations, REN27](https://renderman.atlassian.net/wiki/spaces/REN27/pages/542236818)). *(Exact per-node param spellings unverified against live pages; LamaSheen's underlying model — possibly Conty–Estévez "charlie" — is not confirmed.)*

### Layering modes (on `LamaLayer`)
- **Fresnel Blend** — weighted add; base attenuated by top's transmission. Matches MaterialX `layer`. Energy-conserving.
- **Smooth Coating** — Fresnel Blend + *refraction* through the smooth top.
- **Rough Coating** — Smooth Coating + refraction through a rough top, clamping base roughness ≥ top roughness.
- **Auto** — Fresnel Blend when base is diffuse; Rough Coating when base is specular (handles the common Diffuse < Specular < Clearcoat stack).

### Version timeline
- **24 (2021):** Lama introduced (RIS).
- **26.x (you):** full node library available, **RIS only**. XPU does **not** evaluate MaterialX/Lama in 26.
- *(27.0 added Lama to XPU as Early Access; 27.1 added XPU Lama coating absorption — both require Katana 7+, not your pipeline.)*

> **For your 26.x pipeline:** author and render all Lama materials through **RIS**. Don't expect XPU IPR to evaluate Lama correctly in 26 — for fast interactive feedback on Lama-shaded assets you're effectively relying on RIS IPR (or PxrSurface look-equivalents for viewport speed). Since your finals are RIS anyway (see [01](01-renderman-core-and-xpu.md) §2), Lama-in-RIS is fully production-ready for you.

---

## 3. Native layering: PxrLayerSurface / PxrLayer / PxrLayerMixer

RenderMan's **pre-Lama, non-MaterialX** layering — still fully supported; the recommended *native* path for layering PxrSurface-style looks (legacy assets). ([PxrLayerSurface, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661463))

- **`PxrLayerSurface`** — assigned to objects; holds the **global** parameters shared by all layers (italic params in the UI = global, can't be overridden per-layer; **bold = layerable**). e.g. the specular model (Beckmann vs GGX) is global.
- **`PxrLayer`** — an individual layer's PxrSurface-like lobe description.
- **`PxrLayerMixer`** — combines PxrLayer nodes with masks/weights (BaseLayer + up to 4 layers, Layer 1 enabled by default) and feeds the result into PxrLayerSurface. ([Using Material Layers, RFM23](https://rmanwiki.pixar.com/display/RFM23/Using+Material+Layers))

Use for car paint, decals/labels, layered dirt/mud where you want PxrSurface fidelity without MaterialX. Choose **Lama** when you need MaterialX/USD interchange/portability.

---

## 4. OSL, the pattern library, and the RSL→OSL history

### History
RSL (RenderMan Shading Language, 1990, Hanrahan & Lawson) + the **Reyes** architecture → **RIS** introduced in **RenderMan 19 (SIGGRAPH 2014)**, where everything is a C++ plug-in (BXDFs, integrators, patterns) → **RenderMan 21 (2016)** deprecated **Reyes and RSL** in favor of RIS + **OSL** for patterns → **RenderMan 24 (2021)** converted the great majority of C++ patterns to **OSL** (enabling RIS/XPU code sharing; a known side effect was a volume-integration perf regression vs 23). ([CG Channel: RM19](https://www.cgchannel.com/2014/11/pixar-ships-renderman-19/); [RM21](https://www.cgchannel.com/2016/07/pixar-releases-renderman-21/); [RM24.0 notes](https://renderman.atlassian.net/wiki/spaces/REN24/pages/21758170))

### OSL today — patterns, not materials
- OSL is the **pattern** language (texture/procedural logic feeding BxDFs). **RenderMan's OSL does NOT support material closures** — instead, pattern outputs connect into other patterns and into Bxdf/Displace inputs. **Bxdf/Displace plugins take the place of closures**, allowing more complex layering than OSL's linear closure combinations. ([OSL Patterns, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661571))
- Author `.osl` text → compile to `.oso` with **`oslc`** (ships with RenderMan). The shader name must match the `.osl` filename. The **`PxrOSL`** node loads a compiled shader into the DCC and auto-populates its UI (Compile/Reload buttons). ([Using PxrOSL, RFM26](https://renderman.atlassian.net/wiki/spaces/RFM26/pages/21037502))
- Sharing OSL across RIS and XPU gives confidence XPU renders match RIS. Large pattern networks are compiled together on the fly so the optimizer can dead-strip unused branches.

### Pxr pattern library (categories)
Master index: [Patterns, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661575). Confirmed members by category:
- **Texture (image):** `PxrTexture`, `PxrMultiTexture`, `PxrPtexture`, `PxrLayeredTexture`, `PxrProjectionLayer`
- **Procedural / noise:** `PxrChecker`, `PxrCurvature`, `PxrFractal`, `PxrVoronoise`, `PxrWorley`, `PxrPhasorNoise`
- **Manifolds & projection (placement):** `PxrManifold2D`, `PxrBumpManifold2D`, `PxrManifold3D`, `PxrProjector`, `PxrRandomTextureManifold`, `PxrRoundCube`, `PxrTileManifold`, `PxrHexTileManifold`
- **Color:** `PxrBlackBody`, `PxrBlend`, `PxrClamp`, `PxrColorCorrect`, `PxrColorSpace`, `PxrExposure`, `PxrGamma`, `PxrHairColor`, `PxrHSL`, `PxrInvert`, `PxrLayeredBlend`, `PxrMix`, `PxrRamp`, `PxrRemap`, `PxrThinFilm`, `PxrThreshold`, `PxrVary` (and `PxrColorGrade`)
- **Bump/Normal:** `PxrBump`, `PxrBumpRoughness`, `PxrNormalMap`, `PxrAdjustNormal`
- **Layer:** `PxrLayer`, `PxrLayerMixer`
- **Utility/data:** `PxrAttribute`, `PxrPrimvar`, `PxrVariable`, `PxrToFloat`, `PxrToFloat3`, `PxrTee` (taps a signal into an AOV while passing through), `PxrShadedSide`, `PxrMatteID`

Typical network: `PxrManifold2D → PxrTexture/PxrFractal → (color-correct) → PxrSurface/Lama input`.

### MaterialX networks as patterns
RenderMan consumes MaterialX networks by translating them via **ShaderGen → OSL**: "all of the patterns you use in your MaterialX networks are converted to RenderMan via OSL and should run exactly as you expect," with **PxrSurface representing most of what MaterialX defines**. ([MaterialX, REN26](https://rmanwiki-26.pixar.com/space/REN26/19662341))

---

## 5. MaterialX as a pipeline standard

MaterialX is an open standard (governed under the **ASWF**, originally Lucasfilm/ILM) defining material graphs + an exchange format, so looks are **portable** across DCCs/renderers. ([materialx.org](https://materialx.org/)) In RenderMan/HdPrman the integration is deep: Lama ships as first-class MaterialX nodes; under USD/Hydra, **HdPrman** consumes MaterialX networks (ShaderGen generates OSL on demand). Pipeline pattern: author materials in **Solaris**, publish the asset as **USD + MaterialX**, render in Karma and HdPrman alike. **Takeaway:** for assets that survive DCC/renderer churn, author in MaterialX/Lama and publish via USD; reserve PxrSurface/PxrLayer for RenderMan-only art-directed looks.

---

## 6. Specific materials

**Hair / fur**
- **`PxrMarschnerHair`** — physically plausible, energy-preserving Marschner model with **R / TT / TRT** transport, glints, eccentricity. ([PxrMarschnerHair, REN/27](https://rmanwiki-27.pixar.com/display/REN/PxrMarschnerHair); [fxguide](https://www.fxguide.com/fxfeatured/pixars-renderman-marschner-hair/))
- **`LamaHairChiang`** — layerable **Chiang** model (Disney Animation research). Better convergence, more realistic tube-like specular, remapped color across roughness; separate R/TT/TRT lobes, color remap, IOR, cone offset. ([LamaHairChiang, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661519))
- **`PxrHairColor`** — pattern node, artistic (color-inversion) and physical (melanin) modes; feeds either hair shader.
- **Recommendation:** new work → **LamaHairChiang** (modern, predictable, layerable, MaterialX-native); PxrMarschnerHair for legacy/RIS-specific setups.

**Skin / subsurface**
- Model history: **Jensen et al. (2001) dipole** → d'Eon "Better Dipole" → Burley normalized diffusion → **path-traced** (Pixar's uses anisotropic phase functions + non-exponential free flights, Wrenninge & Villemin). ([Pixar paper](https://graphics.pixar.com/library/PathTracedSubsurface/); [fxguide SSS](https://www.fxguide.com/fxfeatured/pixar-deep-dive-on-sss-siggraph-preview/))
- PxrSurface model selector covers **Jensen Dipole, d'Eon Better Dipole, Burley Normalized, Multiple Mean Free Paths, Path-Traced** (with **exponential and non-exponential** path-traced variants).
- **Guidance:** dipoles (cheap) for very translucent art-directed objects (gummies, wax); **path-traced exponential** for hero skin (accurate multiple-scatter, costs more). Pixar publishes [skin presets](https://renderman.pixar.com/skin-material-presets). In Lama use **`LamaSSS`** / **`LamaTriColorSSS`**.

**Glass / dielectric** — PxrSurface **Glass lobe** (`reflectionGain`, `refractionGain`, `glassRoughness`, `glassIor`, `mediaColor`/`mediaTransmitColor`, `thinGlass`) or **`LamaDielectric`** in Lama. For thick colored glass prefer real absorption (`mediaColor` / Lama absorption) over a tinted refraction gain.

**Fabric / sheen** — PxrSurface **Fuzz** (Marschner-R retroreflection) for fine fabric/dust edges; in Lama use **`LamaSheen`** (view-dependent edge sheen).

---

## 7. Stylized Looks / NPR

The **Stylized Looks** suite (PxrStylized*) provides non-photoreal output via a network of control nodes + display/sample filters. **On 26.x you have the pre-27.2 toolset** — solid for cel/toon/line looks, but without the big 27.2 node expansion. ([Stylization at Pixar](https://renderman.pixar.com/stories/stylization-at-pixar); [Pixar RM26 news](https://renderman.pixar.com/news/pixar-animation-studios-releases-renderman-26))

**What 26.x gives you:**
- **`PxrStylizedControl`** — hub driving the network (often paired with `PxrManifold2D` for placement).
- **`PxrStylizedToon`** — toon stepping/range/softness; produces a toon AOV signal. 26.0 added an **artistic (non-PBR) toon mode**.
- **Lines** (line detection/remapping/filtering — improved in 26.0) and a new **Canvas layer** (26.0); expanded compositing/detection modes.

Workflow: a `PxrStylizedControl`-driven network produces stylization signals/AOVs; a chain of stylized display filters composites the NPR look.

> *(27.2-only, not on your pipeline: `PxrStylizedHatchControl` with up to 8 hatching layers, `PxrStylizedLightControl`, curvature/Sobel-edge outlines, PainterlyBrush. These need Katana 7+ / RenderMan 27.)*

---

## Shading quick-guidance
- **New feature default:** author in **Lama** (LamaSurface + LamaLayer) for portability/USD interchange.
- **Proven uber-shader:** PxrSurface. **Native layering of legacy assets:** PxrLayerSurface/PxrLayer/PxrLayerMixer.
- **Hair:** LamaHairChiang > PxrMarschnerHair. **Hero skin:** path-traced exponential SSS.
- **Custom texturing:** OSL patterns (`oslc` → `PxrOSL`) feeding Bxdf inputs; never author closures in OSL.
