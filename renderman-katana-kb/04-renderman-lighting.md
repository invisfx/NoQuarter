# 04 — RenderMan Lighting (RenderMan 26/27)

> All RenderMan lights are in the **Pxr** set and share a physically-based core: intensity, exposure (power-of-2), color/temperature, per-light sampling. Hubs: [Lighting, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661727); [Lighting, REN/27](https://rmanwiki.pixar.com/display/REN/Lighting). Pixar wikis 403 automated fetches — verify exact param spellings against each light's `.args`.

---

## 1. Light types

| Light | Role / notes |
|---|---|
| **`PxrRectLight`** | Common rectangular area light (key/fill workhorse). |
| **`PxrDiskLight`** | Disk area light; soft source or, with filters, a spotlight. |
| **`PxrSphereLight`** | Spherical light; illuminates in all directions. |
| **`PxrCylinderLight`** | Cylinder area light — fluorescent tubes, lightsabers, neon. |
| **`PxrDistantLight`** | Parallel-ray infinite source — sun / distant key over the whole scene. |
| **`PxrDomeLight`** | Environment / IBL light, HDRI-mapped. **Only rotation matters** (scale/translate ignored — treated as infinitely far). Importance-sampled. |
| **`PxrPortalLight`** | Used **with** a PxrDomeLight to focus sampling through apertures (windows/skylights) for interiors. **One-sided, rectangular, NOT interchangeable with PxrRectLight** — it pulls illumination from the dome's environment. |
| **`PxrMeshLight`** | Turns arbitrary geometry into a light — far more efficient than emissive-BxDF glow; good for neon and deforming shapes. |
| **`PxrEnvDayLight`** | Physical sky+sun daylight — supply time/date + lat/long, or place the sun freely. |

Sources: [PxrDomeLight, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661747); [PxrPortalLight, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661743); [PxrMeshLight, REN/27](https://rmanwiki-27.pixar.com/display/REN/PxrMeshLight); [PxrEnvDayLight, REN26](https://rmanwiki-26.pixar.com/display/REN/PxrEnvDayLight).

**`PxrEnvDayLight` params:** `exposure`/`intensity`, sun **direction** (or month/day/year/hour + latitude/longitude/zone to compute sun position), `haziness`, `skyTint`, `sunTint`, `sunSize`, sun on/off. *(Sub-param spellings from the legacy RM20 page + well-known param set — confirm current names on the REN26 page.)*

---

## 2. Common light parameters

- **`intensity`** — linear scale of contribution.
- **`exposure`** — power-of-2 stops: +1 doubles energy; `0` → intensity 1, `-1` → 0.5. *Use exposure for stops, intensity for fine scaling.*
- **Color / temperature** — `lightColor` plus an `enableTemperature` + `temperature` (Kelvin) blackbody control. *(Toggle/param names are the long-standing Pixar names — verify in `.args`.)*
- **Importance sampling (MIS)** — samples drawn both from the **lights** (per importance metric) and from the **BxDF** (per its weighting), then combined. ([Light Sampling, RM20](https://renderman.pixar.com/resources/RenderMan_20/risLightSampling.html))
- **Light samples / `fixedsamplecount`** — RenderMan auto-balances a global sample budget across all lights, rebalancing when per-light counts change. A light given a **`fixedsamplecount`** is removed from automatic selection and assigned that count *in addition* to `numLightSamples` — pin tricky/noisy lights this way.

---

## 3. Light filters

Filters modify a light's emission and can be shared across lights / float independently. ([Light Filters, REN26](https://rmanwiki-26.pixar.com/display/REN22/Light+Filters); [REN/27](https://rmanwiki-27.pixar.com/display/REN/Light+Filters))

| Filter | What it does |
|---|---|
| **`PxrBlockerLightFilter`** | Rod/box-like blocker shaped to a volume, placed to subtract light; floats freely even if the light is static. |
| **`PxrRodLightFilter`** | Like Blocker but with more controls/flexibility. |
| **`PxrGoboLightFilter`** | Projects a painted texture (a "gobo") in front of the light. |
| **`PxrCookieLightFilter`** | Like Gobo with more options — texture/cookie projection with extra controls. |
| **`PxrBarnLightFilter`** | Barn doors — physically accurate window/barn shaping with correct shadowing; also has an **analytic** mode. |
| **`PxrRampLightFilter`** | Ramp/gradient falloff to attenuate/shape the light. |
| **`PxrIntMultLightFilter`** | Intensity multiplier — scale intensity/exposure (e.g. isolate one asset at a different exposure). |
| **`PxrCombinerLightFilter`** | Combines multiple filters under grouped operators: **Mult, Max, Min, Screen**. |

**Combiner math:** groups execute/combine in the order **max → min → screen → mult**, then multiply together — a filter that goes black in the **mult** group zeroes everything. **Max** = per-group maximum; **Mult** = multiply; **Screen** = like max but blends gradients smoothly (best for greyscale). ([Light Filters in Maya, RFM24](https://rmanwiki.pixar.com/display/RFM24/Light+Filters+in+Maya)) *(Exact behavior of **Min** inferred as per-group minimum — confirm on the live page.)*

---

## 4. Light linking, light groups, IES, dome/portal IBL

**Light linking.** Per-light/per-object include–exclude linking controls which lights illuminate which geometry (RfM/RfH/RfB light editor, and USD light-linking collections). In Katana this is the **`LightLink`** node / GafferThree — see [06](06-katana.md).

**Light groups & per-light AOVs (relighting).** Assign a group via the light's **`__group`** parameter; lights sharing a name form a group, written to **per-group AOVs** (e.g. `GroupedDiffuse_<group>`, `GroupedSpecular_<group>`) for **comp-stage relighting**. The LPE must use the **`<L.>`** form (with the dot), never bare `L`, to be light-group-compatible. Full LPE detail in [05](05-aovs-lpes-outputs.md). ([Using LPE, REN26](https://renderman.atlassian.net/wiki/spaces/REN26/pages/19661899))

**IES profiles.** Real-world IES photometric profiles load on area lights via the **Light Profile** settings to modulate intensity/throw. **Profile Range** stretches/squeezes the falloff; **Distribution Angle** focuses the throw. *(Labels from indexed RM docs — confirm on the light's page.)*

**Dome / IBL workflow & importance sampling.**
- Feed **PxrDomeLight** a float/half HDRI (EXR/HDR with values well above 1.0 — LDR maps won't light correctly). Only **rotation** orients the environment. ([PxrDomeLight, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661747))
- The dome map is **importance-sampled**: the renderer builds a ray distribution respecting the image's intensity, concentrating samples on bright regions (sun, windows).
- **Portals for interiors:** add **PxrPortalLight(s)** over apertures with the dome. Portals act as visibility hints — the renderer predominantly selects dome samples *visible through the portal* and avoids fully occluded directions, drastically cutting noise/time for indirectly lit interiors. One-sided and rectangular. ([PxrPortalLight, REN26](https://rmanwiki-26.pixar.com/space/REN26/19661743))
- Dome color controls include per-channel **gamma** and a tint over the color map.

---

## Lighting quick-guidance
- Drive lights with **exposure** (stops) + **intensity** (fine); use **temperature** for warm/cool keys.
- **Interiors:** dome + **portals** over every window/skylight — biggest single noise win.
- **Tricky/dim lights too noisy?** Pin them with **`fixedsamplecount`** instead of raising the global budget.
- **Relighting in comp:** put every light on a named **`__group`**, emit per-group AOVs via `<L.'name'>` LPEs.
- **Neon / emissive shapes:** `PxrMeshLight`, not emissive-BxDF glow.
- **Sun/sky:** `PxrEnvDayLight` (physical) or `PxrDistantLight` + dome HDRI.
