use std::collections::HashMap;

// Phase 2 of the pixbots_core split: the hot inner loop of
// Mech._simulate_grid with FULL tile coverage - every tile type maps to a
// kind below, including the stateful ones (Resonator remnants/sync
// residues, Mythic Splitter remnants, Magnet accumulation, Accumulator
// stamps, Lance face-gating, Shield banking, mech-level Jumpjet/Actuator
// merges). Stateful tiles receive prior state from the bridge
// (scripts/core/RustGridSim.gd) and return final state for write-back, so
// cross-sim persistence (reset only via reset_simulation_state) behaves
// exactly as before. The bridge still vetoes any tile it can't describe
// faithfully (gated/inverted Catalysts) so those grids fall back to the
// GDScript path automatically.
//
// PARITY DISCIPLINE: every operation mirrors its GDScript original - same
// float op order, same clamps, same merge/split/amplify semantics
// (EnergyPacket.gd), same per-kind process_energy branches.
// RustGridSimParityCheck.gd holds the two paths identical; when a tile
// script changes in GDScript, the matching arm here MUST change too.
//
// Tile kinds (must match RustGridSim.gd's KIND_* constants):
//   0 PASS          - plain pass-through (base HexTile, Sensor, Counter-*,
//                     Missile Rack, Mobility Core, disabled tiles)
//   1 AMPLIFIER     - amplify(mult), optional aoe_add (Mythic AoE focus)
//   2 SPLITTER      - faces + ratio weights; optional pre_amp (Power Grid),
//                     optional Mythic remnant state
//   3 REFLECTOR     - direction = (entry + 3 + rotation) % 6
//   4 CONDUIT       - pass-through, reports dominant synergy; valve mode
//   5 INFUSER       - convert RAW -> syn at rate, then add flat amount
//   6 CATALYST      - convert everything -> target; optional magnitude/
//                     every-Nth gating (state: gate_counter), optional
//                     Mythic Inverted filter-instead-of-convert mode
//   7 CORE          - redistribute incoming across active faces
//   8 MOUNT_SINK    - Weapon Mount capture; optional range_mult (Sniper)
//   9 LINK_SINK     - Component Link with target slot: transfer capture
//  10 LINK_ROUTER   - Energy Intake/Accessory Return: split across faces
//  11 STORE_SINK    - HealBeacon/Jammer/DroneBay/Cloak (incl. AllyCloak):
//                     bank mag * coef
//  12 FILTER        - keep allowed+RAW, return removed mass to RAW at rate
//  13 MAGNET        - accumulate magnetic power (state), lightning mult
//  14 JUMPJET       - consume; emit mech-merge capture
//  15 ACTUATOR      - consume; per-tile speed bonus + mech-merge capture
//  16 SHIELD_STORE  - Shield Generator / Shield tile: bank energy + syn
//  17 ACCUMULATOR   - stamp acc_* / trigger / quality / auto-dump
//  18 RESONATOR     - non-Mythic: baseline amplify + remnant state; optional
//                     post_amp (Power Grid Resonator)
//  19 RESONATOR_SYNC- Mythic: 3-path residue state + proc conferral
//  20 PRIME_CIRCUIT - Amplifier + Infuser + Resonator-baseline in one
//  21 LANCE         - multi-cell capture with per-face magnitude bookkeeping
//  22 THRUSTER      - consume; emit mech-merge capture (Maneuvering
//                     Thruster - mech.thruster_accel_bonus, no packet
//                     merge needed, just the "was fed" event)

