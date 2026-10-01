# Daily seed and run cards

## Daily seed

The daily run needs no server. `RunCard.daily_params(date)` derives everything from the UTC date
(`YYYY-MM-DD`): a SHA-256 of `pixbots-daily-<date>` gives the 31-bit seed, and a RNG seeded with
it picks the map type (from `DAILY_MAP_TYPES`) and the map layout (`MapGenerator.LAYOUTS`). Two
players on the same day get the same terrain. `MapGenerator.map_seed` makes generation
deterministic; wave composition is not yet seeded.

Start it from **Main Menu > Daily Run**. Your best wave per date is kept in `user://meta_progress.json`.

## Run cards

A run card is a PNG with an iTXt chunk (`pixbots.runcard`, format `pixbots-runcard-v1`) holding:

```json
{"format": "pixbots-runcard-v1", "mode": "daily|custom", "date": "2026-09-30", "seed": 123,
 "map_type": "Forest", "layout": "river", "pilot": "name",
 "genes": {},   // optional frozen AI snapshot (GenePool export, sanitized on import)
 "result": {"wave": 12, "seconds": 900, "kills": 88}}   // optional
```

Cards are written to and listed from `user://run_cards/`. The image is a deterministic badge from the
seed (`RunCard.render_badge`); `RunCard.render_preview(map)` can render a terrain thumbnail instead.

### Safety

Card contents are untrusted data. `RunCard.parse` allow-lists `mode`, `map_type` and `layout`,
checks the date format and seed range, clamps result numbers and truncates strings. A daily card
must match what its date produces (`matches_daily`), so a hand-edited card can't claim today's seed
with a different map. Embedded genes are only passed to the normal sanitizing gene import. Nothing is
loaded or evaluated from a card. The PNG reader bounds-checks chunk lengths and caps chunk size.

## Leaderboard (stub)

`LeaderboardClient` defines the interface and ships a `NullBackend` ("no server configured"). To add
a server, implement a backend with:

- `submit(card) -> {"ok": bool, "rank": int?, "reason": String?}`
- `fetch(date, limit) -> {"ok": bool, "entries": [{"pilot", "wave", "seconds", "kills"}], "reason": String?}`

and assign it to `LeaderboardClient.backend`. `submit` only forwards finished cards that pass
`RunCard.parse` and `matches_daily`; `fetch` clamps and truncates whatever a server returns. The seed
never depends on the server.
