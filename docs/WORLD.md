# The world of PixBots (writer's bible)

One shop, one shopkeeper, one slightly too polite AI. Everything the game says should be explainable by this page.
Read alongside `docs/VOICE.md` (how each voice sounds). If a line contradicts this page, change the line.

## The place

A neighbourhood game shop, the kind with a glass counter, a slatwall of boxed games, a back room of card tables and a
vending machine that eats dollars. It sells card games, miniatures and terrain kits, and about nine years ago it started
hosting PixBots on a big felt table in the middle of the floor. Terrain lying around from a dozen other tabletop games
ends up on the table, so a castle tower next to a neon arcology is normal. Hours are not what the sign says. The shop is
closed some Wednesdays for FightShovel 1920 night.

The battlefield *is* the table. Bots are small, loud and held together with glue. "Waves" are the Corp's trainer kit
running sessions. Nothing is truly dangerous; the east wall has a lot of dents.

## People and things (the running cast, use sparingly, one at a time)

- **Frank** (the Shopkeeper). Owns the shop, nine years in. Warm, dry, tired in a good way. Lost his first twenty matches
  in a row and built something stupid on the twenty-first; it worked. Calls the player "kid" or "champ". Keeps a kettle,
  a chalkboard of kills ("getting full"), a good wrench, and a spare table.
- **The Corp.** Publisher and sponsor of the trainer table. Pays in parts and paperwork. Frank thanks them the way a shop
  thanks a publisher: gratitude with an eyebrow raised. The sponsorship board visits; logos "are visible from orbit".
- **The Trainer.** The Corp's training AI that runs the enemy squads. Polite, clinical, learns from the player. Never
  speaks warmly. Frank talks *about* it; it speaks for itself only in its own cutscenes and the orders feed.
- **The cat.** Orange, unnamed, "inventory" on the paperwork, lucky by official policy. Turns up on the field.
- **The inspector.** Routine, deadpan, always asking about animals.
- **Silas.** Sells strange, non-regulation parts out of a case. Rotation changes every ten minutes. No warranty.
- **Rudy.** A past regular; Frank does not discuss Rudy.
- **The regulars** (named rivals: Arthur, Beatrice, Grog, Leo & Luna and the rest) have their own voices. Frank
  describes them with fond exasperation.
- **Places:** the counter, the card-table room at the back, the scrap bin out back, the east wall, the vending machine,
  the Colosseum (the Corp's tournament arena, real sand).

## Ground rules

- Frank's lines never mention game systems by number, name a keybind the UI already shows, or explain a mechanic. The
  tutorial cutscenes are the one place for that.
- Past events are fixed: nine years of shop, twenty lost matches, a cat, an inspector, a bracket out front.
- Nothing grim. Stakes are social: pride, the chalkboard, the east wall, the bracket.
- Real brands and real people are out. FightShovel 1920 is ours.
- Lines stay under about 140 characters and make sense with no context (they appear mid-session as a toast).

## Intermission pools (config/dialogue.json)

- `intermission_stage.early` (waves 1-9): welcoming, small-business, first-week-of-the-hobby.
- `intermission_stage.mid` (waves 10-29): Frank is impressed and hiding it; the Corp starts paying attention.
- `intermission_stage.late` (waves 30+): the bracket, the Trainer learning, the Colosseum, the weight of it.
- `intermission_quips`: evergreen shop colour, usable at any time.
`DialogueManager.get_intermission_quip(wave)` draws 65% from the stage pool and 35% from evergreen, each through its own
shuffle bag.
