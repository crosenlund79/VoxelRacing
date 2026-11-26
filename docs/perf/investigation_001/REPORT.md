# VoxelRacing — Performance Investigation 001: Under the Hood

Investigation only. Nothing in the playable game was changed. This is
measurement and analysis, with recommendations for a future, separately
approved optimisation milestone.

## 0. What was investigated

| Item | Value |
|---|---|
| Playable branch / commit investigated | `claude/practical-gates-7ar1fn` @ `e6fc737` (Prototype 005, unchanged) |
| Diagnostic branch (this report, tools, raw data) | `claude/perf-investigation-001` (never to be merged) |
| Godot | 4.7.2-stable (official build `ed1daf0bf`) |
| Renderer (project) | Forward+ on Vulkan; fallback to D3D12, then OpenGL 3 (`gl_compatibility`) |
| Build configuration | Windows Desktop preset, release template, PCK embedded, console wrapper on, `script_export_mode=2` |
| Base resolution | 1280×720, stretch `canvas_items` / `keep` (3D renders at window size) |
| Physics | 60 ticks/s fixed; max 8 ticks per rendered frame (engine default) |
| Frame cap / VSync | no `max_fps` set; VSync at the engine default (enabled) |
| 3D quality settings | MSAA 3D 2×; directional shadow atlas 4096, soft filter 2; positional soft filter 2 |
| Race environment | Filmic tonemap, SSAO (radius 0.7, intensity 1.8), glow (soft light), colour adjustment; sun: 2-split shadows, max distance camera+70 |
| Existing performance measures found | time-sliced world build (20 ms slices), terrain in 128×128 chunks, MultiMesh for debris / effects / crowds / flowers, a 3-rebuilds-per-frame damage budget, a 9,000 debris pool, shadowless lamp-post and car lights, preview cache (12 dioramas), hidden menu viewports disabled during races |

### Execution environment (all measurements in this report)

| Item | Value |
|---|---|
| OS | Ubuntu 24.04.5 LTS, Linux 6.18 (cloud VM), Xvfb virtual display |
| CPU | Intel Xeon @ 2.30 GHz, 4 vCPU (no SMT), cloud VM |
| RAM | 16 GB |
| GPU | **none** — Mesa **lavapipe** (llvmpipe, software Vulkan 1.4) rasterises on the CPU |
| Builds | Linux **release export** of the diagnostic branch (main runs); editor binary (debug) for comparison |
| VSync / cap | uncapped, VSync off (VSync is meaningless on Xvfb) |
| Tools | own probes (`PerfProbe`), Godot `Performance` monitors, `RenderingServer` per-viewport render times, `/proc` RSS sampling, micro-timings; no GPU profiler (RenderDoc/PIX/Nsight) and no Godot editor profiler available headless |

**The single most important caveat:** this machine has no real GPU. Every
"GPU" number below is software rasterisation on the same 4 CPU cores that
run the game. Absolute frame rates here (2–7 fps) say **nothing** about a
gaming PC. What *is* reliable here: script/CPU costs per system, how often
and how hard work spikes, draw calls, triangle counts, node/resource/memory
behaviour, load-time structure, and *relative* rendering costs (which
feature costs how much compared to another). GPU-side conclusions are
marked "needs Windows verification"; a diagnostic kit for that is ready
(section 10).

## 1. Executive summary

**Overall.** VoxelRacing is in reasonable shape. A normal race costs about
**6–8 ms of game-script CPU per frame** at 60 Hz on a modest 2.3 GHz server
core (release build). That is roughly 1.7–2.2 ms of simulation per 60 Hz tick
plus about 4–6 ms of voxel presentation. Draw calls are moderate (about 335 per
frame) and render-thread submission is cheap (about 0.9–1.3 ms). Nothing
degrades over a long race. Returning to the menu releases everything.
Comfortable 60 fps on ordinary PCs looks very likely on the CPU side;
**120/144 fps on mid-range CPUs is not yet reliable**, mainly because of spikes.

**Most important bottlenecks (measured):**

1. **Damage spikes (CPU).** A single damaging hit costs about **4.8 ms** to
   pick which voxels break, plus about **4–5 ms** to re-mesh the car. An
   explosion costs about **6.3 ms**. Up to 3 re-meshes may run in one frame. In
   heavy combat the per-frame worst case reaches **20–45 ms** of script time.
   These are the game's most concerning frame-time spikes. About half of it is
   easy to remove invisibly (PERF-02).
2. **Repeated standings sorts (CPU).** About 20 full sorts of the field per
   physics tick (replay recorder, AI pit logic, achievements, HUD), at about 24
   µs each. That's about 0.45–0.55 ms per tick, roughly a quarter of the
   simulation. It's invisible to fix (PERF-01).
3. **HUD refresh (CPU).** About **1.2 ms every frame**, because the
   position tower re-applies colours and styles to every row every frame
   (PERF-04).
4. **GPU, relative (software renderer).** The 2-split sun shadow (−24% when
   off, −45% triangles), SSAO (−19%), glow (−21%), the terrain itself (−34%),
   spectators (−12%; drawn everywhere, even off-screen, and in the shadow pass)
   and meadow flowers (−12%) are the largest rendering costs. The voxel cars and
   the props are comparatively cheap. **"Voxels" as such are not the bottleneck;
   shadows, screen effects and the number of small instanced things are.**
   Needs Windows verification.

**Most concerning spikes:** damage/explosions (above), a **replay-start GPU
stall** (5–6 frames at about 4× normal GPU time), likely first-use shader
compilation, to verify on Windows. Also the **setup-screen preview rebuild**
(20–34 ms per circuit/environment change, a 1–2 frame hitch in the menu) and
a 1–1.4 ms crowd-update bump every 0.1 s.

