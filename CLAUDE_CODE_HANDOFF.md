# Pixbots-G — Handoff to Claude Code

This project (Godot 4.6 GDScript, hex-grid mech-builder wave-survival game) has been under active development in a separate Cowork session with no local machine access. This document is the full state-of-the-world so a fresh Claude Code session on this machine can pick up correctly. Read this before making changes — several items below correct assumptions that turned out to be wrong when checked against actual code, so verify against the code, not just this doc, wherever the two might drift.

## Immediate task: Rust/GDExtension proof-of-concept

This is why you're being brought in — the previous session is sandboxed to Linux with a blocked network allowlist (couldn't reach rustup.rs, static.rust-lang.org, or GitHub release binaries) and can't produce a Windows build. This machine can.

**What already exists:**
- `rust_poc/hexgrid.rs` — a pure Rust port of `scripts/core/HexCoord.gd`'s coordinate math and `scripts/core/ComponentEquipment.gd`'s `generate_procedural_shape()` shape-growth algorithm (the "recursive grid building" workload). No Godot integration — compiles standalone with plain `rustc` (`rustc -O hexgrid.rs -o hexgrid_bench`), no Cargo needed since it has zero dependencies. Prints a benchmark on run.
- `rust_poc/README.md` — results so far: Rust ran the shape-generation workload at 2.44 µs/shape and the coordinate-math loop at 1.66 ns/op, vs. 69.62 µs/shape and 396.86 ns/op for an equivalent Python port (~28x and ~239x respectively). Both produced identical output (same avg hex count, exact checksum match on the deterministic math loop), confirming the port is faithful.
- `scripts/debug/RustBenchComparison.gd` — the identical algorithm in GDScript, not wired into any menu. **Run this first** (attach to a Node in an empty scene, hit F6) to get the real in-engine GDScript number — that's the actual baseline to beat, not the Python stand-in.

