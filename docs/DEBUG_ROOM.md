# Debug Room

`scripts/debug/DebugRoom.tscn` is a scriptable scenario runner for the real game. It replaces the
flag-per-experiment growth of `BenchGame` (kept for old experiments, but see the timing note below).

```
godot --path . --audio-driver Dummy res://scripts/debug/DebugRoom.tscn -- --help
godot --path . --audio-driver Dummy res://scripts/debug/DebugRoom.tscn -- \
    --wave=34 --spawn=20 --ring=500 --seconds=14 --warmup=4 --report=/tmp/run.json
```

What it does for you
- Boots `main.tscn` directly (no menu or cinematic), deploys from the Garage, skips the 5 s wave countdown.
- Forces full visuals (`--fx=full`). A killed run leaves the FxTier marker and the next run silently
  drops to "safe FX"; the room also clears the marker on a clean finish.
- Drives the player's guns itself (`--fire=auto` aims at the nearest enemy), god mode on by default.
- Spawns a crowd on a schedule (`--spawn`, `--ring`, `--spawn_rate`), missile volleys, mass kills,
  a mid-run Garage return, and a `--events="5:spawn=20;10:masskill;20:quit"` timeline.
- A/B tweaks: `--off=Node,Node`, `--noglow`, `--notrees`, `--noslide`, `--hidevis`, `--nocollide`, `--stream`.
- Reports STEADY-STATE stats (after `--warmup`) as one `ROOM_SUMMARY` JSON line, plus `--report=PATH`
  with a per-second series (fps, worst frame, enemies, projectiles, nodes, draws, physics objects/pairs).
- `--interactive`: overlay and hotkeys (F1 spawn 5 squads, F2 mass kill, F3 fire, F4 god, F5 missiles, F12 quit).

TIMING NOTE (important)
Godot clamps the `delta` it passes to `_process` to `max_physics_steps_per_frame` physics ticks (we set 3,
so 50 ms) and `physics_jitter_fix` snaps it to tick multiples. On slow frames the delta under-reports, so
any "fps" computed from `_process(delta)` saturates near 20. `BenchGame` does that. The Debug Room times
frames with `Time.get_ticks_usec()` instead. At wave 34 with ~120 enemies and several hundred projectiles
the same scene reads ~21 fps via delta and ~6-9 fps in wall-clock time. Use the Debug Room for any
before/after numbers.
