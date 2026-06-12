# 12 — Lookdev Artist Workflow (Katana 6.5v4 + RenderMan 26.x)

> The lookdev artist's process: build and sign off a material/asset so it holds up under any lighting and travels cleanly to shot lighting. Anchored on **Katana 6.5v4 + RenderMan 26.x**. Cross-refs: shading → [03](03-renderman-shading.md), rigs/color → [10](10-lookdev-color-workflow.md), Katana material nodes → [06](06-katana.md).

---

## The asset at a glance

```
turntable rig → build materials → calibrate → IPR iterate → QC under
multiple environments → publish (LookFile) → sign-off
```

Core 26.x rule: **author in Lama for portability, but judge/render it in RIS** (XPU won't evaluate Lama on 26). Use PxrSurface when you want XPU IPR speed or a self-contained uber-shader.

---

## 1. Build (or open) the turntable rig

Use the studio's standard lookdev rig so every asset is judged identically.

1. **Neutral environment** — a uniform mid-grey dome (or studio 3-point: key `PxrRectLight` + fill + rim) plus a turntable rotation on the asset/camera.
2. **Reference props in-frame** — **grey ball** (diffuse/lighting reference), **chrome ball** (reflections/light positions), **Macbeth / X-Rite ColorChecker** (color ground truth + mid-grey). ([10](10-lookdev-color-workflow.md) §1)
3. **Lighting conditions to switch between** — keep several HDRIs ready on the dome (neutral studio, sunny exterior, overcast, warm interior) so you can QC the look in §5.
4. **Color** — confirm the rig uses the show OCIO config; rendering space = **ACEScg**. ([10](10-lookdev-color-workflow.md) §2)

---

## 2. Build materials (NetworkMaterialCreate)

1. **`NetworkMaterialCreate`** — press **Tab** inside to add shading nodes; lay the graph left-to-right with labeled ports.
2. **Pick the surface model** ([03](03-renderman-shading.md)):
   - **Lama** (`LamaSurface` + `LamaLayer` stacks) for layered/portable looks — car paint, coatings, dirt-over-base. *Render in RIS on 26.*
   - **PxrSurface** for a proven single uber-shader (and faster XPU IPR).
   - **PxrLayerSurface/PxrLayer/PxrLayerMixer** for native layering of legacy assets.
3. **Texturing** — connect `PxrTexture` (mipmapped **`.tex`** via `txmake`; 8-channel cap on 26) through `PxrManifold2D` placement; build procedural detail with `PxrFractal`/noise + color-correct patterns. Custom logic → **OSL patterns** (`oslc` → `PxrOSL`) feeding Bxdf inputs. ([03](03-renderman-shading.md) §4)
4. **Tag texture color spaces** (sRGB-texture vs raw/data) so `txmake` converts into ACEScg correctly. ([10](10-lookdev-color-workflow.md) §2)
5. **Material types** — hair → `LamaHairChiang`; hero skin → path-traced (exponential) SSS; glass → Lama `LamaDielectric` or PxrSurface glass lobe; fabric → `LamaSheen`/Fuzz. ([03](03-renderman-shading.md) §6)

**6.5 lookdev aids you have:**
- **Material Solo** — short-circuit the network to preview individual sections (keys 1–9). Indispensable for isolating a lobe/texture while dialing it.
- **LiveShadingGroups** (`LiveShadingGroup` inside NMC) — reuse/share sections of a network across assets/artists.
- **6.5v4** added `NetworkMaterialLayoutFilter` (perf in multi-material contexts), `MaterialInterfaceResolve` (propagate interface changes downstream), `NetworkMaterialMultiSplice`.

---

## 3. Calibrate

1. **Mid-grey** — set/confirm the mid-grey value against the ColorChecker neutral patch.
2. **Albedo sanity** — diffuse albedos in plausible PBR ranges (no pure black/white); check the `albedo` AOV.
3. **Energy** — Lama is energy-conserving by construction; for PxrSurface watch additive lobe gains (don't reflect more than received).
4. **Neutral read** — under the neutral dome the asset should read believably before you touch any stylization.

---

## 4. IPR iteration

1. **Live render** in the Viewer. For **PxrSurface** assets use **XPU IPR** (fast); for **Lama** assets judge in **RIS IPR** (XPU won't evaluate Lama on 26).
2. **Interactive ML denoiser ON** — read material response in a few samples.
3. **Solo lobes** via Material Solo; check specular roughness/Fresnel, SSS depth, coat behavior, anisotropy under rotation.
4. **Rotate the turntable** and watch the chrome/grey ball — reflections, Fresnel falloff, and SSS should behave across angles and lighting.

---

## 5. QC under multiple environments

Switch the dome HDRI through your conditions (studio → sun → overcast → warm interior). The material must hold up in **all** of them — no blown speculars in sun, no muddy diffuse in overcast, plausible SSS in warm light. Note breakdowns and fix at the material level, not by re-lighting the rig.

Also QC: displacement bounds (no clipping/over-dicing), presence/cutouts on thin geo, and texture filtering (remember XPU previews one MIP coarser than the RIS final — confirm sharpness in RIS).

---

## 6. Publish (LookFile)

1. **`LookFileBake`** — bake the *differences* (materials + overrides) into a Look File for downstream assignment. ([06](06-katana.md) §4)
2. **Assign/resolve** via **`LookFileManager`** (resolves with global settings/overrides) and `LookFileAssign` (maps by root names / `rootIds`).
3. **Version** the publish per the show convention; record the asset/lookdev version so shot lighting binds the right one.
4. **(USD pipelines)** author/compose with 6.5's native USD nodes if you publish materials as USD; full Katana→USD round-trip export is an 8.0 feature you don't have, so LookFile is your primary hand-off on 6.5. ([09](09-usd-solaris-pipeline.md))

---

## 7. Sign-off

1. **Turntable render** under the neutral rig (and one or two hero conditions) — RIS, final-quality.
2. **AOV breakdown** — beauty + lobe AOVs so the supe can see diffuse/spec/SSS separately.
3. **Reference comparison** — side-by-side with concept/photo reference and the ColorChecker.
4. **Supe review → notes → revise → re-publish.** Lock the version once approved.

---

## Per-asset checklist
- [ ] Standard turntable rig; reference props in-frame; ACEScg/OCIO confirmed.
- [ ] Surface model chosen (Lama = RIS; PxrSurface = XPU-IPR-friendly); textures `.tex` + color-space tagged.
- [ ] Calibrated: mid-grey, albedo ranges, energy, neutral read.
- [ ] Iterated with Material Solo + interactive denoiser; turntable behaves.
- [ ] QC'd under multiple HDRIs; displacement/presence/filtering checked.
- [ ] Published via LookFileBake; versioned; assignable.
- [ ] Sign-off turntable + AOV breakdown approved; version locked.
