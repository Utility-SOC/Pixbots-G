#!/bin/bash
# Runs every headless check (scripts/debug/*Check.tscn) and prints one "Name PASS|FAIL|TIMEOUT" line each plus a summary.
# PASS = exit code 0 and no FAIL / SCRIPT ERROR / Parse Error in the output. Output goes to stdout and, if given, OUT_FILE.
#   tools/run_checks.sh [-j JOBS] [-t TIMEOUT_SECONDS] [-g GODOT] [-o OUT_FILE] [NAME_REGEX]
# Each check gets its own throwaway XDG_DATA_HOME so none can touch the real profile. Exit status is the number of non-PASS checks.
JOBS=2; TMO=240; OUT=""; GODOT="$(cd "$(dirname "$0")/../.." && pwd)/Godot_v4.6.3-stable_linux.x86_64"
while getopts "j:t:g:o:" o; do case $o in j) JOBS=$OPTARG;; t) TMO=$OPTARG;; g) GODOT=$OPTARG;; o) OUT=$OPTARG;; esac; done
shift $((OPTIND-1)); FILTER="${1:-.}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
export PROJECT GODOT TMO
run_one() {
  local name="$1" home out rc
  home=$(mktemp -d); mkdir -p "$home/godot/app_userdata"
  out=$(XDG_DATA_HOME="$home" timeout "$TMO" "$GODOT" --headless --path "$PROJECT" "res://scripts/debug/$name.tscn" --quit-after 6000 2>&1); rc=$?
  rm -rf "$home"
  if [ $rc -eq 124 ]; then echo "$name TIMEOUT"
  elif [ $rc -ne 0 ] || echo "$out" | grep -q "FAIL\|SCRIPT ERROR\|Parse Error"; then echo "$name FAIL"
  else echo "$name PASS"; fi
}
export -f run_one
RESULT=$(ls "$PROJECT"/scripts/debug/*Check.tscn | sed 's#.*/##;s/\.tscn$//' | grep -E "$FILTER" | sort | xargs -P "$JOBS" -I{} bash -c 'run_one {}' | sort)
echo "$RESULT"
[ -n "$OUT" ] && echo "$RESULT" > "$OUT"
BAD=$(echo "$RESULT" | grep -vc " PASS$")
echo "SUMMARY: $(echo "$RESULT" | grep -c " PASS$") pass, $BAD not passing, $(echo "$RESULT" | grep -c .) total"
exit "$BAD"