pub const SYN_COUNT: usize = 10;
pub const MAX_MAGNITUDE: f64 = 600000.0;
pub const NORMAL_MAGNITUDE_CAP: f64 = 150000.0;
pub const MYTHIC_RARITY: i64 = 4;
// Lowered from 1000 (2026-08-10 live playtest: wave 9-12 bot spawning
// collapsed to 2-7fps - common-rarity builds with no Mythic-overcharge
// intent at all were routinely hitting the full 1000-step cap on plain
// Reflector/edge-bounce loops that never resolve to zero active packets
// on their own, NOT the intentional Mythic-overcharge mechanic (that's
// explicitly about all-Mythic annexes building magnitude before releasing
// it - MythicOverchargeSplitCheck.gd's split/bounce behavior resolves in
// a handful of steps regardless of this cap, and LongPathStepCapCheck.gd's
// legitimate 150-step straight-line crossing stays comfortably inside
// 200). This is the REAL hot path - Mech._simulate_grid's own GDScript
// STEP_CAP constant only governs its fallback loop, which real spawns
// never reach once RustGridSim.try_simulate() succeeds (confirmed via
// live diagnostic: it does, for every role/rarity combination tested).
pub const STEP_CAP: i64 = 200;
// Negligible-packet culling (user's own proposal, 2026-08-10): a packet
// that's decayed to a trivial fraction of the energy actually in play is
// rounding-error noise, not a meaningful part of the build - letting it
// keep consuming simulation steps forever (it can never merge away since
// merge only fires for exact position+direction matches) is pure waste.
// Two floors, matching the user's own framing exactly: an absolute floor
// for low-total builds (their own example: "some 4 energy packets
// running around" - well under the ~600 energy single-packet baseline
// this game's payload scale standardizes around, per Status.md's own
// design directive), and a floor relative to the CURRENT total active
// energy for high-total (Mythic-overcharge-scale) builds - "greater than
// 1,200,000 energy total" is their own number; 0.05% of that (~600, the
// same baseline) is "a rounding error" by comparison to a real overcharge
// loop, without touching the loop's actual dominant packets at all.
// Mirrored in Mech._simulate_grid's own GDScript fallback loop.
pub const NEGLIGIBLE_MAGNITUDE_FLOOR: f64 = 2.0;
pub const HIGH_TOTAL_ENERGY_THRESHOLD: f64 = 1200000.0;
pub const HIGH_TOTAL_RELATIVE_CULL_FRACTION: f64 = 0.0005;
// Loop detection: a tile entered through the same face on this many DIFFERENT
// steps is being recirculated (an Infuser/Amplifier in a ring keeps re-adding
// to the same packet stream). Reported to the garage as a warning.
pub const LOOP_ENTRY_STEPS: i64 = 5;
pub const SYN_RAW: usize = 0;
pub const SYN_LIGHTNING: usize = 3;
pub const SYN_KINETIC: usize = 7;

#[derive(Clone, Default)]
pub struct Packet {
    pub magnitude: f64,
    pub syn: [f64; SYN_COUNT],
    pub syn_present: [bool; SYN_COUNT],
    pub proc_syn: [f64; SYN_COUNT],
    pub proc_present: [bool; SYN_COUNT],
    pub dir: i64,
    pub q: i64,
    pub r: i64,
    pub steps: i64,
    pub active: bool,
    pub charge_required: f64,
    pub accumulator_quality: f64,
    pub aoe_bonus: f64,
    pub acc_charge_mult: f64,
    pub acc_damage_mult: f64,
    pub range_mult: f64,
    pub auto_dump_threshold: f64,
    pub trigger: i64, // 0 = "None", 1..3 = keys (EnergyPacket.trigger_key)
    // True for the excess a non-Mythic tile bounced back (overload reflection). Used only so the
    // overload marker lands on the choke tile and not on the tile the excess flows back into.
    pub reflected: bool,
}

impl Packet {
    pub fn set_magnitude(&mut self, v: f64) {
        self.magnitude = v.min(MAX_MAGNITUDE);
    }

    pub fn syn_total(&self) -> f64 {
        self.syn.iter().sum()
    }

    pub fn sync_synergies(&mut self) {
        let total = self.syn_total();
        if total > self.magnitude * 1.0001 {
            let factor = self.magnitude / total;
            for v in self.syn.iter_mut() {
                *v *= factor;
            }
        }
    }

    pub fn add_synergy(&mut self, k: usize, amount: f64) {
        self.syn[k] += amount;
        self.syn_present[k] = true;
        self.set_magnitude(self.magnitude + amount);
        self.sync_synergies();
    }

    pub fn convert_synergy(&mut self, from: usize, to: usize, percentage: f64) {
        if !self.syn_present[from] {
            return;
        }
        let amount = self.syn[from] * percentage;
        self.syn[from] -= amount;
        if self.syn[from] <= 0.0 {
            self.syn[from] = 0.0;
            self.syn_present[from] = false;
        }
        self.syn[to] += amount;
        self.syn_present[to] = true;
    }

    pub fn amplify(&mut self, mut multiplier: f64) {
        let new_mag = self.magnitude * multiplier;
        if new_mag > MAX_MAGNITUDE && self.magnitude > 0.0 {
            multiplier = MAX_MAGNITUDE / self.magnitude;
        } else if self.magnitude <= 0.0 {
            multiplier = 1.0;
        }
        self.set_magnitude(self.magnitude * multiplier);
        for v in self.syn.iter_mut() {
            *v *= multiplier;
        }
        self.sync_synergies();
    }

    // EnergyPacket.split(): the share carries proc_synergies (duplicated)
    // but NOT trigger_key / auto_dump_threshold / traversal steps.
    pub fn split(&mut self, ratio: f64) -> Packet {
        let mut newp = self.clone();
        newp.set_magnitude(self.magnitude * ratio);
        for i in 0..SYN_COUNT {
            newp.syn[i] = self.syn[i] * ratio;
        }
        newp.steps = 0;
        newp.auto_dump_threshold = 0.0;
        newp.trigger = 0;
        self.set_magnitude(self.magnitude * (1.0 - ratio));
        for v in self.syn.iter_mut() {
            *v *= 1.0 - ratio;
        }
        newp
    }