**Long races:** **no degradation.** Settled debris costs no CPU and the debris
pool caps at 9,000 fragments. GPU cost rises once by about 10–14% as the pool
fills, then stays flat. Replay memory is bounded (30 moments). Burn marks are
the only thing that grows without a limit (about 1,200 sprites after 160 s of
forced heavy combat), with no measurable cost at that count.

**Memory:** healthy. After 4 menu→race→menu cycles the node count returns
to exactly 1,226 every time, with 0 orphan nodes. Objects and resources
plateau after the first race (caches), and video memory grows only about 4 MB
over 3 cycles. Process memory is flat during a 160-second heavy race. No leaks
were found.

**CPU-bound or GPU-bound?** Here, always GPU-bound (software renderer), so
the question can't be answered for a real PC from this environment. On the
CPU side the budget is about 6–8 ms per frame in normal racing and about
16–19 ms mean in forced heavy combat, with spikes. A real mid-range GPU at 1080p
will most likely be faster than that, which would make **heavy combat
CPU-bound** and normal racing comfortably within 60 fps. At 1440p/4K,
SSAO/glow/shadows will dominate. **Needs Windows verification.**

**Reliable findings:** all CPU costs, spike sources, draw-call/triangle
counts, relative feature costs, memory and leak behaviour, load-time
structure. **Needs real hardware:** absolute fps, real GPU frame times,
shader-compile stalls, VSync/pacing, resolution scaling on a GPU,
renderer comparisons.

## 2. Methodology

* **Harness.** `PerfBench` is an autoload that does nothing unless the game
  is started with `--bench=<scenario>`. It runs deterministic scenarios:
  fixed seed 1991, fixed circuit (Kestrel Ridge), the same environment and
  camera, and fixed warm-up and measurement windows. The player's car is driven
  by an AI driver, so every run is identical and uses the normal race camera and
  HUD.
* **Per-frame samples:** wall frame time, physics ticks in the frame, Godot
  process/physics monitors, main-viewport and all-viewport render CPU/GPU time,
  draw calls, objects, primitives, nodes, orphans, objects alive, resources,
  video/texture/buffer memory, 2D physics, and the probe timings. Process RSS
  was sampled once a second from outside.
* **Probes.** 55 timing probes wrap the per-frame and per-tick functions and
  the suspect operations (`tools/perf/apply_probes.py` inserts them
  reproducibly). They measure **wall time on the main thread**. In the
  software-rendering runs the rasteriser competes for the same cores, so
  "clean CPU" runs used **1 rasteriser thread at 320×180**.
* **Statistics:** mean, median, p95, p99, max, 1% low (mean of the slowest 1%
  of frames, as fps), stdev, and spikes (>2× median, >33 ms).
* **Repeatability:** three identical day races agreed within about 3%. 
  GPU: 238.6 / 233.5 / 232.5 ms. Sim tick: 1.88 / 1.84 / 1.86 ms.
  AI: 1.045 / 1.020 / 1.044 ms. Single runs are therefore usable for
  comparisons of more than about 5%.
* **Important artefact:** frames here take 200–300 ms, so each frame contains
  8 physics ticks. Simulation costs are reported **per tick**. Presentation
  costs are per frame, but event-driven ones (damage) collect 8 ticks' worth of
  events per frame, so their per-frame means are higher than they would be at
  60 fps. Their *per-event* costs (micro-timings) are exact.
* **Release vs debug:** the release export runs the simulation about 20%
  faster than the editor binary (1.65 vs 2.09 ms/tick) and builds the world
  15.4 s vs 18.6 s. The main runs use the release export.
* **Isolation experiments** switched one thing off at runtime (hide or stop
  processing) in the benchmark process only. Nothing in the game changed.

## 3. Baseline measurements

Software renderer: frame/GPU times are **not** representative of a gaming
PC; use them relatively. Release export; Linux; 1280×720 unless stated.
"GPU" = main-viewport render time (software rasterisation).

