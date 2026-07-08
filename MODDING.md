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
	"version": "1.3",
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
- `required_roles` — role name → count. Valid roles: `sniper`, `brawler`, `flamethrower`, `ambusher`, `scout`, `jammer`, `support`, `commander` (see `SquadTemplateMutator.ALL_ROLES`; the game also spawns special roles like `diver` internally).
- `spawn_weight` / `base_spawn_weight` — weighted-random selection weight; 100 is baseline. Weight learns toward `base_spawn_weight * fitness/100`, clamped 10–1000.
- `times_deployed` / `total_fitness` — learning history; ship 0 for fresh templates.
- `is_experimental` — `true` puts the template on trial: it gets culled if average fitness < 60 after 3 deployments, and graduates to permanent at ≥ 110.
- `has_shields` — optional bool; squad members spawn with shields.

### Solver profile fields

- `favored_synergy` — index into `EnergyPacket.SynergyType`: 0 RAW, 1 FIRE, 2 ICE, 3 LIGHTNING, 4 VORTEX, 5 POISON, 6 EXPLOSION, 7 KINETIC, 8 PIERCE, 9 VAMPIRIC. Use `-1` for no preference.
- `pierce_priority` / `amplify_priority` — relative weights when the auto-equip solver chooses between Pierce-flavored and Amplify-flavored placements. Only the ratio matters.
- Remaining fields mirror the template learning fields.

### Boss profiles (format v1.2+)

A third optional key, `boss_profiles`, carries evolvable boss kits:

```json
	"boss_profiles": [
		{
			"profile_name": "R4K-201",
			"base_role": "brawler",
			"ability_pool": ["shockwave", "blink_strike"],
			"enrage_style": "berserker",
			"position_style": "aggressive",
			"hp_mult": 1.0,
			"is_experimental": false,
			"spawn_weight": 100.0,
			"base_spawn_weight": 100.0,
			"parent_name": "",
			"times_used": 0,
			"total_fitness": 0.0,
			"fitness_history": []
		}
	]
```

Valid abilities: `shockwave`, `railgun`, `blink_strike`, `fire_pool`,
`jam_burst`, `rally`. Enrage styles: `berserker`, `juggernaut`, `vampiric`,
`unstable`. Position styles: `aggressive`, `kiter`, `circler`. Base roles:
`brawler`, `sniper`, `ambusher`, `flamethrower`, `jammer`, `commander`.
(See `BossProfile.gd` for the authoritative lists.)

### Telemetry (format v1.3, learned_state only)

`learned_state.json` also carries a `"telemetry"` dict (the director's
observed player element usage and kill methods) so the counter-doctrine
remembers you between sessions. It is intentionally **excluded from
clipboard export/import** — sharing your combat history would poison a
friend's director with the wrong player's habits. Delete the key (or the
whole file) to reset the AI's memory of your playstyle.

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
