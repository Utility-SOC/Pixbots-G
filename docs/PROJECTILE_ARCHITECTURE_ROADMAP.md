# Projectile Architecture Rewrite — Roadmap

Started 2026-08-07. User's framing: "the tree seems to be fucking us."
Target: real progress by Monday, not a one-night rewrite. This document is
the plan — read it before picking this back up, verify against the actual
code (things may have moved), and update it as phases land or the plan
changes.

## The problem, in one paragraph

Every projectile in the game is a real Godot `Node2D` — `add_child`/
`remove_child`, canvas-item registration, group membership, per-instance
`_process`/`_physics_process` dispatch. That's real engine-level overhead
that exists **per node**, completely separate from the actual simulation
math, which is already batched in Rust (`ProjectileFlight`,
`ProjectileBroadphaseRs` — see `rust_ext/src/`). A live playtest at wave
138 confirmed the remaining hotspots (`shoot_fired`, `projectile_physics`)
scale with live shot count in a way that tracks node/tree bookkeeping, not
just simulation cost. The fix isn't more caching inside the existing
per-Node model — it's not having a Node per shot at all.

## Ground rules (do not violate without asking)

1. **Parallel system, opt-in only, until approved through actual gameplay
   testing.** Never silently cut live combat over to the new path.
   `GarageTestRange.gd`'s "Batch Renderer (experimental)" toggle (off by
   default) is the only integration point right now — keep it that way
   until there's an explicit decision to promote it further.
2. **Prototype in GDScript first, port the hot loop to Rust only once the
   shape is proven.** This is the same discipline `ProjectileFlight`/
   `ProjectileBroadphaseRs` already followed, and the same discipline that
   correctly caught `packet_tax.rs` (16% slower) and whole-Projectile
   pooling (12% slower) as *not* worth keeping before they shipped. Don't
   skip the "measure before porting" step just because Rust tooling
   already exists in this repo.
3. **The real `Projectile.gd` path is not touched by this project.**
   Every fix so far (obstacle-target caching, muzzle-position caching, AI
   shoot throttle, Mythic pattern fanout cap — see the commit history
   around `3c1e1e4`/`d55b6a7`/`b6d20ca`) stays exactly as it is. This
   project is additive, not a replacement, until a real cutover decision
   gets made deliberately.

## Current state (commit `e1e0723`)

`scripts/entities/ProjectileBatchPool.gd` — V1:
- Flat `PackedArray`s per slot (position, direction, speed, damage,
  radius, lifetime, color, scale, source). No `Node2D` per projectile.
- One shared `QuadMesh` via `MultiMeshInstance2D`, tinted per-instance by
  dominant-synergy color, scaled by magnitude. Not per-synergy shapes yet.
- Straight-line flight only.
- Hit detection: plain per-tick distance check against explicitly
  registered targets (`register_target`/`unregister_target`) — not
  integrated with `ProjectileBroadphase` or `Projectile._handle_hit()`.
- Free-list slot recycling, capped capacity (no unbounded growth).

`scripts/ui/GarageTestRange.gd` — "Batch Renderer (experimental)" toggle,
off by default. When on, `_fire_selected()` routes through
`_fire_via_batch_pool()` instead of `_fire_combined_projectile()`. Every
other firing site in the game is untouched.

Covered by `scripts/debug/ProjectileBatchPoolCheck.gd` (pool mechanics in
isolation) and `scripts/debug/TestRangeBatchPoolCheck.gd` (real toggle,
real UI, real hit, zero cross-contamination with the default path).

## What V1 deliberately does NOT cover yet

- Lightning blink-hop, Vortex spiral, Poison mine (stationary/crawling),
  gravity lob, kinetic-scaled range/speed curves — every exotic movement
  type `Projectile.gd` has. Straight-line only so far.
- Per-synergy visual shapes (currently one generic tinted quad for every
  element).
- Mythic patterns (Shotgun/Radial/Beam/Mortar) — Test Range's capital-
  weapon row (Lance Mount/Orbiting Array) also still always uses the real
  path regardless of the toggle.
- Real hit-pipeline integration: no chain lightning, status effect procs,
  elemental resistance, vampiric lifesteal, pierce execution, crit rolls,
  or `ProjectileBroadphase`'s real broadphase — just a flat damage number
  on contact.
- Rust. Still pure GDScript.

## Phased plan, roughly in priority order

### Phase 2 — Movement richness
Port the two most visually/mechanically distinct movement types first to
prove the data model can express real variety, not just straight lines:
- **Vortex spiral** — adds an orbiting offset term to the position update
  each tick, no new per-slot fields beyond an angle/radius pair.
- **Lightning blink-hop** — the hardest one architecturally, since a real
  hop needs live target *re-acquisition* mid-flight (see
  `Projectile.gd`'s `BLINK_INTERVAL`/`_lightning_hops_left` for the real
  behavior). Worth doing early specifically because it's the mechanic that
  produced the extreme "11,865 shots in one volley" stress case that
  started this whole investigation — if the batch pool can't handle
  Lightning cleanly, that's important to know before going further.

Poison mine, gravity lob, and kinetic range/speed curves can follow once
those two prove the per-slot data model holds up.

### Phase 3 — Real hit pipeline
Decide how much of `Projectile._handle_hit()`'s logic actually needs to
run per batch-pool hit vs. gets consciously left as "the batch pool is for
raw damage-and-feel testing, not full synergy fidelity." This is a design
call, not just an engineering one — dropping chain lightning/status procs
might be fine for a perf-comparison tool and wrong for anything closer to
a real gameplay path. Needs a decision before building it, not after.

### Phase 4 — Visual variety
Per-synergy shape library instead of one generic tinted quad — this is
also where the separately-discussed "bake the aesthetic once, don't
rebuild it every shot" idea lands, and it benefits BOTH the batch pool
*and*, if ported back, the real `Projectile._build_visuals()` path.

### Phase 5 — Measure, then maybe Rust
Only after Phases 2-4 (or however much of them lands) have the batch pool
doing something close to feature-complete: benchmark `_step_simulate`'s
inner loop against the real path at comparable shot counts, the same
kind of same-process interleaved A/B this codebase already used to settle
`packet_tax.rs` and `ProjectilePool.gd`. If it's a real win at realistic
batch sizes, port that inner loop to Rust mirroring `ProjectileFlight`'s
existing flat-array FFI contract. If it isn't, that's useful information
too — don't force it.

### Phase 6 — The actual cutover decision (not before explicitly asked)
Whether and how any of this ever becomes the default live-combat path is
a separate, later decision — likely partial (e.g., only for very
high-shot-count synergies like Lightning) rather than all-or-nothing, and
only after real playtesting against the Test Range comparison, not a
unilateral swap.

## Open questions for whoever picks this back up

- Does Phase 3's hit-pipeline scope need the FULL `_handle_hit()` fidelity,
  or is a deliberately-simplified "raw damage only" mode acceptable for
  what this tool is actually for? Ask before building either way.
- Is MultiMesh-per-synergy-family (Phase 4) the right rendering
  granularity, or does even that undercount how much visual variety a
  single element's shots can have (rarity, banked-shot bonus, aoe_bonus
  scaling, etc.)?
- Worth deciding explicitly whether Phase 6 is ever actually the goal, or
  whether this stays a permanent Test Range comparison tool. Both are
  legitimate outcomes.


