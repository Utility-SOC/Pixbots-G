#!/bin/bash
# Fixed-workload A/B bench (see BenchGame.gd --fixed). Compares two project trees, interleaved so machine drift hits both
# equally, and prints the median of the per-run scores (ms of engine CPU per game tick per enemy, lower is better).
#   tools/bench_fixed.sh [-n REPEATS] [-w WAVE] [-m MAP] [-t TICKS] [-s SEED] [-g GODOT] PROJECT_A [PROJECT_B]
# With one project it just reports that tree's median and spread (use it for a baseline number).
REPEATS=5; WAVE=34; MAP=Forest; TICKS=900; SEED=7
GODOT="$(dirname "$0")/../../Godot_v4.6.3-stable_linux.x86_64"
while getopts "n:w:m:t:s:g:" o; do case $o in
  n) REPEATS=$OPTARG;; w) WAVE=$OPTARG;; m) MAP=$OPTARG;; t) TICKS=$OPTARG;; s) SEED=$OPTARG;; g) GODOT=$OPTARG;; esac; done
shift $((OPTIND-1))
A=$1; B=$2
[ -z "$A" ] && { echo "usage: $0 [opts] PROJECT_A [PROJECT_B]"; exit 2; }
# The wave plan overshoots its target by a few bots and evolution state persists between runs, so the enemy count
# varies a little (80-96 at wave 34). The comparison number is therefore score PER ENEMY (ms/tick/bot), not raw score.
run() { # project -> per-enemy score (empty on a hang or crash; timeout kills it)
  timeout 600 "$GODOT" --headless --path "$1" res://scripts/debug/BenchGame.tscn -- --fixed --wave=$WAVE --map=$MAP --seed=$SEED --fixedticks=$TICKS 2>&1 \
    | grep BENCH_FIXED | head -1 | sed -E 's/.*per_enemy=([0-9.]+).*/\1/'
}
as=(); bs=()
for i in $(seq 1 $REPEATS); do
  as+=("$(run "$A")"); [ -n "$B" ] && bs+=("$(run "$B")")
  echo "run $i: A=${as[-1]}${B:+  B=${bs[-1]}}"
done
stat() { [ $# -eq 0 ] && { echo "no completed runs"; return; }; printf '%s\n' "$@" | grep . | sort -n | awk '{a[NR]=$1} END{printf "median=%.4f min=%.4f max=%.4f spread=%.1f%%", a[int((NR+1)/2)], a[1], a[NR], (a[NR]-a[1])/a[int((NR+1)/2)]*100}'; }
echo "A: $(stat "${as[@]}")"
[ -n "$B" ] && echo "B: $(stat "${bs[@]}")"
