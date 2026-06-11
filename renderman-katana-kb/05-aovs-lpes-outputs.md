# 05 — AOVs / LPEs / Outputs (RenderMan)

> LPE grammar, event letters, and standard channel names are **stable across RenderMan 20→27**, so this applies to your **RenderMan 26.x** pipeline. Pixar wikis 403 automated fetch; some specifics are from indexed excerpts — flagged where only snippet-level confirmation was possible. In Katana these are authored via `PrmanOutputChannelDefine → RenderOutputDefine` (see [07](07-katana-renderman-integration.md)).

---

## 1. Light Path Expressions (LPE)

An LPE describes the **path** light travels, written from **camera (`C`)** to a **light (`L`/`O`)**, used as the `source` of a DisplayChannel/AOV so the renderer accumulates only matching energy. RenderMan follows the Heitz/OSL LPE convention shared with Arnold and Houdini/Karma. ([Using LPE, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661899); [risLPEs, RM20](https://renderman.pixar.com/resources/RenderMan_20/risLPEs.html))

### Event / transport letters
| Letter | Meaning |
|---|---|
| `C` | Camera (path always starts here) |
| `L` | Light source (terminator). Use **`<L.>`** not bare `L` for light-group compatibility |
| `D` | Diffuse scattering (paper, skin, rough wood) |
| `S` | Specular scattering (metal, glass, water, shiny dielectrics) |
| `G` | Glossy scattering (intermediate roughness) **[PARTIAL — part of shared grammar; confirmed C/L/D/S/T/R/U/O directly on RenderMan pages]** |
| `T` | Transmission (through — refraction/straight) |
| `R` | Reflection (off) |
| `U` | User event — shader-defined `U1`–`U8` (default `U1`) |
| `O` | Emission / emissive-object event (glow) |

### Operators
- **`< >`** — select a single specific event: `<RD>` = a reflection that is diffuse; `<TS>` = a transmission that is specular; `<L.>` = a light event of any subtype (the `.` = "any subtype" wildcard).
- **`[ ]`** — alternation / "any of": `[DS]` = diffuse or specular; `[RT]` = reflection or transmission.
- **`*`** — zero or more; **`+`** — one or more; **`|`** — OR (between subexpressions or light-group names).
- **`' '`** — single quotes name a **light group** or a lobe/label.
- Read **left-to-right, camera → light**; intermediate `[...]*` groups capture the bounce chain.

### Canonical examples
| Pass | LPE |
|---|---|
| Direct diffuse | `lpe:CD<L.>` |
| All diffuse (incl. bounces) | `lpe:CD*<L.>` |
| Direct diffuse incl. emission terminator | `lpe:CD[<L.>O]` |
| All contributions of one light group | `lpe:C[DS]*<L.'name'>` |
| Refraction/transmission for a light group (caustic form) | `lpe:C<TS>+[DS]*<L.'name'>` |
| Multiple light groups OR'd | `lpe:C<[RT][DS]>*[<L.('key'\|'fill')>O]` |

- **Direct vs indirect** = number of scattering events before the light (one ⇒ direct; intermediate `[DS]*`/`[RT]*` groups ⇒ indirect).
- **Caustics** = a specular/transmission chain reaching a diffuse receiver before the light.
- **SSS / subsurface** = use the dedicated `subsurface` preset (PxrSurface routes its subsurface lobe there) rather than hand-writing a path.
- **Emission / glow** = path terminates on `O` rather than `L`.

**RIB declaration form:**
```
DisplayChannel "color directDiffuse" "string source" ["color lpe:CD[<L.>O]"]
```
The `lpe:` prefix marks the channel as LPE-driven. ([AOVs, RFM26](https://renderman.atlassian.net/wiki/spaces/RFM26/pages/21037114))

---

## 2. Standard AOV preset set & beauty decomposition

RenderMan ships **LPE presets** (short names the renderer expands). Core production set: `directDiffuse`, `indirectDiffuse`, `directSpecular`, `indirectSpecular`, `subsurface`, `emissive`, `albedo`. ([Using LPE, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661899)) **[PARTIAL — existence/naming confirmed from snippets; full enumerated table not read verbatim; confirm in your install.]**

**Beauty decomposition is additive:** `Ci ≈ directDiffuse + indirectDiffuse + directSpecular + indirectSpecular + subsurface + emissive`. RenderMan deliberately folds lobes into shared AOVs (e.g. glass-lobe reflections go into `directSpecular`/`indirectSpecular`). PxrSurface has three specular lobes (primary, clearcoat, rough) plus user lobes — world position on **U3**, user color on **U4**, extractable via LPE as utility AOVs.

---

## 3. Per-light AOVs & light groups (relighting)

- **Group assignment:** set the light's **`__group`** parameter to a shared name. ([Using LPE, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661899))
- **Two equivalent LPE forms:**
  - Short: `lpe:diffuse_key` (preset `_` group name)
  - Long: `lpe:CD<L.'key'>`
- **Always `<L.>` (with the dot), never bare `L`** — otherwise the renderer warns and the expression isn't light-group-compatible.
- **Multiple groups:** OR with `|` → `lpe:C<[RT][DS]>*[<L.('key'|'fill')>O]`.
- This is the foundation of **in-comp relighting**: scale/tint each group AOV and re-add without re-rendering.

---

## 4. Holdouts, IDs, Cryptomatte, deep

**Holdouts / matte objects.** Enable with the **`trace holdout`** attribute on the object. Implemented **at the integrator level**, so it catches diffuse/specular reflections, transmissions, and caustics from the held-out CG onto the plate — embeds CG shadows/reflections into a live-action plate. The **`PxrImageDisplayFilter`** can preview the plate comp in-renderer. ([Holdouts, REN24](https://renderman.atlassian.net/wiki/spaces/REN24/pages/21759851))

**Cryptomatte (`PxrCryptomatte`).** A **SampleFilter** producing anti-aliased ID mattes from **string user attributes**; instantiate **multiple filters** with different criteria (per-object, per-material). Manifest location: **`None` / `Header` (default) / `Sidecar`** (JSON name→ID); written to a **separate EXR**. ([PxrCryptomatte, REN27](https://renderman.atlassian.net/wiki/spaces/REN27/pages/542235274)) **[UNVERIFIED: exact user-attribute key strings driving it.]**

**Deep EXR.** Stores per-pixel depth functions for correct depth comp + volumetric comp without holdouts. RenderMan provides a **DeepEXR** display driver; route the primary (`RI_RGBA`/`RI_RGBAI`) or any AOV to it. Subpixel deep functions are filtered to one per-pixel function on write. ([DeepEXR, REN25](https://renderman.atlassian.net/wiki/spaces/REN25/pages/20416874)) Cost: heavier than flat — reserve for elements needing depth comp (see [02](02-render-optimization.md) §7).

---

## 5. Display drivers, channels, denoiser AOVs

**Display drivers.** Production shallow drivers: **`d_openexr`** and **`d_tiff`** (8-bit→float, arbitrary channels). ([Display Drivers, RM20](https://renderman.pixar.com/resources/RenderMan_20/display.html)) Notable `d_openexr` options: **`int asrgba`** (first four channels labeled RGBA), **`exrheader_$key`** (inject EXR header metadata).

**Display channels.** `DisplayChannel` declares a named channel (type + `source`); `Display` references channels + a driver. In Katana split into **`PrmanOutputChannelDefine`** (→ `RiDisplayChannel`) wired into **`RenderOutputDefine`** (→ `RiDisplay`). ([Setting up AOVs in Katana](https://rmanwiki.pixar.com/display/RFK22/Setting+up+AOVs+in+Katana))

**Display / Sample Filters.** Image-space ops, e.g. `PxrImageDisplayFilter` (plate comp/holdout preview), `PxrCryptomatte` (sample filter).

**Denoiser AOV requirements.** The `denoise` utility expects a **multichannel OpenEXR with specific channel names**, each channel's `type` = **`raw`** so the name is preserved. ([Denoiser AOVs, REN26](https://rmanwiki.pixar.com/display/REN26/Denoiser+AOVs); [Denoising, REN23](https://renderman.atlassian.net/wiki/spaces/REN23/pages/19038611))

| DisplayChannel | source / statistics |
|---|---|
| `color Ci` | beauty radiance |
| `float a` | alpha |
| `color mse` | source `Ci`, statistics `mse` |
| `color albedo` + `color albedo_var` | unlit albedo + variance |
| `color diffuse` + `color diffuse_mse` | diffuse + mse |
| `color specular` + `color specular_mse` | specular + mse |
| `normal normal` + `normal normal_var` | shading normal + variance |
| `float zfiltered` + `float zfiltered_var` | filtered depth + variance |
| `float sampleCount` | source `sampleCount` |
| `vector forward`, `vector backward` | motion vectors — **cross-frame denoising only** |

Minimal single-frame: `Ci` + `a` + `mse`. `albedo`/`normal` layers **improve** quality (and `normal` requires `albedo` present). **[PARTIAL: channel set & statistics keywords corroborated; verify `_var` vs `variance` suffix casing locally. The ML denoiser's exact channel set in 26/27 may differ slightly.]**

---

## AOV/output quick-facts
- **Beauty = additive lobes**; emit the standard preset set for full comp control.
- **Relighting** = `__group` per light + per-group LPE AOVs (`<L.'name'>`, never bare `L`).
- **Mattes** = `PxrCryptomatte` (multiple filters for object/material), manifest in Header or Sidecar.
- **Depth comp / volumes** = DeepEXR driver (costly — use selectively).
- **Denoise** = multichannel EXR, `raw` channel type, `_variance.exr` master, motion vectors for cross-frame.
- **In Katana** = `PrmanOutputChannelDefine → RenderOutputDefine`, `interactiveOutputs` for live.
