# Pixbots-G Modding Guide (Phase 1)

This documents what is *actually moddable today* — the JSON formats the game
already loads. It replaces the old `mod_guide_text.txt` (which was scraped
content from an unrelated game and has been deleted). For the longer-term
modding plan (data-driven tile stats, custom bot types, texture overrides,
script-registered tiles), see the Modding section of `FEATURE_ROADMAP.md`.

## Where files live

| Location | Purpose |
|---|---|
| `user://ai_profiles/*.json` | Player-local AI profiles: saved learning state, imported/shared profiles. Writable at runtime. |
| `res://config/*.json` | Shipped/modded profile packs. Read-only fallback: `SquadProfileManager.load_profile("name")` checks `user://ai_profiles/name.json` first, then `res://config/name.json`. |

On Windows, `user://` is `%APPDATA%/Godot/app_userdata/Pixbots-G/`.

## AI profile format

One file carries both halves of the AI's learning: squad compositions
(`templates`) and loadout-building preferences (`solver_profiles`). Both
keys are optional — old files with only `templates` still load.

```json
{
	"profile_name": "my_mod_pack",
	"version": "1.1",
	"templates": [
		{
			"template_name": "P3X-774",
			"required_roles": {"sniper": 2, "brawler": 1},
			"spawn_weight": 100.0,
			"base_spawn_weight": 100.0,
			"times_deployed": 0,
			"total_fitness": 0.0,
			"is_experimental": false
		}
	],
	"solver_profiles": [
		{
			"profile_name": "K9M-041",
			"favored_synergy": 3,
			"pierce_priority": 0.4,
			"amplify_priority": 1.0,
			"is_experimental": false,
			"spawn_weight": 100.0,
			"base_spawn_weight": 100.0,
			"times_used": 0,
			"total_fitness": 0.0
		}
	]
}
```

### Template fields

- `template_name` — display name (the game generates Stargate-style designations like `P3X-774` for evolved squads; mods can use any string).
- `required_roles` — role name → count. Valid roles: `sniper`, `brawler`, `flamethrower`, `ambusher`, `scout`, `jammer`, `support` (see `SquadTemplateMutator.ALL_ROLES`).
- `spawn_weight` / `base_spawn_weight` — weighted-random selection weight; 100 is baseline. Weight learns toward `base_spawn_weight * fitness/100`, clamped 10–1000.
- `times_deployed` / `total_fitness` — learning history; ship 0 for fresh templates.
- `is_experimental` — `true` puts the template on trial: it gets culled if average fitness < 60 after 3 deployments, and graduates to permanent at ≥ 110.
- `has_shields` — optional bool; squad members spawn with shields.

### Solver profile fields

- `favored_synergy` — index into `EnergyPacket.SynergyType`: 0 RAW, 1 FIRE, 2 ICE, 3 LIGHTNING, 4 VORTEX, 5 POISON, 6 EXPLOSION, 7 KINETIC, 8 PIERCE, 9 VAMPIRIC. Use `-1` for no preference.
- `pierce_priority` / `amplify_priority` — relative weights when the auto-equip solver chooses between Pierce-flavored and Amplify-flavored placements. Only the ratio matters.
- Remaining fields mirror the template learning fields.

## Learned state & sharing

- The game persists its own learning to `user://ai_profiles/learned_state.json` after every squad defeat — same format as above. Deleting it resets the AI's memory.
- **Export/Import:** the War Room (TAB in-game) has clipboard export/import buttons. The clipboard payload is the same JSON (just without the outer `profile_name`). This is how two players swap trained AIs.
- Imports merge by name: known templates/profiles get their stats updated in place, unknown ones are added.

## Baseline squad pack

`res://config/default_squads.json` is a live modding surface: it's loaded
by `SquadDirector.load_learned_state()` at the start of a run and merged
(by `template_name`) with the in-code defaults, *before* any saved learning
applies on top. Edit it to add or reweight baseline squad compositions
without touching code. To override it per-player instead of per-install,
drop a `default_squads.json` into `user://ai_profiles/` — the user copy
wins. Its role names use the current role set (see valid roles above).
