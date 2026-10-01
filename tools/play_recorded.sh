#!/bin/bash
# Play Pixbots with the flight recorder + console capture (+ optional desktop shots).
#   tools/play_recorded.sh [--desktop[=SECONDS]] [--silent] [-- extra game args]
# Output folder: ~/pixbots_session_<timestamp>/  (console.log, desktop_*.png)
# In-game recorder output (events, screenshots, state dumps) goes to the Godot
# user dir: ~/.local/share/godot/app_userdata/Pixbots-G/flight/
# GODOT=/path/to/godot overrides the binary.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(ls "$HERE"/../tc/Godot_v4.6.3-stable_linux.x86_64 2>/dev/null || command -v godot)}"
DESKTOP=0; INTERVAL=30; SILENT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --desktop) DESKTOP=1 ;;
    --desktop=*) DESKTOP=1; INTERVAL="${1#*=}" ;;
    --silent) SILENT=1 ;;
    --) shift; break ;;
    *) break ;;
  esac; shift
done
OUT="$HOME/pixbots_session_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$OUT"
echo "Session folder: $OUT"
if [ "$DESKTOP" = 1 ]; then
  ( n=0; while true; do n=$((n+1)); import -window root "$OUT/desktop_$(printf %04d $n).png" 2>/dev/null
    ls -1t "$OUT"/desktop_*.png 2>/dev/null | tail -n +61 | xargs -r rm -f; sleep "$INTERVAL"; done ) &
  SHOTPID=$!; trap 'kill $SHOTPID 2>/dev/null' EXIT
  echo "Desktop screenshots every ${INTERVAL}s (this captures your WHOLE screen)."
fi
EXTRA=(); [ "$SILENT" = 1 ] && EXTRA=(--audio-driver Dummy)
"$GODOT" "${EXTRA[@]}" --path "$HERE" "$@" 2>&1 | tee "$OUT/console.log"
