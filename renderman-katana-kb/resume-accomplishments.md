# Resume / Accomplishment Log

> Running log of production work from this session, phrased so each bullet can drop
> into a resume or performance review. Add to it as we go. Numbers in brackets are
> things worth quantifying later (shot counts, time saved, % improvements).

## Lighting pipeline — Katana 6.5 / RenderMan 26

- Built and validated an end-to-end **motion-vector pipeline** (RenderMan `motionFore`/`motionBack` → Nuke VectorBlur2): diagnosed axis/handedness and shutter-convention mismatches, documented the correct Nuke settings, eliminated the need for 3D motion blur on [N] passes.
- Designed a **refracted-matte AOV technique** using LPEs and user lobes (`C<TS>+U4L`) so RGB ID mattes survive refraction through glass — something Cryptomatte cannot do; verified in production renders.
- Implemented **typed user-attribute ID mattes** (PxrMatteID) via OpScript, including the correct typed-attribute form Katana's AttributeSet cannot author.
- Authored per-light **indirect-bounce LPE stacks** and an OpScript channel generator that builds output channels from light-group definitions.
- Investigated and explained **adaptive sampling behavior** (PixelVariance stillness test vs. min-samples) on volumetric passes, including PxrVolume's per-ray sample controls; produced guidance adopted by the team.
- Verified and documented **CEL regex matching** (`~=`), expression-language gotchas (`getVar`, `getParam` reference semantics, ResolutionTable API split), reserved primvar names, and primvar type conventions — now the team's quick reference.

## Tools written (Python / Lua)

- **Overscan automation** — OpScripts deriving overscan from tagged camera attributes and from resolution percentage.
- **GUI batch renderer** for shell-less workstations — serial frame-range disk renders from the Katana Python tab with automatic version-up, output-folder creation, and output receipts (`gui_batch_render.py`).
- **Missing-frame checker** — recursive scan of render outputs against a frame spec, emitting a paste-ready re-render list (`check_missing_frames.py`).
- **Character eye-rig OpScripts** — CEL-driven (with wildcard expansion) rig duplication and constraint targeting per character.
- **Parameter-override utilities** — selected/nested-node search-and-set and override-disable scripts for RfK global settings.
- **Scene stress-test generator** — procedural 3D grids of unique meshes with world-space dicing and procedural displacement for memory/traversal benchmarking.
- Geolib client-cook attribute dumps, scene-diff workflow, and node-graph hygiene scripts (unnamed-node finder).

## Render farm & performance diagnostics

- Led diagnosis of **farm render failures**: decoded Windows exception records (`0xC0000005` read/write/null-offset analysis), `bad allocation` vs. true OOM, and renderboot process pile-ups; established Event Viewer + `/prman/dumpstack` as the crash-triage standard.
- Separated **soft vs. hard page faults** for the render supervisor with arithmetic from prman's end-of-frame stats; prevented a misdirected memory-tuning effort.
- Characterized **texture-cache thrashing vs. compulsory misses** using controlled cap experiments (10 GB → 40 GB, no change ⇒ not thrashing) and Pixar's 25%-of-RAM guidance.
- Explained RenderMan diagnostic-report findings (scene traversal, low utilization, high system time) from raw logs, including identifying a studio Op marked `ThreadModeGlobalUnsafe` as a traversal bottleneck.
- Reviewed and corrected **pipeline conventions** with references (prune-vs-mute for per-pass lights, volume intersect priority, aggregate volumes, bucket size vs. REYES-era gridsize).
- Coordinated with **Pixar support** on a 64-thread processor-group issue, crash-trace capture options, and denoiser OpenMP thread control.

## Knowledge base

- Authored a 16-document **RenderMan/Katana knowledge base** (core, optimization, shading, lighting, AOVs/LPEs, Katana customization, USD, color, workflows, lead templates, tooling, quick reference) with session-verified gotchas, kept under version control.

## Show technical leadership (from the running to-do list — refine with title/team size/numbers)

- Owned and released the show's **lighting template and livegroups** (lighting template, prman init, global show module, global post overrides), rolling optimization updates out to the whole lighting team.
- Ran the **farm crash-investigation program**: designed the staged bisection protocol (empty → geo → textures → lights, with/without AOVs), performed Tractor job forensics across artists' failing jobs, triaged "errorless" failures, and escalated to the renderer vendor with reproducible cases.
- **Audited external optimization proposals** with per-op profiling data (Geolib op timings) and controlled tests; accepted or rejected changes on evidence (e.g. displacement-bound test across 30 assets: change smaller than noise).
- Communicated **show-wide pipeline changes** (motion-blur shutter convention: centered → forward) with clear re-render implications for every layer.
- Designed **controlled wedge tests** (min-sample ladders, glass/volume sample budgets, time-of-day variants) run on dedicated blades for like-for-like benchmarking.
- Fixed and standardized **AOV/denoise configuration** issues: interactive-render noise (Ci + LPE outputs), emissive AOV restoration, channel-list consistency, velocity-apply guard for caches without velocity.
- Daily **technical support for lighting artists** across dozens of shots: constraint targets, Pref/FX attributes, mesh-connectivity cryptomattes for window IDs, overscan tagging, light-linking vs. trace-set membership clashes, volume-pass optimization checklists.
- Cross-department coordination with pipeline/TD, lookdev, FX, comp, and production on render standards (layer conventions for glass passes, volume prunes in globals, test-environment folder structure).

## Ideas to quantify before using
- Number of shots/passes affected by the motion-vector and refracted-matte work.
- Hours saved per week by the GUI batch render + frame checker loop.
- Render-time / memory deltas from the dicing and sampling investigations.
