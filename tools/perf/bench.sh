#!/bin/bash
# usage: bench.sh <binary|editor> <res WxH> -- <bench args...>
# Runs VoxelRacing (editor binary on the project, or an exported binary) under
# Xvfb + lavapipe (software Vulkan) with the PerfBench autoload; logs the
# process RSS once a second to <out>/<tag>_rss.csv.
export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json GALLIVM_PERF=no_aos_sampling LP_PERF=no_rast_linear
BIN=$1; RES=$2; shift 2
OUTD=""; TAG=""
for a in "$@"; do case $a in --out=*) OUTD=${a#--out=};; --tag=*) TAG=${a#--tag=};; esac; done
cd /home/user/VoxelRacing
if [ "$BIN" = "editor" ]; then
  CMD="$HOME/godot/godot --path /home/user/VoxelRacing"; PAT="godot/godot --path"
else
  CMD="$BIN"; PAT="$(basename $BIN)"; cd /tmp/claude-0/-home-user-VoxelRacing/3d7bab0a-2953-55c6-9396-31b60e31efa5/scratchpad
fi
( sleep 2; P=$(pgrep -n -f "$PAT"); [ -n "$OUTD" ] && echo "t,rss_mb" > $OUTD/${TAG}_rss.csv; T0=$(date +%s.%N)
  while [ -n "$P" ] && kill -0 $P 2>/dev/null; do R=$(ps -o rss= -p $P 2>/dev/null); [ -n "$R" ] && [ -n "$OUTD" ] && echo "$(echo "$(date +%s.%N) - $T0" | bc),$(echo "$R/1024" | bc)" >> $OUTD/${TAG}_rss.csv; sleep 1; done ) &
timeout ${TIMEOUT:-900} xvfb-run -a -s "-screen 0 3840x2160x24" $CMD --rendering-method ${RM:-forward_plus} --rendering-driver ${RD:-vulkan} --resolution $RES "$@" 2>&1 | grep --line-buffered -E "BENCH|SCRIPT ERROR|Parse Error|ERROR:" | grep -v "leaked\|resources still in use"
wait
