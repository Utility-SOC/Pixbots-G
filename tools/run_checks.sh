#!/bin/bash
# Runs every headless check (scripts/debug/*Check.tscn) and prints one "Name PASS|FAIL|TIMEOUT" line each plus a summary.
# PASS = exit code 0 and no FAIL / SCRIPT ERROR / Parse Error in the output. Output goes to stdout and, if given, OUT_FILE.
#   tools/run_checks.sh [-j JOBS] [-t TIMEOUT_SECONDS] [-g GODOT] [-o OUT_FILE] [NAME_REGEX]
# Each check gets its own throwaway XDG_DATA_HOME so none can touch the real profile. A failing check is retried once (a few are
# timing/seed sensitive under parallel load); one that passes on retry is reported PASS. Checks that need a real renderer (they
# save screenshots) are reported SKIP. Exit status is the number of checks that are neither PASS nor SKIP.
JOBS=2; TMO=240; OUT=""; GODOT="$(cd "$(dirname "$0")/../.." && pwd)/Godot_v4.6.3-stable_linux.x86_64"
while getopts "j:t:g:o:" o; do case $o in j) JOBS=$OPTARG;; t) TMO=$OPTARG;; g) GODOT=$OPTARG;; o) OUT=$OPTARG;; esac; done
shift $((OPTIND-1)); FILTER="${1:-.}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
export PROJECT GODOT TMO
NEEDS_RENDERER=" CutsceneLimbsCheck RotateLimbsCheck "
export NEEDS_RENDERER
SLOW_CHECKS=" MapTypesCheck MapLayoutCheck "
export SLOW_CHECKS
run_once() { # prints PASS, FAIL or TIMEOUT
  local name="$1" home out rc tmo="$TMO"
  case " $SLOW_CHECKS " in *" $name "*) tmo=$((TMO * 3));; esac # whole-map generation checks get three times the budget
  home=$(mktemp -d); mkdir -p "$home/godot/app_userdata"
  out=$(XDG_DATA_HOME="$home" timeout "$tmo" "$GODOT" --headless --path "$PROJECT" "res://scripts/debug/$name.tscn" --quit-after 6000 2>&1); rc=$?
  rm -rf "$home"
  if [ $rc -eq 124 ]; then echo TIMEOUT
  elif [ $rc -ne 0 ] || echo "$out" | grep -q "FAIL\|SCRIPT ERROR\|Parse Error"; then echo FAIL
  else echo PASS; fi
}
run_one() {
  local name="$1" r
  case "$NEEDS_RENDERER" in *" $name "*) echo "$name SKIP"; return;; esac
  r=$(run_once "$name")
  [ "$r" != PASS ] && r=$(run_once "$name")
  echo "$name $r"
}
export -f run_once
export -f run_one
RESULT=$(ls "$PROJECT"/scripts/debug/*Check.tscn | sed 's#.*/##;s/\.tscn$//' | grep -E "$FILTER" | sort | xargs -P "$JOBS" -I{} bash -c 'run_one {}' | sort)
echo "$RESULT"
[ -n "$OUT" ] && echo "$RESULT" > "$OUT"
BAD=$(echo "$RESULT" | grep -vc " PASS$\| SKIP$")
echo "SUMMARY: $(echo "$RESULT" | grep -c " PASS$") pass, $(echo "$RESULT" | grep -c " SKIP$") skipped, $BAD not passing, $(echo "$RESULT" | grep -c .) total"
exit "$BAD"
