# PixBots-G: Master Status Document (Active Work & Backlog)

This document tracks the active implementation targets, backlog, and design expansions for PixBots-G. (All shipped and completed features have been cleared from this tracker - see the short "Recently Shipped" section at the bottom only for orientation context.)

---

## 1. Lore & Vision Context
**The Core Fantasy:** You are playing *PixBots*, a wildly popular tabletop miniatures game at Evan's local hobby shop. The scale is 20mm miniatures fighting on a 4x8ft tabletop mat (1mm = 5px, 1 inch = 127px).
**The Goal:** Survive as many waves as possible against Evan's proprietary AI Director, which evolves and breeds new rival profiles to counter your strategies.

**Story (Canon):** The shop runs a standing competition: defeat the AI and earn merchandise. The Black Market is the shop's glass case; the War Room is your opponent studying your plays.

**Standing design rulings (locked):**
- Purely procedural 2D visuals; sprite PNGs are optional *overrides*, never requirements.
- Every Champion Card PNG carries the full buildout (ghost + blueprint duality).
- Explosions are payload-only (no flight identity). Skill trees are QoL, not power.
- Corporate Sponsorships bias loot via **weights, never hard filters** - no build path can be bricked.
- Pixelbots 2 (godot-3d) shares gameplay rules via Node-free RefCounted/static classes, targeting an engine-agnostic `pixbots_core` Rust crate long-term.

---

## 2. Execution Queue (in order)

Garage QoL first (felt immediately), then small gameplay wins, then progression systems, then the big engine lift, then the feature batch.

1. **Resonator per-path configuration** - `ResonatorTile`: replace `const SYNC_DROPOFF_STEPS = 3` with per-traversal-path values (`sync_dropoff_per_path`), read in `_process_sync`; add a Resonator branch to `GarageTileConfigPopup` with +/- per path.
2. **Tile re-imaginings** (batched - all three follow the same config-popup pattern):
   - *Splitters:* Mythic ratio tuning UI (assign output percentages instead of forced equal split).
   - *Accumulators:* auto-dump threshold slider (automated burst-fire rhythms).
   - *Catalysts:* gated injection - minimum-magnitude gate AND every-X-packets cadence.
3. **Garage target dummy test range** - physical dummy mech in the garage view; select a single Weapon Mount/Emitter and test-fire it, demonstrating the real spread/range/particles from that mount's actual energy feed. (Complements, not replaces, the hover mount-preview popup.)
4. **Simulation UX** - Timeline Scrubber implemented as *deterministic re-run-to-step-N* (the sim is deterministic, so no state buffering: same UX, zero memory cost, scrubs the whole run, not a 2-3s window) + Packet Inspector panel (packet composition and last-5-packet history for each of the 6 directions on tile click).
5. **Data-driven tiles** - per-tile folder with `stats.json` (charge multipliers, damage boosts) and optional sprite PNG override; stages full custom tile mods. Procedural visuals remain the default per the locked ruling.
6. **Late-game progression** (in order):
   - *Overclocking (prestige):* at max component level, safely un-equips Mod Chips back to inventory, drops Chip Capacity until re-upgraded; grants permanent mass reduction or +1 hex.
   - *Chip Splicing:* merge two Mythic chips into one "Corrupted" dual-effect chip carrying a severe drawback from a large pool.
   - *Nemesis Bounties:* the Director breeds a boss from the player's own genetics (BossEvolution) to counter their build; drops unique inverted-synergy Nemesis Parts.
7. **Corporate Sponsorships** - post-max-level alignment with an in-universe manufacturer; biases loot via weights (see locked ruling) and adds tech constraints. **Each brand carries its own unique hex tiles** (Natalia, 2026-07-14) - design discussion with Natalia pending before implementation starts.
8. **Rust projectile physics port (Phase 3)** - the real win: eliminate per-projectile Area2D nodes entirely (Rust-side spatial hash + batched sweeps in `rust_ext`), feeding the `pixbots_core` extraction. Already landed toward this: ProjectileFlight batched flight math, `hexgrid_sim.rs` stub, and the GDScript saturation tiers (consolidation + visual LOD + popup budget) that relieve the immediate pressure.
9. **Feature batch:** Bot League auto-pilot spectating (entered via Evan's exhibition table), Tactical Puzzle Challenges (Evan's chess-style JSON scenarios, restricted parts, strict timers), Shop events (wager waves first; Shop Cat flagship later), shop-framing UI paradigm pass across all menus, Champion Card art compositing the real mech sprite.

---

## 3. Backlog & Improvements

### Bugs & Code Health
- **God-Class Aftercare:** Monitor and stabilize the `Mech.gd` split (`BossBrain`, `StatusEffectRunner`, `PlayerController`, `MagnetSystem`).
- **Spatial Hashing:** Largely superseded by `EntityCache` + the saturation tiers; the remaining need (projectile broadphase) folds into queue item 8.

### Gameplay & Balance Improvements
- **Boss Variety:** Stop scaling up Brawlers. Use role-specific bosses or genuine boss-only kits.
- **Counterplay Tells:** Audio/visual cues for Ambusher decloaks; make Heal Beacons targetable. (Director pre/post-wave intel tells already shipped.)
- **Synergy Effects:** Signature status marks per element are shipped; deepen the lingering effects for VORTEX and VAMPIRIC (bleed/immobilize interactions with corpse statues).
- **Near-peer difficulty watch:** evolution now earns premiums for player/ally damage and killing blows - watch whether it needs a counterweight (rubber-banding, bounty rewards for the player) as it sharpens.
- **Starter Inventory:** Rebalance the debug leftovers (20 Legendary Splitters) into a formal progression curve.
- **HUD & UX:** Improve HUD legibility, damage-number noise (popup budget shipped; legibility pass still open), unify menu keys. Extend Synergy Codex to cover biome interactions.

### Future Expansions
- **Expedition Map:** Slay-the-Spire style branching Tournament Bracket/Shop Campaign.
- **Pilot Skill Tree:** Earn XP for permanent QoL/utility passives across runs (QoL, not power, per ruling).
- **Deployables & Superweapons:** Proximity mines, turrets, massive multi-hex superweapons (e.g. AoE shield domes).
- **Modding (Phases 3-4):** Custom bot types and custom tile scripts extending `HexTile` (staged by queue item 6).
- **Cutscene content:** the framework is shipped and data-driven (`config/cutscenes/`) - actual story beats and real sprite PNGs are authoring work, gated on STORY_SCRIPT.md.

---

## 4. Recently Shipped (orientation only - cleared from tracking)
- Wild-bot flee thresholds: skittish roles break off and go wild (squad + wave accounting stay honest, wounds regen while loitering, director recruits them back)
- Saturation perf tiers: volley consolidation, projectile visual LOD, damage-popup budget (`d65ab79`)
- Drone sortie leash fix (1000/2000px), near-peer AI fitness premiums, Mythic boss torso hex-budget fix (`d65ab79`)
- Pixel-art cutscene framework + sample Evan beat (`6bc1b63`)
- Power-scaled jammer fields + minimap jammer secrecy swirl (`3f3df78`)
- Unlimited named save slots for builds and parts (`fa26417`)
- Earlier: Scrap Shop, captured loadouts, Lance Mount, recon/Chinook drones, lightning blink identity, mortars with true direct-fire payloads, strategic zoom, demo builds, module keybinds, obstacle corridor carving.