| Scenario | Res | Frames | Mean ms | Median | p95 | p99 | 1% low fps | Stdev | GPU ms | Render-CPU ms | Draw calls | Prims (k) | Nodes | VRAM MB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A Menu idle | 720p | 59 | 255 | 255 | 270 | 282 | 3.6 | 11 | 197 | 0.49 | 134 | 727 | 1,228 | 179 |
| B Setup idle | 720p | 32 | 322 | 324 | 342 | 351 | 2.9 | 14 | 206 | 0.50 | 148 | 782 | 1,246 | 258 |
| B Setup cycling | 720p | 62 | 321 | 321 | 358 | 384 | 2.6 | 23 | 202 | 0.45 | 149 | 772 | 1,246 | 261 |
| C Day race (run 1) | 720p | 73 | 275 | 278 | 311 | 323 | 3.1 | 22 | 239 | 0.93 | 335 | 801 | 1,634 | 210 |
| C Day race (run 2) | 720p | 75 | 268 | 263 | 324 | 358 | 2.8 | 27 | 234 | 0.86 | 336 | 800 | 1,635 | 228 |
| C Day race (run 3) | 720p | 75 | 268 | 262 | 314 | 351 | 2.9 | 27 | 233 | 0.87 | 336 | 802 | 1,634 | 210 |
| D Night race (run 1) | 720p | 70 | 289 | 282 | 359 | 386 | 2.6 | 32 | 253 | 1.25 | 340 | 807 | 1,633 | 210 |
| D Night race (run 2) | 720p | 71 | 284 | 284 | 335 | 359 | 2.8 | 25 | 248 | 1.23 | 341 | 806 | 1,633 | 210 |
| E Heavy combat (1) | 720p | 68 | 301 | 301 | 354 | 385 | 2.6 | 28 | 250 | 1.21 | 384 | 938 | 1,710 | 213 |
| E Heavy combat (2) | 720p | 69 | 296 | 293 | 345 | 427 | 2.3 | 29 | 247 | 1.19 | 384 | 939 | 1,710 | 213 |
| F Long race, window 0 (start) | 720p | 49 | 245 | 240 | 273 | 319 | 3.1 | 19 | 209 | 0.81 | 333 | 742 | 1,634 | 210 |
| F Long race, window 1 | 720p | 45 | 270 | 268 | 301 | 313 | 3.2 | 16 | 237 | 0.97 | 291 | 1,180 | 1,861 | 216 |
| F Long race, window 2 | 720p | 47 | 259 | 259 | 287 | 292 | 3.4 | 16 | 225 | 0.87 | 285 | 1,109 | 2,090 | 216 |
| F Long race, window 3 | 720p | 44 | 274 | 273 | 300 | 309 | 3.2 | 15 | 238 | 0.95 | 291 | 1,218 | 2,311 | 217 |
| F Long race, window 4 | 720p | 46 | 261 | 257 | 305 | 314 | 3.2 | 18 | 230 | 0.92 | 243 | 1,129 | 2,494 | 238 |
| H Replay playback | 720p | 475 | 282 | 272 | 330 | 1,031 | 0.9 | 101 | 253 | 0.89 | 247 | 1,083 | 2,466 | 241 |
| I Garage idle | 720p | 75 | 134 | 134 | 150 | 168 | 5.9 | 8 | 12 (workshop: own viewport) | 0.29 | 170 | 154 | 1,310 | 259 |
| I Photo mode, still | 720p | 34 | 243 | 240 | 268 | 281 | 3.6 | 14 | 235 | 0.56 | 221 | 1,067 | 1,629 | 224 |
| I Photo mode, orbiting | 720p | 45 | 224 | 225 | 248 | 250 | 4.0 | 15 | 217 | 0.54 | 174 | 883 | 1,629 | 224 |
| J Race via game flow | 720p | 71 | 213 | 212 | 241 | 267 | 3.8 | 16 | 177 | 0.96 | 337 | 447 | 2,657 | 301 |
| K Split screen (2 views) | 720p | 32 | 473 | 476 | 517 | 521 | 1.9 | 20 | 138 + views | 0.66 | 533 | 2,248 | 1,908 | 263 |
| Spectating | 720p | 63 | 241 | 241 | 276 | 294 | 3.4 | 19 | 210 | 0.90 | 357 | 797 | 1,639 | 238 |
| C, OpenGL compatibility | 720p | 59 | 257 | 247 | 320 | 370 | 2.7 | 39 | 243 | (n/a) | 434 | 808 | 1,630 | 130 |

**Resolution scaling (day race, software renderer):**

| Resolution | Pixels vs 720p | Mean frame ms | GPU ms | Draw calls | Prims (k) | VRAM MB |
|---|---|---|---|---|---|---|
| 320×180 | 0.06× | 139 | 108 | 251 | 822 | 159 |
| 1280×720 | 1× | 270 | 235 | 336 | 801 | 210 |
| 1920×1080 | 2.25× | 428 | 391 | 331 | 888 | 297 |
| 2560×1440 | 4× | 608 | 562 | 340 | 935 | 421 |
| 3840×2160 | 9× | 1,218 | 1,146 | 347 | 942 | 788 |

There is a fixed geometry part (about 100 ms here even at 320×180) plus a
part that scales with pixels (about 4.9× from 720p to 4K for 9× the pixels).
Draw calls and triangles barely change. On a real GPU the pixel-dependent part
is dominated by SSAO, glow, shadow-map sampling and the lit terrain. Video
memory scales with the render targets (210 MB at 720p → 788 MB at 4K).

