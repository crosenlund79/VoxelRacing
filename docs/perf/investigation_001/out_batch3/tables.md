### All measured phases (lavapipe software Vulkan; GPU ms = rasterisation on the CPU)

| run | res | frames | mean ms | median | p95 | p99 | max | 1% low fps | GPU ms | render CPU ms | draws | prims (k) | objects | nodes | mem MB | VRAM MB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gl_race_day | 1280x720 | 59 | 256.78 | 246.83 | 320.21 | 370.08 | 370.08 | 2.70 | 242.81 | 243.72 | 433.58 | 808.03 | 550.14 | 1629.85 | 0.00 | 130.41 |
| gl_shot / menu_idle | 1280x720 | 4 | 304.90 | 305.83 | 306.74 | 306.74 | 306.74 | 3.26 | 263.00 | 262.59 | 274.25 | 728.01 | 351.25 | 1236.00 | 0.00 | 97.44 |
| gl_shot / menu_nav | 1280x720 | 32 | 318.08 | 316.12 | 343.18 | 356.06 | 356.06 | 2.81 | 264.47 | 264.52 | 272.66 | 726.92 | 352.47 | 1232.56 | 0.00 | 103.74 |
| replay_dbg / replay | 1280x720 | 475 | 282.05 | 271.56 | 329.54 | 1031.28 | 1169.31 | 0.93 | 252.61 | 0.89 | 246.57 | 1083.13 | 404.38 | 2465.91 | 0.00 | 240.57 |
| shader_cold | 1280x720 | 40 | 256.68 | 256.83 | 278.85 | 290.11 | 290.11 | 3.45 | 225.03 | 0.81 | 324.30 | 837.41 | 544.98 | 1629.08 | 0.00 | 209.91 |
| shader_warm | 1280x720 | 40 | 254.55 | 250.93 | 286.78 | 286.95 | 286.95 | 3.48 | 225.14 | 0.79 | 323.18 | 830.21 | 542.95 | 1629.05 | 0.00 | 209.91 |


### Simulation CPU per 60 Hz tick (ms, release export)

| run | ticks/frame | main_tick | ai_drive | combat | replay_record | progress | car_physics | pits | jumps | debris_traction | levels |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gl_race_day / race | 8.00 | 1.64 | 0.94 | 0.45 | 0.39 | 0.11 | 0.04 | 0.04 | 0.03 | 0.02 | 0.02 |
| gl_shot / menu_idle | 8.00 | - | - | - | - | - | - | - | - | - | - |
| gl_shot / menu_nav | 8.00 | - | - | - | - | - | - | - | - | - | - |
| replay_dbg / replay | 8.00 | 1.10 | 0.77 | 0.05 | 0.01 | 0.10 | 0.11 | 0.03 | 0.03 | 0.01 | 0.02 |
| shader_cold / race | 8.00 | 1.75 | 1.01 | 0.46 | 0.28 | 0.12 | 0.05 | 0.05 | 0.03 | 0.02 | 0.02 |
| shader_warm / race | 8.00 | 1.63 | 0.94 | 0.43 | 0.26 | 0.11 | 0.05 | 0.04 | 0.03 | 0.02 | 0.02 |


### Presentation CPU per rendered frame (ms, release export)

| run | pres.stage_total | pres.stage_cars | pres.race_fx | pres.voxel_fx | pres.debris_step | pres.life | pres.life_people | pres.main_process | ui.hud | pres.lighting | pres.replay_theater | pres.photo_mode | pres.car_remesh | pres.car_break |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gl_race_day / race | 0.85 | 0.39 | 0.35 | 0.25 | 0.02 | 1.07 | 0.90 | 1.14 | 1.09 | 0.00 | 0.00 | 0.00 | 0.10 | - |
| gl_shot / menu_idle | - | - | - | 0.13 | 0.01 | - | - | - | - | - | - | - | - | - |
| gl_shot / menu_nav | - | - | - | 0.13 | 0.01 | - | - | - | - | - | - | - | - | - |
| replay_dbg / replay | 0.23 | 0.02 | 0.09 | 2.07 | 0.93 | 0.94 | 0.75 | 1.60 | 1.56 | 0.00 | 3.88 | 0.00 | 0.99 | 1.11 |
| shader_cold / race | 0.71 | 0.40 | 0.21 | 0.38 | 0.00 | 1.21 | 1.01 | 1.16 | 1.11 | 0.00 | 0.00 | 0.00 | - | - |
| shader_warm / race | 0.63 | 0.39 | 0.15 | 0.33 | 0.00 | 1.17 | 0.98 | 1.14 | 1.09 | 0.00 | 0.00 | 0.00 | - | - |

