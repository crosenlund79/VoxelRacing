#!/bin/bash
# The Performance Investigation 001 benchmark matrix (release export, lavapipe).
S=/tmp/claude-0/-home-user-VoxelRacing/3d7bab0a-2953-55c6-9396-31b60e31efa5/scratchpad
B=/home/user/VoxelRacing/build/linux_diag/VoxelRacingDiag.x86_64
O=$S/perf/raw
mkdir -p $O
run() { # tag res args...
  local tag=$1 res=$2; shift 2
  if [ -f $O/${tag}_summary.json ]; then echo "skip $tag"; return; fi
  echo "=== $tag $res $* ($(date +%T))"
  TIMEOUT=${T:-600} $S/bench.sh $B $res -- --out=$O --tag=$tag "$@" | grep -E "ready in|wrote|SCRIPT|TIMEOUT|world|global"
}
run race_day_1 1280x720 --bench=race --secs=20 --warm=4
run race_day_2 1280x720 --bench=race --secs=20 --warm=4
run race_day_3 1280x720 --bench=race --secs=20 --warm=4
run race_night_1 1280x720 --bench=race --night=1 --secs=20 --warm=4
run race_night_2 1280x720 --bench=race --night=1 --secs=20 --warm=4
for r in 320x180 1920x1080 2560x1440 3840x2160; do run res_day_$r $r --bench=race --secs=15 --warm=4; done
run res_night_1920x1080 1920x1080 --bench=race --night=1 --secs=15 --warm=4
for i in no_omni_spot no_car_lights no_shadows no_dir_shadow no_life_lights; do run iso_night_$i 1280x720 --bench=race --night=1 --secs=15 --warm=4 --iso=$i; done
for i in no_people no_dressing no_life_process no_dir_shadow no_props no_stands no_fx no_decals no_ssao no_glow no_post no_recorder no_audio no_hud no_legacy2d no_terrain no_flowers_grass; do run iso_day_$i 1280x720 --bench=race --secs=15 --warm=4 --iso=$i; done
for v in 2 3 4 5; do run env_v${v}_day 1280x720 --bench=race --variant=$v --secs=15 --warm=4; done
for v in 3 4; do run env_v${v}_night 1280x720 --bench=race --variant=$v --night=1 --secs=15 --warm=4; done
for l in larkspur_ring ravenhook; do run layout_$l 1280x720 --bench=race --layout=$l --secs=15 --warm=4; done
run spectate_day 1280x720 --bench=race --spectate=1 --secs=15 --warm=4
run combat_1 1280x720 --bench=combat --secs=20
run combat_2 1280x720 --bench=combat --secs=20
run replay_1 1280x720 --bench=replay
run menu_1 1280x720 --bench=menu --secs=15 --warm=5
run setup_1 1280x720 --bench=setup --warm=5
run garage_1 1280x720 --bench=garage --warm=5
run photo_1 1280x720 --bench=photo
run split_1 1280x720 --bench=split --secs=15 --warm=4
run load_1 1280x720 --bench=load
T=1800 run long_1 1280x720 --bench=long --secs=12 --windows=5 --gap=45
T=1800 run transitions_1 1280x720 --bench=transitions --cycles=4
echo "MATRIX DONE $(date +%T)"
