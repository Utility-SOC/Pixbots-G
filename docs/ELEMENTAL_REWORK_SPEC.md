# Elemental rework spec (owner direction 2026-10-09)

Source of truth for the Ice, Vortex, Explosive, Guard and solver changes. Supersedes the one-line Ice/Vortex notes in
`Status.md` and `docs/OPEN_QUESTIONS.md` items 3-4. Status: designed, not built. Numbers marked **(tune)** are
illustrative and need a balance pass. Build these on the post-coupling-cut status/movement systems, not the current ones,
so the Rust port does not redo them (see `Status.md` section 2, Prerequisites).

## Ice: embrittlement + shatter
- **Energy interference.** A cold hit of energy `I` on a bot whose actuators receive flow `F` blocks part of that flow for
  several ticks. Proposed: blocked fraction = `I / (I + F)`, so `I == F` blocks half (owner's 60,000 vs 60,000 example).
  Duration scales with `I` **(tune)**. Only the unblocked share reaches the actuators, so the mech slows in proportion.
- **Embrittled.** While affected, reactive plating does not work. (Extra damage taken is implied by the plating loss.)
- **Frozen -> shatter.** A frozen bot hit by a *large* kinetic hit shatters. Violence scales with both inputs: more ice and
  more kinetic means a bigger shatter radius and damage. Shards damage nearby bots (collateral). Below the kinetic
  threshold it is an ordinary hit. Threshold and scaling **(tune)**.
- Replaces the earlier "Shatter + Frost field" wording; the icy trail from that note is optional, not required.

## Vortex: pin, well, wander
- **Pin.** A vortex projectile draws bots in and keeps them pinned to it; they travel with it (replaces fling-only).
  Pairs with Kinetic (fling at the end) and Poison (clump for culling).
- **Gravity-well mine.** Large Poison + large Vortex makes the projectile a stationary gravity-well mine. AoE radius scales
  with the vortex energy. Adding Explosive scales the range further.
- **Wander.** A moving vortex projectile follows bezier curves rather than a straight line.

## Explosive
- Explosive missiles can reach **4x the current maximum diameter**. (Small constant change; ships early.)

## Guards (defence against status effects)
- Existing Stun / Shock / Freeze Guard are energy-fed: they keep remediating only while fed, and strength follows the
  energy routed in (cap 90%). That already matches the intent; no change except calibration (`energy_for_max`, 1500).
- **New Mythic remediation tile.** Handles *all* conditions. **Super rare.** Costs **6x** the energy of a single guard.
  Trade-off: saves grid space but is less focused than the Legendary single-condition guards. Exact drop rate and the
  Legendary single-condition set to be defined **(tune)**.

## AutoEquipSolver
- Must be able to build **loops** and exploit **mixed synergies**.
- Must treat the **head and backpack** as ways to boost and condition energy leaving the reactor, not as inert slots.
- Enemy builds use the same output, so this lifts enemy quality too.

## Notes for the port
- Ice and Vortex touch status effects, movement and projectiles: exactly the systems the Rust migration moves next.
- Energy interference is a per-tick multiplier on actuator flow; keep it a pure function of (ice energy, flow) so it can live
  in `pixbots_core` and be tested natively.
- Vortex pin and bezier wander should read a seeded RNG stream, not global `randf` (see RNG policy in `Status.md`).