    pub fn merge(&mut self, other: &Packet) {
        self.set_magnitude(self.magnitude + other.magnitude);
        self.accumulator_quality = self.accumulator_quality.min(other.accumulator_quality);
        self.aoe_bonus = self.aoe_bonus.max(other.aoe_bonus);
        self.acc_charge_mult = self.acc_charge_mult.max(other.acc_charge_mult);
        self.acc_damage_mult = self.acc_damage_mult.max(other.acc_damage_mult);
        self.range_mult = self.range_mult.max(other.range_mult);
        self.auto_dump_threshold = self.auto_dump_threshold.max(other.auto_dump_threshold);
        self.reflected = self.reflected && other.reflected;
        for i in 0..SYN_COUNT {
            if other.syn_present[i] {
                self.syn[i] += other.syn[i];
                self.syn_present[i] = true;
            }
            if other.proc_present[i] {
                self.proc_syn[i] = self.proc_syn[i].max(other.proc_syn[i]);
                self.proc_present[i] = true;
            }
        }
        self.sync_synergies();
    }

    pub fn add_proc(&mut self, k: usize, strength: f64) {
        self.proc_syn[k] = self.proc_syn[k].max(strength);
        self.proc_present[k] = true;
    }

    // EnergyPacket.has_synergy(type) with the default 0.0 threshold.
    pub fn has_synergy(&self, k: usize) -> bool {
        if self.magnitude == 0.0 {
            return false;
        }
        self.syn_present[k] && self.syn[k] > 0.0
    }

    pub fn dominant_synergy(&self) -> i64 {
        let mut max_syn = 0i64;
        let mut max_val = -1.0f64;
        let mut any = false;
        for i in 0..SYN_COUNT {
            if self.syn_present[i] {
                any = true;
                if self.syn[i] > max_val {
                    max_val = self.syn[i];
                    max_syn = i as i64;
                }
            }
        }
        if any {
            max_syn
        } else {
            0
        }
    }
}

#[derive(Default, Clone)]
pub struct TileState {
    pub remnant: [f64; SYN_COUNT],
    pub remnant_present: [bool; SYN_COUNT],
    pub residue_syn: [i64; 3],
    pub residue_steps: [i64; 3],
    pub magnetic_power: f64,
    pub stored_energy: f64,
    pub stored_syn: [f64; SYN_COUNT],
    pub speed_bonus: f64,
    pub gate_counter: i64,
}

#[derive(Default, Clone)]
pub struct TileDesc {
    pub kind: i64,
    pub rarity: i64,
    pub disabled: bool,
    pub sync_adjustment: i64,
    pub faces: Vec<i64>,
    pub weights: Vec<f64>,
    pub rotation: i64,
    pub amp_mult: f64,
    pub aoe_add: f64,
    pub pre_amp: f64,
    pub post_amp: f64,
    pub infuse_syn: usize,
    pub conv_rate: f64,
    pub infuse_amount: f64,
    pub catalyst_target: usize,
    pub catalyst_mult: f64,
    pub store_coef: f64,
    pub valve: bool,
    pub filter_allowed: usize,
    pub filter_raw_return: f64,
    pub magnet_lightning_mult: f64,
    pub actuator_base_mult: f64,
    pub actuator_kin_mult: f64,
    pub actuator_ltg_mult: f64,
    pub shield_mult: f64,
    pub acc_charge_div: f64,
    pub acc_damage: f64,
    pub acc_auto_dump: f64,
    pub acc_trigger: i64,
    pub acc_quality: f64,
    pub res_baseline_mult: f64,
    pub res_remnant_boost: f64,
    pub sync_dropoff: [i64; 3],
    pub range_mult_stamp: f64,
    pub mythic_remnants: bool,
    pub extra_cells: Vec<(i64, i64)>,
    pub gate_min_magnitude: f64,
    pub gate_every_n: i64,
    pub inverted: bool,
}

// HexCoord.get_directions(): E, SE, SW, W, NW, NE (axial q,r deltas).
pub const DIRS: [(i64, i64); 6] = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)];

pub fn neighbor(q: i64, r: i64, d: i64) -> (i64, i64) {
    let dd = DIRS[(d.rem_euclid(6)) as usize];
    (q + dd.0, r + dd.1)
}


pub const CAPTURE_STRIDE: usize = 52;

