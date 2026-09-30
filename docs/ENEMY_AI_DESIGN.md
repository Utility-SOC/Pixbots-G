# Enemy AI: how enemies get harder

Goal: the game keeps escalating whatever the player does, until the player changes playstyle. Difficulty comes from
smarter builds and smarter tactics, not bigger numbers or a race to Mythic.

## Layers

| Layer | File | What it decides |
|---|---|---|
| Fitness normalisation | `scripts/ai/FitnessPar.gd` | Scores are relative to a moving par per bucket (`role:rarity`, `squad:wave-band`, `boss:wave-band`). 100 = typical. Higher tier or later wave never scores higher just for existing. |
| Loadouts | `StockBuildEvolution.gd`, `StockBuildMutator.gd` | Champion build per `template:role:rarity:slot`; deviation tests must beat the champion's recent average by a margin to be promoted. |
| Tier gating | `SquadDirector.RARITY_UNLOCK_WAVES`, `ROLE_UNLOCK_DELAY` | Rarer components unlock for enemies by wave (per role), so progress is quality at the current tier. |
| Player model | `PlayerModel.gd` | Recent (fast decay) vs slow memory of damage/kill elements. A large divergence = the player changed playstyle: old counters are retired and pressure eases. |
| Pressure | `PlayerModel.pressure` (0..4) | Ratchets up when the player is barely scratched. Feeds exploration rate, counter-commit chance, and tactic complexity/lead skill. Never raw stats or tier. |
| Squad tactics | `SquadTactics.gd` | Per-squad plan (below), planning tick at 4 Hz. |

## Squad tactics

A plan assigns each member a part (`FLANK`, `PIN`, `COVER`, `BAIT`, `RING`, `STAGE`; shown in the enemy state tag) and
steers it toward goal points around the player. Plans are wave-gated:
`swarm` (0), `synchronized_strike` (3), `pincer` (5), `hammer_anvil` (8), `encircle` (12), `bait_flank` (15).

- Selection is weighted: recent plans are damped (variety), plans that score well against this player are favoured,
  pressure shifts weight away from plain `swarm`, and a pressure-scaled exploration roll picks uniformly.
- A plan that lands no hits for 12 s, or a squad being ground down, triggers a replan to a different plan.
- Shots lead the player's motion. Lead skill scales with pressure (0.3 to 1.0) and shrinks against players who jink.
- Per-plan outcomes are stored (`tactic_stats` in learned state) and credited with the squad's normalised fitness.

Next: a tactic genome (plan parameters mutated and culled like build profiles) and player movement-habit modelling.

Checks: `scripts/debug/SquadTacticsCheck.tscn`, `StockBuildCreditCheck.tscn`.