**What's next, in order:**
1. Run `RustBenchComparison.gd`, record the real GDScript number, compare against the Rust number above. If the win isn't meaningful for this workload, that's useful information — don't force the rest of this list.
2. Install Rust via `rustup` (this machine should have real internet access — try `irm https://get.rustup.rs | iex` or the Windows installer from rust-lang.org if that's blocked here too).
3. Set up the actual GDExtension wiring per the godot-rust book (`https://godot-rust.github.io/book/intro/hello-world.html`): a sibling Rust crate (`cargo new rust_ext --lib`, `crate-type = ["cdylib"]`, `cargo add godot`), a `.gdextension` file in the Godot project pointing at `windows.debug.x86_64` / `windows.release.x86_64` DLL paths (this project runs on Windows — don't forget the Windows-specific paths, the tutorial defaults show Linux/Mac too).
4. Port `AutoEquipSolver.gd` (recursive grid building) and the `HexGrid`/`HexCoord` calculations into the new Rust class, expose via `#[godot_api]`/`#[func]`, call from GDScript like any other class.
5. Only if that's a clear win: Phase 2 — `MapGenerator`'s flow fields and `SquadDirector`'s evolutionary algorithms.

Godot-rust requires 4.2+; this project is 4.6, no version concern. LLVM is **not** required (bindgen ships pre-built artifacts now, despite what older tutorials say).

## Recently fixed (context, no action needed)

- `Main.gd:965` was calling `SaveManager.save_game()` with zero arguments when it requires three (`save_name, mech, inventory`). This silently aborted `_on_player_died()` on the 3-consecutive-rival-loss path — the game hung, never returning to the Garage. Fixed to match the autosave pattern used elsewhere in the file. Verify this still holds if you touch that code path.
- The thermal/heat system (`Mech.gd`'s `_update_heat`/`_heat_arc_damage`/`_overheat`) is fully commented out per an explicit decision — don't re-enable without asking.
- A Tournament-arc scaffold exists: `SaveManager.tournament_arc_unlocked` (persisted flag, defaults false, resets on new campaign) and a locked "Tournament" button in `MainMenu.gd` reading it. Nothing sets the flag true yet — the real unlock condition (a Level 100 milestone) doesn't exist as a system yet either.

## Already fully built — verified against code, don't rebuild

A wishlist document review found several claimed-missing features were actually already done (the doc was stale):
- War Room "YOUR MECH" card + bias graphing (`scripts/ui/WarRoomMenu.gd`)
- The entire scrap economy — 5+ spend sites in `GarageMenu.gd` (upgrades, repair, infusion, rarity tier-up, Black Market)
- Mass/ramming/pierce-execution system — every tile has weight, movement speed scales with total mass, ramming damage is `mass × speed`, pierce "cut-in-half" executions exist with boss/commander/jammer exemptions and AI counter-play
- Synergy codex (`GarageMenu.gd`, covers all 9 synergies + shield counters, does **not** cover biomes — worth extending)
- Guided Garage onboarding tutorial (`TutorialManager.gd` + `tutorial.json`, covers Core → tiles → weapon mounts)
- Boss Rush mode — `scripts/ui/BossRushMenu.gd` is a real save-slot browser gated on `max_wave_reached >= 100`, wired into `Main.gd`'s wave-sequencing logic for `SaveManager.current_game_mode == "boss_rush"`

## Confirmed missing — real remaining work

- **PvP Clone System (Traveling Champions)** — nothing built. See Decisions section below for the ground rules already settled.
- **Entity spatial hashing** — still raw `get_nodes_in_group("enemy")` scans in ~8 places (`Mech.gd:463,486,2711`, `Main.gd:958`, `Drone.gd:160`, `MinimapOverlay.gd:140,144`, `SquadDirector.gd:603,838,1018`).
- **MechPartRenderer texture caching** — rebakes every time, no cache keyed on build signature.
- **Modding: data-driven tile-stat JSON** — squad/solver/boss AI profiles are already JSON-moddable (`SquadProfileManager`, `config/default_squads.json`, `user://ai_profiles/`), but tile stats (charge multipliers, damage boosts, splitter faces) are still hardcoded in GDScript per-tile (e.g. `CoreTile.gd`). `MODDING.md` already documents this gap as a known "longer-term plan."
- **Heat UI** — explicitly dropped, do not build (nothing to display since thermal is off).

## Also approved, not yet done

- **Mech.gd split** — approved "do it now." Split the 3,222-line `scripts/entities/Mech.gd` into `BossBrain.gd`, `StatusEffectRunner.gd`, `PlayerController.gd`. **High risk** — this file is touched by nearly everything (combat, AI, mass/ramming, pierce execution, boss abilities, drones). Its original justification (needed before melee-pillar work) is moot since melee/mass is already fully built — this is now a pure maintainability refactor. Go carefully, test thoroughly after.
- **Wire up wild-bot recruitment** (approved — wire up, not delete). `Mech.gd` declares `signal fled_to_wild(bot: Node)` that's never emitted; `SquadDirector.gd`'s `register_wild_bot()`/`_on_wild_bot_died()` are never called, so `_assemble_squad()`'s "recruit wild bots first" step is dead code. Needs: a decision on when a mech "flees" combat (existing retreat/fear AI state, if any) to emit the signal from, and a listener to call `register_wild_bot()`.
- **Wire up AudioManager reactive music** (approved — wire up, not delete). The `AudioManager` autoload has `set_combat_state()`/`set_dominant_synergy()` that nothing outside its own file calls. Needs call sites in `Main.gd`/`Mech.gd` at the right moments (entering combat, dominant elemental synergy changing).

## Narrative / Rival system — verify current state before assuming anything

A prior investigation found this is **significantly further along than expected**, discovered mid-session without a clear record of when it was built:
- `scripts/ai/SquadDirector.gd` already has `all_rival_profiles` (Dictionary), `get_next_rival()`, `rivals_fought_this_round` tracking, and Arthur's last-5-encounters spawn constraint.
- `scripts/ai/RivalProfilesFactory.gd` builds rival profiles from `DialogueManager`'s `dialogue_data`.
- `DialogueManager.gd` exists and reads `config/dialogue.json` (should be a JSON-ified version of `STORY_SCRIPT.md`'s content).
- `Main.gd` has real wave-sequencing logic for both Boss Rush and Rival encounters.

**Do a fresh read of these files before writing any more Rival/Narrative code** — don't trust a wishlist doc's claims about what's missing without checking, the same lesson learned twice already this project (Heat UI and Scrap Economy were both claimed-broken but actually fine).

`STORY_SCRIPT.md` (repo root) is the single source of truth for all narrative text — 15 named rivals with intro/win/loss lines, Traveling Champion flavor text, milestones, Black Market/Silas flavor, death footer lines, Game Over text, Tournament arc teaser, Boss Rush text. If `config/dialogue.json` seems incomplete against it, that's a real gap to fix.

## Decisions already made — ground truth, don't re-litigate

These were settled in the design-review conversation. Implement to these specs unless the player explicitly changes them:

1. **PvP scope**: clipboard-swap only, not real networking. A "Champion Card" is a PNG — the bot's actual rendered visual composited onto a sports-card layout with identifying stats, JSON data embedded via a PNG text chunk (tEXt/iTXt). Long-term goal: host these on a companion webpage/gallery (not this project's concern directly, just don't design the format in a way that makes that harder).
2. **Ghost loot**: on defeat, a ghost always drops one component and some number of tiles. Not a checklist — the ghost's own equipped-tile rarities bias what drops (rarer tiles the ghost had equipped show up more often), using the ghost's inventory as a weighted loot table, still subject to normal rarity drop rules.
3. **Ghost accumulation**: `user://pvp_ghosts/` grows unbounded, no cap. Later (not now): a difficulty setting for how many ghosts can appear in one match (more ghosts = longer rounds) — deferred.
4. **Milestone counter** (10 bosses/champions defeated, Level 100): counts regular wave **bosses only** — not champions/ghosts, not rivals.
5. **Per-round rarity scaling**: rivals scale on a per-character axis to preserve identity, not a blanket rarity bump — e.g. Arthur (already Mythic-only) and Sammy (deliberately junk-tier) need different scaling knobs than a flat "+1 rarity tier per round."
6. **Revoked tournament eligibility** (3 consecutive rival losses): no more Rival fights on that save; regular wave play continues but with no wave rewards (a wave-reward-every-20-waves mechanic that itself doesn't exist yet and needs building); effectively exits the player from the story arc.
7. **Milestone rewards**: auto-granted directly into inventory with a notification popup — no mailbox/claim system.
8. **Boss Rush** needed a real save-slot browser — this is now done (`BossRushMenu.gd`).
9. **Leo & Luna makeup battle**: if the player kills only one twin then later dies (without hitting the 3-loss game-over), they get a one-off battle against the surviving twin, who wagers a valuable tile (Legendary+, Mythic+ once the player reaches level 100+). This battle is outside normal league play and does **not** count toward the 3-loss tournament-disqualification counter.
10. **Rex's build-copy**: snapshots the player's **last deployed** loadout, not a live snapshot at challenge time.
11. **Speculative AI profile sharing** (practicing against a rival's build): happens on **first encounter** with that rival.
12. **Tournament arc**: scaffold only for now (done — flag + locked button + stub handler). Full tournament gameplay is future work, tied to the Level 100 milestone system which doesn't exist yet.

## Lower-priority feature suggestions (optional)

- Extend the synergy codex to cover biome interactions (currently skips them).
- Reuse the Champion Card PNG renderer for a "Rival Roster" gallery screen showing all 15 rivals + any champions beaten.
- Once spatial hashing exists, route the minimap and magnet-pull queries through it too, not just whatever prompted building it.

## Machine/tooling notes

- This machine should have real, unrestricted internet access (the Cowork sandbox that did the Rust POC had a network allowlist blocking rustup.rs, static.rust-lang.org, and GitHub release downloads — that's why the POC used a bare `rustc` compile via an apt-installed compiler rather than a full Cargo/rustup setup).
- Godot is already installed and was seen running as "Pixbots-G (DEBUG)" — confirm the exact version is 4.6 before assuming API compatibility.