pub struct SimOutputs {
    pub captures: Vec<(usize, Packet, i64)>,
    pub stores: Vec<(usize, f64)>,
    pub mech_merges: Vec<(usize, Packet)>,
    pub lance_hits: Vec<(usize, i64, i64, Packet)>,
    pub conduit_dominant: HashMap<usize, i64>,
}

// Non-Mythic Resonator baseline, shared by RESONATOR and the Resonator
// stage of PRIME_CIRCUIT. Mirrors ResonatorTile.process_energy exactly.
pub fn resonator_baseline(p: &mut Packet, tile: &TileDesc, state: &mut TileState) {
    let mut mult = tile.res_baseline_mult;
    let any_remnant = state.remnant_present.iter().any(|x| *x);
    if any_remnant {
        for k in 0..SYN_COUNT {
            if state.remnant_present[k] {
                p.add_synergy(k, state.remnant[k] * 0.8);
                state.remnant[k] *= 0.2;
            }
        }
        mult += tile.res_remnant_boost;
    }
    p.amplify(mult);
    for k in 0..SYN_COUNT {
        if p.syn_present[k] {
            state.remnant[k] = p.syn[k] * 0.15;
            state.remnant_present[k] = true;
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub fn process_energy(
    tile_idx: usize,
    tile: &TileDesc,
    state: &mut TileState,
    mut p: Packet,
    entry_dir: i64,
    entry_cell: (i64, i64),
    tile_anchor: (i64, i64),
    grid: &HashMap<(i64, i64), usize>,
    out: &mut SimOutputs,
) -> Vec<Packet> {
    match tile.kind {
        1 => {
            if tile.aoe_add > 0.0 {
                p.aoe_bonus += tile.aoe_add;
            }
            p.amplify(tile.amp_mult);
            vec![p]
        }
        2 => {
            if tile.pre_amp != 1.0 {
                p.amplify(tile.pre_amp);
            }
            if tile.mythic_remnants {
                let any = state.remnant_present.iter().any(|x| *x);
                if any {
                    for k in 0..SYN_COUNT {
                        if state.remnant_present[k] {
                            p.add_synergy(k, state.remnant[k] * 0.8);
                            state.remnant[k] *= 0.2;
                        }
                    }
                }
                for k in 0..SYN_COUNT {
                    if p.syn_present[k] {
                        state.remnant[k] = p.syn[k] * 0.15;
                        state.remnant_present[k] = true;
                    }
                }
                p.amplify(2.0);
            }
            let split_count = tile.faces.len();
            if split_count == 0 {
                return vec![p];
            }
            let mut total_weight: f64 = 0.0;
            for w in &tile.weights {
                total_weight += *w;
            }
            let mut outs = Vec::new();
            let mut consumed: f64 = 0.0;
            for i in 0..split_count {
                let exit_dir = tile.faces[i];
                if i < split_count - 1 {
                    let share = tile.weights[i] / total_weight;
                    let tail_ratio = (share / (1.0 - consumed).max(0.0001)).clamp(0.0001, 0.9999);
                    let mut newp = p.split(tail_ratio);
                    newp.dir = exit_dir;
                    outs.push(newp);
                    consumed += share;
                } else {
                    p.dir = exit_dir;
                    outs.push(p.clone());
                }
            }
            outs
        }
        3 => {
            p.dir = (entry_dir + 3 + tile.rotation).rem_euclid(6);
            vec![p]
        }
        4 => {
            out.conduit_dominant.insert(tile_idx, p.dominant_synergy());
            if tile.disabled {
                return vec![p];
            }
            if tile.valve {
                let forward_face = tile.rotation.rem_euclid(6);
                if entry_dir != forward_face {
                    return vec![];
                }
            }
            vec![p]
        }
        5 => {
            if tile.infuse_syn == SYN_RAW {
                p.dir = (entry_dir + 3).rem_euclid(6);
                return vec![p];
            }
            p.convert_synergy(SYN_RAW, tile.infuse_syn, tile.conv_rate);
            p.add_synergy(tile.infuse_syn, tile.infuse_amount);
            p.dir = (entry_dir + 3).rem_euclid(6);
            vec![p]
        }
        6 => {
            if p.magnitude <= 0.0 {
                return vec![p];
            }
            // Gated injection: a packet failing either gate passes through
            // UNTOUCHED (no conversion, no efficiency gain). The counter
            // only advances on packets that cleared the magnitude gate, so
            // "every Nth" means every Nth QUALIFYING packet.
            if tile.gate_min_magnitude > 0.0 && p.magnitude < tile.gate_min_magnitude {
                return vec![p];
            }
            if tile.gate_every_n > 1 {
                state.gate_counter = (state.gate_counter + 1) % tile.gate_every_n;
                if state.gate_counter != 0 {
                    return vec![p];
                }
            }
            if tile.inverted && tile.rarity == MYTHIC_RARITY {
                // Inverted (Mythic): filter mode - keep only the target
                // element, void everything else outright (no conversion,
                // no efficiency gain).
                let kept = if p.syn_present[tile.catalyst_target] {
                    p.syn[tile.catalyst_target]
                } else {
                    0.0
                };
                p.syn = [0.0; SYN_COUNT];
                p.syn_present = [false; SYN_COUNT];
                p.magnitude = 0.0;
                if kept > 0.0 {
                    p.add_synergy(tile.catalyst_target, kept);
                }
                return vec![p];
            }
            let mut total_consumed = 0.0;
            for i in 0..SYN_COUNT {
                if p.syn_present[i] {
                    total_consumed += p.syn[i];
                }
            }
            p.syn = [0.0; SYN_COUNT];
            p.syn_present = [false; SYN_COUNT];
            let output = total_consumed * tile.catalyst_mult;
            p.magnitude = 0.0;
            p.add_synergy(tile.catalyst_target, output);
            vec![p]
        }
        7 => {
            if tile.disabled {
                return vec![p];
            }
            let mut outs = Vec::new();
            for f in &tile.faces {
                let mut newp = p.clone();
                newp.dir = *f;
                newp.active = true;
                outs.push(newp);
            }
            outs
        }
        8 => {
            if tile.range_mult_stamp != 1.0 {
                p.range_mult *= tile.range_mult_stamp;
            }
            out.captures.push((tile_idx, p.clone(), p.steps));
            vec![]
        }
        9 => {
            if tile.disabled {
                return vec![p];
            }
            out.captures.push((tile_idx, p.clone(), p.steps));
            vec![]
        }
        10 => {
            if tile.disabled {
                return vec![p];
            }
            let split_count = tile.faces.len();
            if split_count == 0 {
                return vec![p];
            }
            let ratio = 1.0 / split_count as f64;
            let mut outs = Vec::new();
            for i in 0..split_count {
                let exit_dir = tile.faces[i];
                let npos = neighbor(tile_anchor.0, tile_anchor.1, exit_dir);
                let mut target = if i < split_count - 1 {
                    p.split(ratio / (1.0 - ratio * i as f64))
                } else {
                    p.clone()
                };
                target.dir = exit_dir;
                if !grid.contains_key(&npos) {
                    out.captures.push((tile_idx, target.clone(), target.steps));
                } else {
                    outs.push(target);
                }
            }
            outs
        }
        11 => {
            if p.magnitude <= 0.0 || !p.active {
                return vec![];
            }
            out.stores.push((tile_idx, p.magnitude * tile.store_coef));
            vec![]
        }
        12 => {
            let mut removed_mag = 0.0;
            let mut new_syn = [0.0; SYN_COUNT];
            let mut new_present = [false; SYN_COUNT];
            for k in 0..SYN_COUNT {
                if p.syn_present[k] {
                    if k == tile.filter_allowed || k == SYN_RAW {
                        new_syn[k] = p.syn[k];
                        new_present[k] = true;
                    } else {
                        removed_mag += p.syn[k];
                    }
                }
            }
            if removed_mag > 0.0 {
                new_syn[SYN_RAW] += removed_mag * tile.filter_raw_return;
                new_present[SYN_RAW] = true;
            }
            p.syn = new_syn;
            p.syn_present = new_present;
            p.set_magnitude(p.syn_total());
            vec![p]
        }
        13 => {
            state.magnetic_power += p.magnitude;
            if p.has_synergy(SYN_LIGHTNING) {
                state.magnetic_power *= tile.magnet_lightning_mult;
            }
            vec![]
        }
        14 => {
            if p.magnitude <= 0.0 || !p.active {
                return vec![];
            }
            out.mech_merges.push((tile_idx, p.clone()));
            vec![]
        }
        15 => {
            let mut bonus = p.magnitude * tile.actuator_base_mult;
            if p.has_synergy(SYN_KINETIC) {
                bonus *= tile.actuator_kin_mult;
            }
            if p.has_synergy(SYN_LIGHTNING) {
                bonus *= tile.actuator_ltg_mult;
            }
            state.speed_bonus = bonus;
            out.mech_merges.push((tile_idx, p.clone()));
            vec![]
        }
        16 => {
            if p.magnitude <= 0.0 || !p.active {
                return vec![];
            }
            state.stored_energy += p.magnitude * tile.shield_mult;
            for k in 0..SYN_COUNT {
                if p.syn_present[k] {
                    state.stored_syn[k] += p.syn[k] * tile.shield_mult;
                }
            }
            vec![]
        }
        17 => {
            p.acc_charge_mult *= tile.acc_charge_div;
            p.acc_damage_mult *= tile.acc_damage;
            p.auto_dump_threshold = p.auto_dump_threshold.max(tile.acc_auto_dump);
            if tile.acc_trigger != 0 {
                p.trigger = tile.acc_trigger;
            }
            p.accumulator_quality = p.accumulator_quality.min(tile.acc_quality);
            vec![p]
        }
        18 => {
            resonator_baseline(&mut p, tile, state);
            if tile.post_amp != 1.0 {
                p.amplify(tile.post_amp);
            }
            vec![p]
        }
        19 => {
            let this_path = (entry_dir.rem_euclid(6) % 3) as usize;
            for path in 0..3 {
                if path == this_path {
                    continue;
                }
                if state.residue_syn[path] >= 0 {
                    p.add_proc(state.residue_syn[path] as usize, 0.5);
                    state.residue_steps[path] -= 1;
                    if state.residue_steps[path] <= 0 {
                        state.residue_syn[path] = -1;
                        state.residue_steps[path] = 0;
                    }
                }
            }
            let dom = p.dominant_synergy();
            if dom != SYN_RAW as i64 {
                state.residue_syn[this_path] = dom;
                state.residue_steps[this_path] = tile.sync_dropoff[this_path];
            }
            // Power Grid Resonator (brand subclass): a flat extra amplify
            // pass applied AFTER the base Sync behavior, same "base +
            // bonus" shape as the baseline Resonator's post_amp (kind 18).
            if tile.post_amp != 1.0 {
                p.amplify(tile.post_amp);
            }
            vec![p]
        }
        20 => {
            p.amplify(tile.amp_mult);
            if tile.infuse_syn != SYN_RAW {
                p.convert_synergy(SYN_RAW, tile.infuse_syn, tile.conv_rate);
                p.add_synergy(tile.infuse_syn, tile.infuse_amount);
            }
            resonator_baseline(&mut p, tile, state);
            vec![p]
        }
        21 => {
            if p.magnitude <= 0.0 || !p.active {
                return vec![];
            }
            // -1 = "entry_cell matched none of this Lance's own cells" -
            // grid/state inconsistency (shouldn't normally happen) rather
            // than a real hit on the anchor. Previously defaulted silently
            // to 0 (the anchor cell), misattributing the hit instead of
            // signaling the mismatch. The GDScript side (RustGridSim.gd)
            // only uses this to build a "%d:%d" face_key string, so -1 is
            // safe to pass through: it just becomes a face key that never
            // matches a real tracked face, instead of wrongly crediting one.
            let mut cell_idx: i64 = if entry_cell == tile_anchor { 0 } else { -1 };
            if entry_cell != tile_anchor {
                for (i, off) in tile.extra_cells.iter().enumerate() {
                    if entry_cell == (tile_anchor.0 + off.0, tile_anchor.1 + off.1) {
                        cell_idx = i as i64 + 1;
                        break;
                    }
                }
            }
            out.lance_hits.push((tile_idx, cell_idx, entry_dir, p.clone()));
            vec![]
        }
        22 => {
            // Maneuvering Thruster: consume + mech-level merge, same shape
            // as Jumpjet/Actuator but the bridge write-back only needs the
            // "this tile was fed" event (mech.thruster_accel_bonus takes
            // the tile's rarity via max(), not the packet's magnitude).
            if p.magnitude <= 0.0 || !p.active {
                return vec![];
            }
            out.mech_merges.push((tile_idx, p.clone()));
            vec![]
        }
        _ => vec![p],
    }
}


pub struct SimResult {
    pub outs: SimOutputs,
    pub flow_visits: Vec<f64>,
    pub flow_energy: Vec<f64>,
    pub flow_syn: Vec<[f64; SYN_COUNT]>,
    pub entry_steps: Vec<[i64; 6]>,
    pub overload_peak: Vec<f64>,
    pub hit_step_cap: bool,
    pub steps: i64,
}

/// Runs the packet simulation to completion (or STEP_CAP). `grid` maps every occupied cell (including a tile's extra
/// cells) to its tile index; `anchors[i]` is tile i's anchor cell; `valid` is the set of empty-but-valid cells.
pub fn simulate(
    descs: &[TileDesc],
    states: &mut [TileState],
    anchors: &[(i64, i64)],
    grid: &HashMap<(i64, i64), usize>,
    valid: &HashMap<(i64, i64), bool>,
    mut active: Vec<Packet>,
) -> SimResult {
        let mut outs = SimOutputs {
            captures: Vec::new(),
            stores: Vec::new(),
            mech_merges: Vec::new(),
            lance_hits: Vec::new(),
            conduit_dominant: HashMap::new(),
        };

        // Per-tile flow stats for the garage: packets entering, energy entering,
        // synergy-weighted energy, and (for loop detection) the number of
        // distinct steps each entry face was used.
        let mut flow_visits: Vec<f64> = vec![0.0; descs.len()];
        let mut flow_energy: Vec<f64> = vec![0.0; descs.len()];
        let mut flow_syn: Vec<[f64; SYN_COUNT]> = vec![[0.0; SYN_COUNT]; descs.len()];
        let mut entry_steps: Vec<[i64; 6]> = vec![[0; 6]; descs.len()];
        // Largest magnitude that tried to enter each non-Mythic tile above
        // NORMAL_MAGNITUDE_CAP (the tile can't carry it; the excess reflects).
        let mut overload_peak: Vec<f64> = vec![0.0; descs.len()];

        let mut steps = 0i64;
        while !active.is_empty() && steps < STEP_CAP {
            steps += 1;

            let mut next: Vec<Packet> = Vec::new();

            for p0 in active.iter() {
                if !p0.active {
                    continue;
                }
                let mut p = p0.clone();
                let dir = p.dir;
                let npos = neighbor(p.q, p.r, dir);

                if let Some(&tidx) = grid.get(&npos) {
                    let anchor = anchors[tidx];
                    p.steps += 1;
                    p.steps = (p.steps + descs[tidx].sync_adjustment).max(0);

                    let mut entering = p.clone();
                    if descs[tidx].rarity != MYTHIC_RARITY && p.magnitude > NORMAL_MAGNITUDE_CAP {
                        // Mark only the choke tile: excess already reflected back is not a new fault
                        // for the tile it flows back into (owner ruling 2026-10-07).
                        if !p.reflected && p.magnitude > overload_peak[tidx] {
                            overload_peak[tidx] = p.magnitude;
                        }
                        entering = p.split(NORMAL_MAGNITUDE_CAP / p.magnitude);
                        entering.steps = p.steps;
                        p.dir = (dir + 3).rem_euclid(6);
                        p.reflected = true;
                        next.push(p.clone());
                    }
                    entering.reflected = false;

                    let entry = (dir + 3).rem_euclid(6);
                    flow_visits[tidx] += 1.0;
                    flow_energy[tidx] += entering.magnitude;
                    for k in 0..SYN_COUNT {
                        flow_syn[tidx][k] += entering.syn[k];
                    }
                    entry_steps[tidx][entry as usize] += 1;
                    let (desc_ref, state_ref) = (&descs[tidx], &mut states[tidx]);
                    let processed = process_energy(
                        tidx, desc_ref, state_ref, entering, entry, npos, anchor, &grid, &mut outs,
                    );
                    for mut out_p in processed {
                        out_p.q = anchor.0;
                        out_p.r = anchor.1;
                        out_p.steps = p.steps;
                        next.push(out_p);
                    }
                } else if valid.contains_key(&npos) {
                    let mut pass = p.clone();
                    pass.q = npos.0;
                    pass.r = npos.1;
                    pass.steps += 1;
                    pass.set_magnitude(pass.magnitude * 0.95);
                    for v in pass.syn.iter_mut() {
                        *v *= 0.95;
                    }
                    next.push(pass);
                } else {
                    let mut bounce = p.clone();
                    bounce.dir = (dir + 3).rem_euclid(6);
                    next.push(bounce);
                }
            }

            let mut merged: HashMap<i64, Packet> = HashMap::new();
            let mut order: Vec<i64> = Vec::new();
            for p in next {
                if !p.active {
                    continue;
                }
                let key = ((p.q + 4096) * 8192 + (p.r + 4096)) * 8 + p.dir;
                match merged.get_mut(&key) {
                    Some(existing) => existing.merge(&p),
                    None => {
                        merged.insert(key, p);
                        order.push(key);
                    }
                }
            }
            active = order.into_iter().map(|k| merged.remove(&k).unwrap()).collect();

            // Negligible-packet cull, moved to run AFTER this step's
            // movement. Exempts any packet whose NEXT hop would land on a real tile
            // (2026-08-11 fix) - mirrors Mech._simulate_grid's own GDScript
            // fallback loop exactly, see that function's matching comment
            // for the full root-cause writeup (an earlier attempt that just
            // moved this check to run after movement instead of before it
            // turned out to be a no-op - "after this step" and "before next
            // step's movement" are the same point in the timeline). A
            // packet freshly split off by a Splitter is created AT the
            // splitter's own hex, not yet moved into whatever real tile is
            // one hex further along its path - it needs a genuine SECOND
            // loop iteration to actually reach and register there. The
            // floor was killing it in that gap even though it was already
            // correctly routed - not "wandering pointlessly," which is
            // what this cull is actually for (Reflector/edge-bounce loops
            // and empty-hex passes that never resolve on their own).
            let mut total_active_magnitude = 0.0f64;
            for p in active.iter() {
                if p.active {
                    total_active_magnitude += p.magnitude;
                }
            }
            let relative_floor = if total_active_magnitude > HIGH_TOTAL_ENERGY_THRESHOLD {
                total_active_magnitude * HIGH_TOTAL_RELATIVE_CULL_FRACTION
            } else {
                0.0
            };
            let cull_floor = NEGLIGIBLE_MAGNITUDE_FLOOR.max(relative_floor);
            for p in active.iter_mut() {
                if p.active && p.magnitude < cull_floor {
                    let npos = neighbor(p.q, p.r, p.dir);
                    let about_to_hit_tile = grid.contains_key(&npos);
                    if !about_to_hit_tile {
                        p.active = false;
                    }
                }
            }
        }

        let hit_step_cap = !active.is_empty();
    SimResult { outs, flow_visits, flow_energy, flow_syn, entry_steps, overload_peak, hit_step_cap, steps }
}


#[cfg(test)]
mod tests {
    use super::*;

    fn packet_at(q: i64, r: i64, dir: i64, magnitude: f64) -> Packet {
        let mut p = Packet::default();
        p.magnitude = magnitude;
        p.syn[SYN_RAW] = magnitude;
        p.syn_present[SYN_RAW] = true;
        p.dir = dir;
        p.q = q;
        p.r = r;
        p.active = true;
        p
    }

    // A row of tiles along +q starting at q = 1; empty valid cells fill the gaps.
    fn run(kinds: &[(i64, TileDesc)], valid_to: i64, packet: Packet) -> SimResult {
        let mut descs = Vec::new();
        let mut anchors = Vec::new();
        let mut grid = HashMap::new();
        for (i, (q, d)) in kinds.iter().enumerate() {
            descs.push(d.clone());
            anchors.push((*q, 0));
            grid.insert((*q, 0), i);
        }
        let mut valid = HashMap::new();
        for q in 0..=valid_to {
            if !grid.contains_key(&(q, 0)) {
                valid.insert((q, 0), true);
            }
        }
        let mut states = vec![TileState::default(); descs.len()];
        simulate(&descs, &mut states, &anchors, &grid, &valid, vec![packet])
    }

    fn mount() -> TileDesc {
        TileDesc { kind: 8, range_mult_stamp: 1.0, ..TileDesc::default() }
    }

    #[test]
    fn empty_valid_hexes_cost_five_percent_each() {
        let r = run(&[(5, mount())], 5, packet_at(0, 0, 0, 100.0));
        assert_eq!(r.outs.captures.len(), 1);
        let got = r.outs.captures[0].1.magnitude;
        assert!((got - 100.0 * 0.95f64.powi(4)).abs() < 1e-6, "got {}", got);
        assert!(!r.hit_step_cap);
    }

    #[test]
    fn grid_edge_bounces_and_the_packet_fades_out() {
        // No tile at all: the packet ping-pongs between the edges, loses 5% per empty hex and is culled below the floor.
        let r = run(&[], 1, packet_at(0, 0, 0, 100.0));
        assert!(r.outs.captures.is_empty());
        assert!(!r.hit_step_cap);
        assert!(r.steps < STEP_CAP);
    }

    #[test]
    fn amplifier_scales_what_the_mount_receives() {
        let amp = TileDesc { kind: 1, amp_mult: 2.0, rarity: 0, ..TileDesc::default() };
        let plain = run(&[(1, mount())], 1, packet_at(0, 0, 0, 100.0)).outs.captures[0].1.magnitude;
        let boosted = run(&[(1, amp), (2, mount())], 2, packet_at(0, 0, 0, 100.0)).outs.captures[0].1.magnitude;
        assert!(boosted > plain * 1.5, "plain {} boosted {}", plain, boosted);
    }

    #[test]
    fn a_non_mythic_tile_caps_what_enters_and_flags_overload() {
        let r = run(&[(1, mount())], 1, packet_at(0, 0, 0, NORMAL_MAGNITUDE_CAP * 2.0));
        assert!(r.overload_peak[0] > NORMAL_MAGNITUDE_CAP);
        let first = r.outs.captures[0].1.magnitude;
        assert!(first <= NORMAL_MAGNITUDE_CAP + 1e-6, "entering was {}", first);
    }

    #[test]
    fn simulation_is_deterministic() {
        let a = run(&[(3, mount())], 3, packet_at(0, 0, 0, 500.0));
        let b = run(&[(3, mount())], 3, packet_at(0, 0, 0, 500.0));
        assert_eq!(a.outs.captures.len(), b.outs.captures.len());
        assert_eq!(a.outs.captures[0].1.magnitude, b.outs.captures[0].1.magnitude);
        assert_eq!(a.steps, b.steps);
    }
}