**Memory (process RSS; includes the software renderer's "GPU" memory):**
menu 840–920 MB; race 1.14–1.18 GB; game-flow race (title, garage workshop
and race all loaded) 1.33 GB; split screen 1.51 GB; two loads in one process
peak 1.37 GB. Godot's static-memory counter is not available in release
builds, and true GPU memory on a real card is not available here (Godot's
`video_mem` monitor is shown instead).

**Loading (Kestrel Ridge, software renderer):**

| | Cold (first load) | Warm (second load, same process) |
|---|---|---|
| World ready | 15.9 s | 15.1 s |
| Until the grid (loading finish + 7 s intro + fades) | 32.4 s | 31.1 s |
| Sliced CPU work in the world build (clean run) | 2.0–2.4 s in 86–102 slices | (same: nothing is cached) |

## 4. Performance breakdown (CPU, measured)

**Simulation, per 60 Hz tick** (release; mean of clean runs):

| Part | ms/tick | Note |
|---|---|---|
| Whole tick (`main._physics_process`) | 1.7–2.2 | of which: |
| AI driving (10 cars) | 0.95–1.2 | about 0.24 of it is the pit logic's `position_of()` sort per car |
| Combat (weapons, AI weapon choice) | 0.45–0.65 | `_combat_states()` builds 10 dictionaries per tick (19 µs) |
| Replay recorder | 0.35–0.42 | about 0.24 of it is 10 × `position_of()` per tick |
| Track progress | 0.11–0.14 | |
| Car physics incl. collisions (10 cars) | 0.03–0.09 | the physics engine is not a cost |
| Pits / jumps / levels / debris traction / achievements | 0.02–0.05 each | |

**Presentation, per rendered frame** (clean runs, normal race):

| Part | ms/frame | Note |
|---|---|---|
| Car voxel effects (`VoxelRaceFx.sync`) | 1.8–2.3 | mostly damage: re-mesh 0.6–0.8, break 0.4, explosion 0.45 |
| Debris / sparks / smoke (`VoxelFx`) | 0.8–1.3 | only flying pieces are simulated |
| Spectators and trackside life (`VoxelLife`) | 1.2–1.6 | the people update: 1.0–1.4 ms each time it runs (10×/s) |
| HUD (`_refresh_hud`) | 1.1–1.3 | every frame |
| Stage sync (cars, camera, lights, decals) | 0.4–0.5 | |
| Lighting (night only) | 0.23–0.25 | updates hidden 2D lights |
| Audio scripts | 0.2–0.3 | dummy audio driver here: mixing not measured |
| Hidden HyperCars 2D presentation | 0.2–0.3 | |
| Tooltips | 0.01 | |

**Script CPU per 60 Hz-equivalent frame** (one tick plus one presentation
pass; raw: `raw/cpu_budget_60hz_equivalent.txt`):

| Scenario | Mean | p50 | p95 | p99 | Max |
|---|---|---|---|---|---|
| Day race (4-thread run) | 6.1 | 5.7 | 8.0 | 20.9 | 20.9 |
| Day race (clean runs, include the start pack) | 9.8–10.7 | 7.7–8.2 | 24–27 | 27–34 | 31–46 |
| Night race | 6.9 | 6.2 | 9.3 | 14.0 | 14.0 |
| Heavy combat (forced) | 18.9 | 16.0 | 38.2 | 40.7 | 45.0 |
| Long race, later windows | 6.3–7.2 | 6.0–7.0 | 9–14 | 11–20 | 11–20 |
| Replay playback | 10.2 | 7.9 | 19.0 | 33.5 | 121.9 |
| Menu / setup / garage | 0.2–0.7 | | | | ≤ 3 |

The p95+ values in races come almost entirely from damage events (section 7).

**Micro-timings (release, per call):** `standings()` 23.9 µs;
`position_of()` 23.8 µs; `_combat_states()` 18.8 µs; car re-mesh 4.08 ms
(32×12×18 voxel grid); wreck hull 4.22 ms; explosion 6.05 ms (about 276
pieces); voxel break selection about 4.8 ms per call (mean of non-zero frames);
setup preview rebuild 20–34 ms cold, 2–4 ms cached, day/night 2.4–3.9 ms.

**GPU breakdown (relative, software renderer; see section 5):** terrain
about 34%, sun shadow pass about 24% (131 of 335 draw calls, about 360k of 800k
triangles), SSAO about 19%, glow about 21%, spectators about 12%, meadow flowers about
12%, grandstands about 10%, everything else small. These overlap (for example
spectators are also in the shadow pass), so they don't add up to 100%.

## 5. System isolation results

Each experiment switched off one system in the benchmark process only; the
baseline is the mean of the three identical day runs (GPU 234.9 ms, 800k
primitives, 335 draws) or the two night runs (GPU 250.5 ms). Software-renderer
GPU deltas are **relative evidence only**; ±5% is noise.

| System | Baseline | Experiment | Difference | Interpretation | Confidence |
|---|---|---|---|---|---|
| Sun shadow (day) | 234.9 ms GPU, 335 draws, 800k prims | 179.2, 204 draws, 440k prims | **−24% GPU, −131 draws, −45% prims** | the 2-split shadow pass redraws most of the scene; biggest single rendering cost | high (relative) |
| Sun shadow (night) | 250.5 | 194.2 | **−22%** | same at night | high (relative) |
| SSAO | 234.9 | 190.2 | **−19%** | screen-space, scales with pixels | medium (needs GPU) |
| Glow | 234.9 | 185.0 | **−21%** | screen-space; probably cheaper on GPUs than on lavapipe | low–medium |
| SSAO + glow + fog + tilt-shift | 234.9 | 161.8 | **−31%** | post-processing as a whole | medium |
| Terrain hidden | 234.9 | 155.2 (−340k prims) | **−34%** | covers the screen, sampled decals, meadow tint | medium |
| Spectators hidden (rendering) | 234.9, 800k prims | 206.5, 576k | **−12%, −225k prims (−28%)** | about 666 people × 108 triangles, drawn everywhere (culling disabled) and in the shadow pass | high (counts), medium (cost) |
| Spectator updates stopped (CPU) | 1.2–1.6 ms/frame | 0 | −1.2–1.6 ms CPU | the 10 Hz per-person update | high |
| Meadow flowers | 234.9, 800k | 207.2, 536k | **−12%, −265k prims** | one MultiMesh over the whole circuit (no shadows, but no culling chunks: always fully drawn) | high (counts) |
| Grandstands | 234.9, 800k | 212.1, 713k | −10%, −88k prims | new detailed stands (expected) | medium |
| Props (track scenery) | 234.9 | 227.9 | −3% (−115k prims) | cheap | medium |
| VoxelKit set dressing | 234.9 | 227.0 | −3% | cheap | medium |
| Debris/effects (early race) | 234.9 | 227.2 | −3% | cheap while the pool is empty; +10–14% once full (long race) | medium |
| Decal viewport (tyre/burn marks) | 234.9 | 225.8 | −4% (≈0.7 ms of its own GPU time) | cheap | medium |
| HUD hidden | 335 draws, render-CPU 0.85 | 190 draws, 0.72 | **−145 draws**, −0.13 ms render CPU; HUD script unchanged | HUD is many canvas draws but cheap to submit; its script cost is the issue (PERF-04) | high |
| Replay recorder off | sim 1.88–2.24 ms/tick | 1.88 | about −0.35–0.4 ms/tick (probe) | see PERF-01 | high |
| Audio muted / stopped | — | within noise | ~0 | dummy driver here: real mixing cost unknown | low |
| Hidden HyperCars 2D presentation | 0.2–0.3 ms/frame | 0.03 | −0.2–0.3 ms CPU | legacy views still process | high |
| Hidden 2D lights (night) | 250.3 GPU, lighting 0.25 ms | 242.9, 0 | −3% GPU, −0.25 ms CPU | 2D lights still lit the decal layer | medium |
| All car lights (night) | 250.5 | 237.3 | −5% | 30 car lights, shadowless | medium |
| All point/spot lights (night) | 250.5 | 230.8 | **−8%** | 119 lights (lamp posts, cars, stands, billboards), shadowless, Forward+ clustered | medium |
| Stand/dressing lights (night) | 250.5 | 244.6 | −2% | | medium |
| Hidden menu viewports during races | 212.7 frame | 220.0 | none | logos and workshop are already disabled while hidden | high |

**Environments (day, same circuit):** Green Valley 235 ms GPU (800k prims),
Wasteland 202 (553k), Winter 201 (565k), The Raceway 211 (773k), Tabletop
Mayhem 181 (453k). Night adds about 6–9% GPU in each. **Green Valley is the most
expensive, because of the meadow flowers.** The other circuits are within ±5%
of Kestrel Ridge (Larkspur 231, Ravenhook 239).

**Day vs night:** night costs about **+6–9% GPU** and about **+0.35 ms render
CPU** (light setup), plus 0.25 ms of lighting script. The shadow pass costs
three times as much as all of the night lights together.

## 6. Voxel implementation review

* **Mesher** (`voxel_mesher.gd`): face-culled (hidden faces between voxels
  are never emitted), with per-vertex AO, per-voxel colour jitter and bevel UVs.
  It is *not* greedy, deliberately: merging faces would lose the per-voxel
  colour, AO and bevel, so greedy meshing is **not** an invisible optimisation
  (category E for the cars and terrain look).
* **Terrain:** chunked 128×128 cells, so frustum culling works. Built once per
  race and **not cached**: the same circuit is rebuilt from scratch next race
  (15.9 → 15.1 s). See PERF-12.
* **Car damage** (`voxel_car_damage.gd`): each damage step re-meshes the
  **whole** car grid (6,912 cells) in GDScript, 4.1 ms. The break selection
  re-counts the car's lamps by scanning the whole grid after every hit, and
  removes voxels with a linear search. See PERF-02 and PERF-03.
* **Instancing:** debris, effects, crowds, critters and flowers are
  MultiMeshes. Props share one mesh per kind (`VoxelProps` cache). Good.
  Crowd MultiMeshes have `extra_cull_margin = 4096`, which disables culling
  (PERF-06). Flowers are one MultiMesh for the whole circuit (PERF-07).
* **Person mesh:** 9 boxes, 108 triangles, 324 unindexed vertices, built with
  `SurfaceTool` without an index buffer. An index buffer would give the same
  look and less vertex work (PERF-06).
* **Static environment assets** are built once per race (the props cache
  persists across races). Car body meshes are cached. The preview caches 12
  dioramas.
* **Track preview:** 20–34 ms per cold rebuild on the main thread, cached
  revisits 2–4 ms (PERF-13).

## 7. Debris and destruction

| Case | Cost (measured) |
|---|---|
| Ordinary progressive damage (one hit) | voxel break selection about 4.8 ms (of which the full-grid lamp count dominates) + re-mesh about 4.1 ms the same or next frame |
| A destroyed car | explosion 6.05 ms (about 276 pieces) + wreck hull 4.22 ms |
| Several destructions at once | up to 3 re-meshes per frame (about 12 ms) + explosions (not budgeted); combat per-frame worst case 29 ms car effects alone |
| Accumulated debris (pool full, 9,000) | CPU: none for settled pieces; flying pieces 0.5–2.3 ms/frame in combat; GPU: about +440k triangles (pieces are also drawn in the shadow pass), about +10–14% (software renderer) |

* **Settled debris costs no CPU.** It sits in a spatial hash and is
  re-activated only by a passing car (`scatter_near`). Good design.
* **Rendering vs simulation:** after the pool fills, debris *rendering* is
  the larger cost (one instanced draw, but about 108k triangles per pass);
  simulation only costs while pieces fly.
* **Spawning debris** (`_spawn_bits`) is cheap (0.16 ms).
* **Traction** (`debris_traction`) is cheap: 0.02–0.03 ms/tick.
* **Cleanup and reuse:** a 9,000 ring pool; nothing grows.

## 8. Replay

* **Recording overhead:** 0.35–0.42 ms per tick, about 20% of the
  simulation tick. Most of it is the 10 standings sorts (PERF-01). Sampling
  itself (30 Hz, 13 floats per car) is cheap.
* **Memory:** a 6 s rolling buffer (181 samples) plus at most 30 captured
  moments (MAX_CAPTURES). The long race held 14 moments and 5,013 samples. An
  estimate from the data structures: a sample is 13×10 floats (520 bytes) plus
  missiles and mines, so 5,000 samples is about 3–4 MB. Bounded.
* **Playback:** the theater itself costs about 3.9 ms/frame. **The live race
  keeps running underneath at full cost** while highlights play. In the
  spectated run that was about 8.8 ms/frame of simulation (8 ticks), the AI
  driving finished cars, plus HUD 1.6 ms, crowds and effects. The race is
  already decided at that point (PERF-10).
* **Replay start:** a transient stall of 5–6 frames at about 4× normal GPU
  time, while CPU work stays normal. The likely cause is first-use shader or
  pipeline compilation for the replay camera and its own cars and effects. It
  could not be confirmed on the software renderer (PERF-11; needs Windows).
* **Cleanup:** nodes return to normal after leaving the race (transitions test).

## 9. Lighting (night)

* **Active lights:** 119 point/spot lights in the scene. These are 26 lamp
  posts, 10 cars × (headlight + tail), the stand roofs, 12 lit billboards, the
  dressing and the explosion flashes. **None cast shadows.** Only the sun/moon
  directional light does (2 splits, 4096 atlas, max distance camera+70).
* **Measured cost:** all point and spot lights together are about 8% of night
  GPU time on the software renderer. Car lights are 5% and stand/dressing
  lights 2%. The moon's shadow pass is about 22%. Render-thread light setup
  adds about 0.35 ms CPU at night.
* **Hidden 2D lighting:** the HyperCars `LightingPilot` still drives 2D
  PointLight2D head/tail lights and lens sprites every frame (0.25 ms CPU)
  that only affect the hidden 2D layer and the decal viewport (about 3% GPU).
* **Opportunities that keep the atmosphere:**
  1. Keep all the lights, but **stop small objects from casting moon/sun
     shadows**: debris pieces and possibly spectators (flowers already don't).
     The visual change is tiny shadows under tiny objects, which is barely
     visible at the race camera's distance (category B).
  2. Tune the sun's shadow distance and splits for each camera preset (B;
     slightly softer or shorter shadows far away).
  3. Retire the hidden 2D lights (A, if a visual check confirms they don't tint
     tyre and burn marks at night; otherwise B).
  4. Lamp-post and billboard ranges are already moderate. Overlap is low on
     the measured circuit.

## 10. Ranked optimisation opportunities

Effort: S (hours), M (a day or two), L (several days). "Est." = estimate,
not measured. The `ms/tick` figures apply 60 times a second whatever the frame
rate.

| ID | Cat. | System | Issue and evidence | Code | Benefit | Effort / risk | Visual / gameplay | Priority | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| **PERF-02** | A | Car damage | `break_to()` re-counts lamps over all 6,912 cells (`_count_lamps`) and removes voxels with a linear `solids.find`, about 4.8 ms per hit, on top of the re-mesh. | `voxel_car_damage.gd` `break_to`, `_count_lamps` | Measured cost: about 4.8 ms per hit. Est.: down to under 0.5 ms (incremental lamp counts, index map). | S / low | None (same voxels if the RNG use is kept) / none | **1** | high |
| **PERF-01** | A | Simulation | The field is sorted about 20× per tick: replay recorder `position_of()` ×10, AI pit `position_of()` ×10, achievements `standings()`, HUD 2–3× per frame; 24 µs each. | `replay_recorder.gd:377`, `ai_driver_input.gd:46`, `achievement_tracker.gd:85`, `main.gd _refresh_hud` | Measured: about 0.45–0.55 ms/tick. Est.: −0.4 ms/tick (about −20–25% of the simulation) with one sort per tick shared. | S / low (keep the identical order and tie-break) | None / none (same ordering) | **1** | high |
| **PERF-04** | A | HUD | The tower re-applies font colours and panel styles to all rows every frame; each override triggers a theme-change relayout. About 1.2 ms/frame, constant. | `hud.gd update_tower`, `main.gd _refresh_hud` | Measured cost 1.1–1.3 ms/frame. Est.: down to about 0.2 ms by updating only on change. | S / low | None | **1** | high |
| **PERF-05** | A | Spectators (CPU) | Every 0.1 s, 666 people × 10 cars distance checks + one `set_instance_custom_data` call per person: 1.0–1.4 ms per update, a bump every ~6th frame at 60 fps. | `voxel_life.gd _update_people` | Est.: 2–5× faster by writing the MultiMesh buffer in one call; or spread over frames (no bump). | S–M / low | None (same animation inputs) | **2** | high (cost), medium (gain) |
| **PERF-03** | A/D | Car damage | A whole-car re-mesh (4.1 ms) on every visible damage step, up to 3 per frame; explosions 6.3 ms unbudgeted; hull 4.2 ms. | `voxel_car_damage.gd rebuild/explode/hull_mesh`, `voxel_race_fx.gd _sync_car` | A: budget explosions like re-meshes, prefer one heavy operation per frame (est.: removes the 20–45 ms worst frames). D: re-mesh only the affected part, or a native (C++/C#) mesher (est.: 5–20× faster). | A: S / low. D: L / medium | A: damage may appear a frame or two later (invisible at normal speed). D: none | **2** (A), 4 (D) | high (cost) |
| **PERF-06** | A/B | Spectators (GPU) | The crowd MultiMeshes have culling disabled (`extra_cull_margin = 4096`), the person mesh has no index buffer, and spectators cast shadows: 225k triangles (28% of the frame), −12% GPU when hidden. | `voxel_life.gd _make_people`, `person_mesh` | A: split crowds per stand/segment so off-screen ones are culled, and index the mesh (est.: −30–60% of crowd vertex work on typical views). B: no spectator shadows (est.: about half of the 225k). | S–M / low | A: none. B: spectators lose their tiny shadows | **2** | medium (needs GPU) |
| **PERF-07** | A | Meadow flowers | One MultiMesh for the whole circuit (already shadowless), so all 265k triangles are drawn every frame even when most of the circuit is off-screen; −12% GPU when hidden (Green Valley is the costliest environment because of it). | `voxel_track.gd` flowers | A: split into chunks so off-screen flowers are culled (est.: most of the 265k on typical views). | S / low | None | **2** | medium |
| **PERF-08** | B/C | Sun shadow | The 2-split 4096 shadow pass redraws most of the scene: −24% GPU, −131 draws, −45% triangles when off. | `voxel_stage.gd` sun; project shadow settings | B: exclude tiny casters (debris pieces, spectators; flowers are already excluded); tune the max distance per camera preset (est.: −10–15% GPU, to verify). C: a shadow-quality setting. | S / low–medium | B: tiny shadows under tiny things; shadow distance | **3** (after Windows data) | medium |
| **PERF-09** | C | Post-processing | SSAO −19%, glow −21%, both with fog/tilt −31% (software renderer); scales with resolution. | `voxel_stage.gd make_environment` | C: SSAO / glow quality or on-off settings; 3D render scale (FSR) for 1440p/4K. | S / low | The look changes if lowered | **3** (needs GPU data) | low–medium |
| **PERF-10** | A | Replay playback | The finished race keeps simulating (AI driving finished cars, HUD, crowds, effects) underneath the highlights: about 1.5 ms/tick of simulation + about 3 ms presentation, invisible. | `main.gd` (replay state), `replay_theater.gd` | Est.: about 4–5 ms/frame less during replays. | M / medium (the live race must resume exactly) | None (the race is decided) | **3** | medium |
| **PERF-11** | A | Replay start | 5–6 frames at about 4× GPU time when the highlights start; likely first-use shader compilation. | `replay_theater.gd` | Est.: removes the hitch by pre-warming replay materials during the race intro or loading. | S–M / low | None | **2 if confirmed** on Windows | low (cause unconfirmed) |
| **PERF-12** | A/D | Loading | Every race rebuilds the voxel world (no cache: 15.9 → 15.1 s here). Only about 2–2.4 s of it is sliced CPU work; the rest is about 90–100 loading-screen frames handed back, so load time grows with frame time (slow GPU → slow load). | `voxel_track.gd build` (SLICE_USEC 20 ms), `voxel_stage.gd` | A: keep the last built world per (circuit, environment) for the next race (est.: a second race on the same track almost instant; memory: tens of MB, to measure). A: adaptive slice budget. D: build on a worker thread (the loading race stays smooth, load ≈ CPU work). | A: M / low–medium. D: L / medium | None (same world) | **2** | high (structure) |
| **PERF-13** | A | Setup preview | A cold rebuild of 20–34 ms on the main thread per circuit/environment change (1–2 frame hitch). | `circuit_preview.gd` | Est.: no hitch with a thread or pre-building neighbours. | M / low | None | 4 | high |
| **PERF-14** | A/B | Hidden 2D presentation | The HyperCars 2D lights, lenses and views still process (0.2–0.3 ms CPU; 0.25 ms + about 3% GPU at night). | `lighting_pilot.gd`, `presentation/*` | Measured: −0.3–0.55 ms CPU, −3% GPU at night. | S / low | A, if a night visual check shows no change to tyre/burn marks | 3 | high (cost) |
| **PERF-15** | A | Burn marks | One `Sprite2D` per scorch, unbounded (about 1,200 after 160 s of forced combat); no measurable cost yet. | `voxel_race_fx.gd _burn` | Est.: none now; a MultiMesh would cap the cost for very long races. | S / low | None | 5 | high |
| **PERF-16** | D | OpenGL fallback (compatibility, not speed) | Under `gl_compatibility` the game exceeds the 4,096 instance-shader-parameter limit (239 errors in one race), so some objects render with wrong parameters on PCs that fall back to OpenGL. | `set_instance_shader_parameter` in 59 places | Correctness on old GPUs (move per-instance values to MultiMesh custom data or materials). | M / medium | Fixes the fallback look | **2** (if the OpenGL fallback should be supported) | high |

**Not recommended (category E):** greedy meshing of cars and terrain (loses the
per-voxel colour, AO and bevel), lowering the debris pool or fragment counts,
removing spectators, removing persistent debris or burn marks, dropping car
lights. None of these were among the large measured costs.

## 11. Performance quick wins (all category A, small effort)

1. **PERF-02:** make the lamp count incremental and replace the linear voxel
   search in `break_to`. This removes about 4.8 ms from every damaging hit,
   the single biggest spike source.
2. **PERF-01:** sort the standings once per tick and share the result.
   About −0.4 ms per tick (20–25% of the simulation).
3. **PERF-04:** update the HUD tower only when something changed. About −1 ms
   every frame.
4. **PERF-03 (A part):** budget explosions with the re-meshes, at most one
   heavy damage operation per frame. Removes the 20–45 ms worst frames in
   pile-ups.
5. **PERF-05:** write the crowd's animation data in one buffer update. Removes
   the 10 Hz bump.

Together these remove an estimated **2–3 ms per frame in normal racing and
most of the spikes in combat** with no visible change. That is the
difference between "60 fps" and "high refresh rate" on mid-range CPUs.

## 12. Larger opportunities

* **PERF-12, loading.** Caching the built world between races (same circuit,
  same environment) would make championship repeats and "race again" nearly
  instant. A worker-thread build would make every load roughly as long as
  its CPU work (about 2–4 s on this CPU), independent of the GPU. Risks: memory
  (to measure) and thread safety in the build code.
* **PERF-03 (D), damage meshing.** Partial re-meshing, or moving the mesher
  to native code, would make destruction cost almost nothing per hit. Risk:
  effort and a second implementation of the mesher to keep identical.
* **PERF-10, replays.** Pausing the decided live race during highlights. Risk:
  resuming the post-race state exactly.
* **PERF-16, OpenGL fallback.** Needed only if old GPUs are to be supported
  properly.

## 13. Graphics settings opportunities (for later, not designed)

Supported by the measurements: shadow quality/distance, SSAO (on / quality),
glow, 3D render scale / FSR for 1440p and 4K, meadow flower density, and the
existing "dynamic vehicle lights" toggle. Spectator density is possible but not
suggested (part of the identity; and PERF-06 should come first).

## 14. Recommended optimisation sequence

1. **Collect the Windows data** (section 15). It decides whether the GPU-side
   items (PERF-06–09, 11) matter on real cards and at which resolutions.
2. **CPU quick wins:** PERF-02, PERF-01, PERF-04, PERF-03 (A), PERF-05. They
   are invisible, low-risk, independent of the hardware data, and remove most
   spikes.
3. **Rendering, category A:** PERF-06 (crowd culling and index), PERF-07
   (flower chunks), PERF-11 (pre-warm, if confirmed). Each is measured before
   and after with the same harness.
4. **Loading:** PERF-12 (world cache first, then possibly a worker thread).
5. **Category B lighting and shadow tuning** (PERF-08, PERF-14), each with
   side-by-side screenshots for approval.
6. **Category C settings** (PERF-09) only if the Windows data shows a need.
7. **Category D work** (PERF-03 D, PERF-10, PERF-16) as separate decisions.

The CPU items come first because they are certain, invisible and measured
here. The GPU items need real-hardware evidence first.

## 15. Hardware verification requirements (your Windows PC)

A diagnostic kit is built by GitHub Actions from the investigation branch
(run https://github.com/crosenlund79/VoxelRacing/actions/runs/45857292899):
the workflow "Performance diagnostic kit (NOT the playable release)", with
the artifact `VoxelRacing-PERF-DIAGNOSTIC-KIT-<sha>`. Extract it, close other
programs, run `run_benchmarks.bat` (hands off), then zip the
`results` folder and send it back (about 30 minutes, 29 runs). It collects:

* `systeminfo.txt` and `dxdiag.txt` (CPU, GPU, driver, RAM, display)
* day race at 720p / 1080p / 1440p / 2160p (resolution scaling on a real GPU)
* night race at 1080p and 1440p (lighting cost)
* 1080p with VSync, and with a 60 fps cap (frame pacing)
* heavy combat, replay (the start stall), menu, setup (preview hitches),
  garage, split screen
* Winter and Raceway at night, Tabletop by day (environment cost)
* isolations: no sun shadow, no point/spot lights, no spectators, no meadow
  flowers, no SSAO, no post-processing (whether these matter on a real GPU)
* D3D12 and OpenGL renderers (fallback cost and the instance-parameter issue)
* a race through the real game flow, the loading split (cold/warm), a long
  race, and 4 menu→race→menu cycles (memory on Windows)

Each run writes a per-frame CSV (frame time, CPU/GPU render time, draw calls,
primitives, memory, all probes) and a JSON summary. Questions it answers:
real GPU ms per frame at each resolution; whether the game is CPU- or
GPU-bound at 1080p; the actual cost of shadows, SSAO, glow and the crowd on a
real GPU; replay-start and first-race shader-compilation stalls; load time on
real hardware; frame pacing under VSync.

## 16. Investigation limitations

* **No real GPU.** Software Vulkan (lavapipe). All absolute frame rates and
  GPU times are non-representative. Relative GPU costs may differ on real
  GPUs: software rasterisers are relatively slower at fill-rate and
  screen-space effects than at geometry, so post-processing is probably
  over-weighted here and geometry under-weighted.
* **CPU contention.** The rasteriser shares the 4 cores. Clean CPU runs (1
  rasteriser thread, 320×180) mitigate this; probe values still vary ±10–15%.
* **8 ticks per frame.** Slow frames run 8 physics ticks per frame, which
  concentrates event-driven presentation work into fewer frames. Per-event
  micro-timings are exact; per-frame "60 Hz equivalents" are estimates.
* **Linux release build**, not the Windows export (same engine version and
  scripts; Windows numbers will differ somewhat).
* **No GPU profiler or Godot visual profiler.** Engine-internal costs (scene
  culling, canvas layout, audio mixing, physics server) are not broken down.
  The dummy audio driver means audio mixing was not measured.
* **Not measured:** real GPU memory (Godot's `video_mem` monitor only), VSync
  pacing, shader-cache effects on a real driver (cold and warm were identical
  here), true 4K GPU behaviour, network play.
* **Single runs** for most scenarios (variance about 3% for repeated runs);
  one replay run; the heavy combat and the long race are forced diagnostic
  loads (more destruction than a normal race).
* The long race reached race-time 160 s (lavapipe caps the accelerated
  simulation), not a full 20 laps; the debris pool was already saturated, so
  the steady state was reached.

## 17. Deliverables (in `docs/perf/investigation_001/` on the diagnostic branch)

* `REPORT.md`: this report.
* `raw/batch1`, `raw/batch2`, `raw/batch3`: per-frame CSVs, JSON summaries,
  RSS logs and run logs (all scenarios).
* `out_batch*/results.csv` and `tables.md`: one row per measured phase.
* `raw/cpu_budget_60hz_equivalent.txt`: the per-frame script CPU table.
* Tools: `src/diag/perf_bench.gd` (harness), `src/diag/perf_probe.gd`,
  `tools/perf/apply_probes.py`, `tools/perf/analyze.py`, `tools/perf/bench.sh`,
  `tools/perf/matrix.sh`, `tools/perf/matrix2.sh`,
  `tools/perf/windows/run_benchmarks.bat`,
  `.github/workflows/perf-diagnostic-kit.yml`.

The playable development branch `claude/practical-gates-7ar1fn` is
unchanged (still at `e6fc737`). All instrumentation lives only on
`claude/perf-investigation-001`, which must not be merged.
