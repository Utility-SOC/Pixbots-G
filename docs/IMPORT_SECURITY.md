# Import security

Everything that arrives from outside the running game is untrusted data: save files, named loadouts,
champion cards, style cards, run cards, and clipboard AI profiles. Rules:

1. Data only. Payloads are parsed as JSON into plain dictionaries/arrays. Nothing from a payload is
   evaluated, and no resource path from a payload is passed to `load()` except through an allow-list.
2. Tile scripts: `SaveManager.is_allowed_tile_script` accepts only `res://scripts/tiles/<Name>.gd` (or
   the `HexTile` base) that actually extends `HexTile`. No `..`, no `user://`, no other directories.
3. Allow-lists and clamps: roles, plan names, map types, layouts, boss abilities/styles are checked
   against fixed lists; counts, sizes, ranks and waves are clamped; strings are truncated.
4. Size caps: JSON files, card PNGs and PNG chunks, component tile/hex counts, list lengths, drone-bay
   nesting depth.
5. Property writes from saves are type-checked against the property's current type.
6. Telemetry and the player model never travel in shared AI profiles.
7. Server responses (future leaderboard) are clamped like any other input.

Where each lives: `SaveManager` (tiles, components, saves), `ChampionCard.sanitize_payload` and the PNG
chunk reader, `GenePool`/`SquadProfileManager.parse_payload`/`BossProfile.sanitize`, `RunCard.parse`,
`LeaderboardClient.fetch`. Regression checks: `ImportSecurityCheck`, `GenePoolCheck`, `RunCardCheck`.

Not covered yet: the planned "Import Mods" feature (currently a stub) must follow these rules when built;
locally authored config JSON under `config/` is trusted.
