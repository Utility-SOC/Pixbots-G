# Pixbots-G Docs Index

Design/roadmap/handoff documents, split back out of a scratch monolith
(`exStatus.md`) that had accidentally concatenated them together. Each
entry below is a pointer, not a summary — open the linked doc for the
real content.

- **[CLAUDE_CODE_HANDOFF.md](CLAUDE_CODE_HANDOFF.md)** — state-of-the-world
  handoff notes for picking up this project cold in a new session. Read
  first if you're orienting after a gap; treat it as a starting map, not
  ground truth (verify against actual code, it says so itself).
- **[AAA_VISION_AND_PERFORMANCE_ROADMAP.md](AAA_VISION_AND_PERFORMANCE_ROADMAP.md)**
  — the "5 Pillars of Feels AAA" aesthetic pillars (audio tactility,
  lighting/diorama, camera juice, diegetic UI, metagame loop), a
  full performance-hotspot audit, a 3D MechWarrior-horizon analysis
  (hex-grid → voxel volume translation), and the master implementation
  roadmap with phase checkboxes. Read when doing visual/perf/3D-roadmap
  work.
- **[PROJECTILE_ARCHITECTURE_ROADMAP.md](PROJECTILE_ARCHITECTURE_ROADMAP.md)**
  — the plan for the no-Node-tree `ProjectileBatchPool` rewrite (ground
  rules, phased plan, non-goals, open questions). Read before touching
  `ProjectileBatchPool.gd` or deciding whether/when it replaces the
  live per-Node projectile system.
- **[STORY_SCRIPT.md](STORY_SCRIPT.md)** — Frank's (the shop owner NPC)
  voice, dialogue, and the game's narrative/tone bible, including the
  slow-burn "something's off outside" background thread. Read before
  writing any player-facing flavor text, quips, or NPC dialogue.
- **[MODDING.md](MODDING.md)** — what's actually moddable today: the real
  JSON formats the game loads. Read before changing save/load formats
  or documenting modding support.
- **[playtest_protocol.md](playtest_protocol.md)** — a snapshot playtest
  checklist from a specific efficiency-audit pass, including debug-menu
  shortcuts for skipping grind while testing. Useful as a reference for
  what debug-menu shortcuts exist; the specific pass it describes is
  historical.
- **[DISCLOSURES.md](DISCLOSURES.md)** — third-party license disclosures
  (Godot, godot-rust, Python tooling, Rust crate tree). Read before
  shipping/publishing, or when adding a new third-party dependency.
- **[PIXELBOTS_2_HEX_TO_CUBE_MAPPING.md](PIXELBOTS_2_HEX_TO_CUBE_MAPPING.md)**
  — design proposal for how the 2D hex grid maps into 3D cube volumes for
  Pixelbots 2 (documentation only, no PB1 code implied). Read alongside
  `Status.md`'s "1a. Pixelbots 2" section before any future 3D/PB2 work.
