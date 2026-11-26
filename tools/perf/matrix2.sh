#!/bin/bash
# Batch 2: clean CPU runs (rasteriser on 1 thread, tiny window), micro-timings,
# game-flow race with off-screen viewports, 2D lights, loading split, long race classes.
S=/tmp/claude-0/-home-user-VoxelRacing/3d7bab0a-2953-55c6-9396-31b60e31efa5/scratchpad
B=/home/user/VoxelRacing/build/linux_diag/VoxelRacingDiag.x86_64
O=$S/perf/raw2
mkdir -p $O
run() { local tag=$1 res=$2; shift 2
  if [ -f $O/${tag}_summary.json ]; then echo "skip $tag"; return; fi
  echo "=== $tag $res $* ($(date +%T))"
  TIMEOUT=${T:-900} $S/bench.sh $B $res -- --out=$O --tag=$tag "$@" | grep -E "ready in|wrote|SCRIPT|TIMEOUT|world|global|micro|viewports:|disabled|diag"
}
export LP_NUM_THREADS=1
run cpu_race_day_1 320x180 --bench=race --secs=25 --warm=4 --micro=1
run cpu_race_day_2 320x180 --bench=race --secs=25 --warm=4
run cpu_race_night 320x180 --bench=race --night=1 --secs=25 --warm=4
run cpu_race_night_no2d 320x180 --bench=race --night=1 --secs=25 --warm=4 --iso=no_2d_lights
run cpu_race_no_life 320x180 --bench=race --secs=25 --warm=4 --iso=no_life_process
run cpu_race_no_legacy 320x180 --bench=race --secs=25 --warm=4 --iso=no_legacy2d
run cpu_race_no_recorder 320x180 --bench=race --secs=25 --warm=4 --iso=no_recorder
run cpu_combat_1 320x180 --bench=combat --secs=25
run cpu_load 320x180 --bench=load
run cpu_menu 320x180 --bench=menu --secs=15 --warm=5
run cpu_setup 320x180 --bench=setup --warm=5
T=1800 run cpu_long 320x180 --bench=long --secs=12 --windows=4 --gap=60
unset LP_NUM_THREADS
run gamerace_720 1280x720 --bench=gamerace --secs=15 --warm=4
run gamerace_720_nohidden 1280x720 --bench=gamerace --secs=15 --warm=4 --iso=no_hidden_vps
run night_no2d_720 1280x720 --bench=race --night=1 --secs=15 --warm=4 --iso=no_2d_lights
run night_base_720 1280x720 --bench=race --night=1 --secs=15 --warm=4
run replay_spec_720 1280x720 --bench=replay
run garage_720 1280x720 --bench=garage --warm=5
run menu_720 1280x720 --bench=menu --secs=15 --warm=5
run split_720 1280x720 --bench=split --secs=15 --warm=4
run race_day_720_allvp 1280x720 --bench=race --secs=15 --warm=4
echo "MATRIX2 DONE $(date +%T)"
