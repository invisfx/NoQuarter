# 10 — Lookdev / Color Management / Comp Workflow

> Practical lighting-lead workflow: lookdev rigs & calibration, ACES/OCIO color management across RenderMan + Katana 6.5v4 + Nuke, multi-shot lighting, relighting, and comp hand-off. Pixar/Foundry docs 403 automated fetch; some specifics from indexed excerpts.

---

## 1. Lookdev rigs & calibration

**IBL / dome.** Environment lighting via **`PxrDomeLight`** (HDRI). **Only rotation matters** (scale/translate ignored — treated as infinite), so orient the HDRI to match plate lighting; on-set HDRIs typically get you 80%+ of the way before rig tweaks. ([PxrDomeLight, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661747))

**Calibration geometry (on-set + lookdev reference):**
- **Chrome ball** → light positions, camera, set reflections. ([CAVE Academy](https://caveacademy.com/wiki/onset-production/data-acquisition/data-acquisition-training/the-grey-the-chrome-and-the-macbeth-chart/))
- **Grey ball** → diffuse lighting direction/intensity reference.
- **Macbeth / X-Rite ColorChecker** → color-calibration ground truth; also sets mid-grey. ([CAVE Academy ColorChecker](https://caveacademy.com/using-the-macbeth-chart-grey-and-chrome-balls-for-look-dev-and-lighting/))

A uniform mid-grey turntable dome (or studio rig + turntable) plus these three reference props is the canonical **neutral lookdev environment**.

**Lookdev utility nodes.** RenderMan-side lookdev utilities are the **`Pxr*` pattern nodes** — e.g. **`PxrTee`** taps a signal into an AOV while passing it through; PxrSurface's **U3 (world position)** / **U4 (user color)** lobes push utility data into LPE AOVs. **[UNVERIFIED:** an official Pixar node literally named `PxrLookdevKit` / `PxrColorChecker` could not be confirmed — "LookdevKit" as documented is the Maya/Autodesk utility-node plug-in. Use `Pxr*` patterns on the RenderMan side.]

---

## 2. Color management — ACES / OCIO v2

**RenderMan + OCIO.** RenderMan reads arbitrary OCIO configs via a **JSON sidecar** named **`rman_color_manager_CONFIGNAME.json`** (`CONFIGNAME` = the dir containing `config.ocio`), located in **`$RMAN_COLOR_CONFIG_DIR`** or **`$RMANTREE/etc`**. The JSON exposes Roles/ColorSpaces in UI, defines texture-name aliases for auto-detection, and gives the Texture Manager initial `txmake` rules. ([Custom OCIO Config, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661971); [Color Management, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661975))
- **Rendering color space** = where the renderer computes. For ACES set it to **ACEScg** (scene-linear, wide-gamut). ([ACES Setup, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661977))
- A non-ACES default uses **scene-linear Rec.709/sRGB** with an sRGB-gamma view.
- **Tag textures with their input color space** (sRGB-texture vs raw/data) so `txmake` converts correctly; the JSON alias list drives auto-detection.

**Katana + OCIO.** Set the **`OCIO`** env var to point at the ACES `config.ocio` so Katana's color picking and monitor LUTs use the same config; an ACES config sets the working/`scene_linear` role to **ACEScg**. ([ACES in Katana, ACESCentral](https://community.acescentral.com/t/aces-in-katana/4107)) *(On your Katana 6.5, USD/OCIO are 23.05-era — confirm the bundled OCIO version; OCIO v2 ACES configs work via the `OCIO` env var.)*

**OCIO v2 / ACES 2.0.** OCIO v2 ships **ACES built-in configs** exposing ACES Output Transforms as OCIO **views**. ([OpenColorIO Using OCIO](https://opencolorio.readthedocs.io/en/v2.4.0/guides/using_ocio/using_ocio.html))

**End-to-end principle:** render & store EXRs in **scene-linear ACEScg**, archive plates/masters in **ACES2065-1**, and apply the ACES **Output/Display transform (RRT+ODT / ACES 2.0 Output Transform)** only as a **view at display/comp time**. Drive RenderMan, Katana, and Nuke from the **same `config.ocio`**.

---

## 3. Multi-shot / sequence lighting & relighting

- **Template / master lighting.** Build a master rig (dome + key/fill/rim, each on a named **`__group`**), propagate across a sequence, ride per-shot overrides on top. Katana's node-graph + scene-graph-location override model makes this natural; per-light groups keep the master rig re-lightable downstream.
- **Relighting via light groups.** Emit one AOV per `__group` (`lpe:diffuse_key`, `lpe:specular_key`, …). In comp, scale/tint each group AOV and re-add — rebalance the rig without re-rendering. (See [04](04-renderman-lighting.md), [05](05-aovs-lpes-outputs.md).)
- **Slap comp.** A standardized Nuke template that auto-assembles per-lobe/per-group AOVs (diffuse + specular + SSS + emissive, optionally per-light) into a recomposed beauty — your immediate lighting-iteration preview. RenderMan's `PxrImageDisplayFilter` gives an in-renderer plate/holdout slap-comp preview; the production slap comp lives in Nuke.

---

## 4. Nuke integration (comp)

- **Multichannel EXR.** RenderMan multichannel EXRs group AOVs as layered channels (`diffuse.R/G/B`, `specular.R/G/B`, …). Use **`Shuffle`** to extract a layer → grade → recombine. Lobes (diffuse/spec/SSS), `Z` (DOF), normals (in-comp relight), world position (relight/fog), motion vectors (motion blur) are all driven non-destructively. ([Whizzy: multichannel EXR in Nuke](https://www.whizzystudios.com/post/breaking-down-multichannel-exr-files-in-nuke-for-flexible-compositing))
- **Cryptomatte.** Read the Cryptomatte EXR (or shuffle out the crypto AOV) → feed the **Cryptomatte gizmo** → click to extract object/material mattes. RenderMan's JSON manifest (Header/Sidecar) supplies the name→ID mapping. ([PxrCryptomatte, REN27](https://renderman.atlassian.net/wiki/spaces/REN27/pages/542235274))
- **Deep.** Read deep with **`DeepRead`**; Nuke imports deep OpenEXR **3.2.1+ in scanline** form (**tiled deep EXR not supported**) — relevant when configuring the RenderMan DeepEXR driver. ([Foundry: Reading deep footage](https://learn.foundry.com/nuke/content/comp_environment/deep/reading_deep_footage.html))
- **Color in comp.** Drive Nuke from the same `config.ocio` (`OCIO` env var) so working space stays ACEScg and the ACES Output Transform is applied as the view. ([Foundry: OCIO config in Nuke](https://learn.foundry.com/nuke/14.0/content/comp_environment/configuring_nuke/using_ocio_config_files.html))

---

## Workflow quick-facts
- **Neutral lookdev** = mid-grey turntable dome + chrome/grey ball + Macbeth chart; calibrate mid-grey.
- **Color** = ACEScg rendering space everywhere; same `config.ocio` across RenderMan/Katana/Nuke; ODT as a view only.
- **Sequence lighting** = master rig with named `__group`s + per-shot overrides.
- **Relight in comp** = per-group AOVs, scale/tint/re-add; slap comp template in Nuke.
- **Comp hand-off** = multichannel EXR (Shuffle), Cryptomatte gizmo, DeepRead (scanline deep).
