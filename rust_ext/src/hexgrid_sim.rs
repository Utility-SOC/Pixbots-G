use godot::prelude::*;
use godot::classes::RefCounted;
use std::collections::HashMap;

type VDict = Dictionary<Variant, Variant>;

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
//   6 CATALYST      - (ungated, non-inverted) convert everything -> target
//   7 CORE          - redistribute incoming across active faces
//   8 MOUNT_SINK    - Weapon Mount capture; optional range_mult (Sniper)
//   9 LINK_SINK     - Component Link with target slot: transfer capture
//  10 LINK_ROUTER   - Energy Intake/Accessory Return: split across faces
//  11 STORE_SINK    - HealBeacon/Jammer/DroneBay/Cloak: bank mag * coef
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

const SYN_COUNT: usize = 10;
const MAX_MAGNITUDE: f64 = 600000.0;
const NORMAL_MAGNITUDE_CAP: f64 = 150000.0;
const MYTHIC_RARITY: i64 = 4;
const STEP_CAP: i64 = 1000;
const SYN_RAW: usize = 0;
const SYN_LIGHTNING: usize = 3;
const SYN_KINETIC: usize = 7;

#[derive(Clone)]
struct Packet {
    magnitude: f64,
    syn: [f64; SYN_COUNT],
    syn_present: [bool; SYN_COUNT],
    proc_syn: [f64; SYN_COUNT],
    proc_present: [bool; SYN_COUNT],
    dir: i64,
    q: i64,
    r: i64,
    steps: i64,
    active: bool,
    charge_required: f64,
    accumulator_quality: f64,
    aoe_bonus: f64,
    acc_charge_mult: f64,
    acc_damage_mult: f64,
    range_mult: f64,
    auto_dump_threshold: f64,
    trigger: i64, // 0 = "None", 1..3 = keys (EnergyPacket.trigger_key)
}

impl Packet {
    fn set_magnitude(&mut self, v: f64) {
        self.magnitude = v.min(MAX_MAGNITUDE);
    }

    fn syn_total(&self) -> f64 {
        self.syn.iter().sum()
    }

    fn sync_synergies(&mut self) {
        let total = self.syn_total();
        if total > self.magnitude * 1.0001 {
            let factor = self.magnitude / total;
            for v in self.syn.iter_mut() {
                *v *= factor;
            }
        }
    }

    fn add_synergy(&mut self, k: usize, amount: f64) {
        self.syn[k] += amount;
        self.syn_present[k] = true;
        self.set_magnitude(self.magnitude + amount);
        self.sync_synergies();
    }

    fn convert_synergy(&mut self, from: usize, to: usize, percentage: f64) {
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

    fn amplify(&mut self, mut multiplier: f64) {
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
    fn split(&mut self, ratio: f64) -> Packet {
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

    fn merge(&mut self, other: &Packet) {
        self.set_magnitude(self.magnitude + other.magnitude);
        self.accumulator_quality = self.accumulator_quality.min(other.accumulator_quality);
        self.aoe_bonus = self.aoe_bonus.max(other.aoe_bonus);
        self.acc_charge_mult = self.acc_charge_mult.max(other.acc_charge_mult);
        self.acc_damage_mult = self.acc_damage_mult.max(other.acc_damage_mult);
        self.range_mult = self.range_mult.max(other.range_mult);
        self.auto_dump_threshold = self.auto_dump_threshold.max(other.auto_dump_threshold);
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

    fn add_proc(&mut self, k: usize, strength: f64) {
        self.proc_syn[k] = self.proc_syn[k].max(strength);
        self.proc_present[k] = true;
    }

    // EnergyPacket.has_synergy(type) with the default 0.0 threshold.
    fn has_synergy(&self, k: usize) -> bool {
        if self.magnitude == 0.0 {
            return false;
        }
        self.syn_present[k] && self.syn[k] > 0.0
    }

    fn dominant_synergy(&self) -> i64 {
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
struct TileState {
    remnant: [f64; SYN_COUNT],
    remnant_present: [bool; SYN_COUNT],
    residue_syn: [i64; 3],
    residue_steps: [i64; 3],
    magnetic_power: f64,
    stored_energy: f64,
    stored_syn: [f64; SYN_COUNT],
    speed_bonus: f64,
}

struct TileDesc {
    kind: i64,
    rarity: i64,
    disabled: bool,
    sync_adjustment: i64,
    faces: Vec<i64>,
    weights: Vec<f64>,
    rotation: i64,
    amp_mult: f64,
    aoe_add: f64,
    pre_amp: f64,
    post_amp: f64,
    infuse_syn: usize,
    conv_rate: f64,
    infuse_amount: f64,
    catalyst_target: usize,
    catalyst_mult: f64,
    store_coef: f64,
    valve: bool,
    filter_allowed: usize,
    filter_raw_return: f64,
    magnet_lightning_mult: f64,
    actuator_base_mult: f64,
    actuator_kin_mult: f64,
    actuator_ltg_mult: f64,
    shield_mult: f64,
    acc_charge_div: f64,
    acc_damage: f64,
    acc_auto_dump: f64,
    acc_trigger: i64,
    acc_quality: f64,
    res_baseline_mult: f64,
    res_remnant_boost: f64,
    sync_dropoff: [i64; 3],
    range_mult_stamp: f64,
    mythic_remnants: bool,
    extra_cells: Vec<(i64, i64)>,
}

// HexCoord.get_directions(): E, SE, SW, W, NW, NE (axial q,r deltas).
const DIRS: [(i64, i64); 6] = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)];

fn neighbor(q: i64, r: i64, d: i64) -> (i64, i64) {
    let dd = DIRS[(d.rem_euclid(6)) as usize];
    (q + dd.0, r + dd.1)
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).map(|v| v.to::<i64>()).unwrap_or(0)
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).map(|v| v.to::<f64>()).unwrap_or(0.0)
}

fn get_f_or(d: &VDict, k: &str, default: f64) -> f64 {
    d.get(k).map(|v| v.to::<f64>()).unwrap_or(default)
}

fn get_b(d: &VDict, k: &str) -> bool {
    d.get(k).map(|v| v.to::<bool>()).unwrap_or(false)
}

fn get_f10(d: &VDict, k: &str) -> [f64; SYN_COUNT] {
    let mut out = [0.0; SYN_COUNT];
    if let Some(v) = d.get(k) {
        let arr = v.to::<PackedFloat64Array>();
        let s = arr.as_slice();
        for i in 0..SYN_COUNT.min(s.len()) {
            out[i] = s[i];
        }
    }
    out
}

fn get_b10(d: &VDict, k: &str) -> [bool; SYN_COUNT] {
    let mut out = [false; SYN_COUNT];
    if let Some(v) = d.get(k) {
        let arr = v.to::<PackedInt32Array>();
        let s = arr.as_slice();
        for i in 0..SYN_COUNT.min(s.len()) {
            out[i] = s[i] != 0;
        }
    }
    out
}

fn parse_tile(d: &VDict) -> (TileDesc, TileState) {
    let mut faces = Vec::new();
    let mut weights = Vec::new();
    if let Some(v) = d.get("faces") {
        let arr = v.to::<PackedInt32Array>();
        for f in arr.as_slice() {
            faces.push(*f as i64);
        }
    }
    if let Some(v) = d.get("weights") {
        let arr = v.to::<PackedFloat64Array>();
        for w in arr.as_slice() {
            weights.push(*w);
        }
    }
    let mut extra_cells = Vec::new();
    if let Some(v) = d.get("extra_cells") {
        let arr = v.to::<PackedInt32Array>();
        let s = arr.as_slice();
        let mut i = 0;
        while i + 1 < s.len() {
            extra_cells.push((s[i] as i64, s[i + 1] as i64));
            i += 2;
        }
    }
    let mut sync_dropoff = [3i64; 3];
    if let Some(v) = d.get("sync_dropoff") {
        let arr = v.to::<PackedInt32Array>();
        let s = arr.as_slice();
        for i in 0..3.min(s.len()) {
            sync_dropoff[i] = s[i] as i64;
        }
    }

    let desc = TileDesc {
        kind: get_i(d, "kind"),
        rarity: get_i(d, "rarity"),
        disabled: get_b(d, "disabled"),
        sync_adjustment: get_i(d, "sync_adjustment"),
        faces,
        weights,
        rotation: get_i(d, "rotation"),
        amp_mult: get_f_or(d, "amp_mult", 1.0),
        aoe_add: get_f(d, "aoe_add"),
        pre_amp: get_f_or(d, "pre_amp", 1.0),
        post_amp: get_f_or(d, "post_amp", 1.0),
        infuse_syn: get_i(d, "infuse_syn") as usize,
        conv_rate: get_f(d, "conv_rate"),
        infuse_amount: get_f(d, "infuse_amount"),
        catalyst_target: get_i(d, "catalyst_target") as usize,
        catalyst_mult: get_f(d, "catalyst_mult"),
        store_coef: get_f_or(d, "store_coef", 1.0),
        valve: get_b(d, "valve"),
        filter_allowed: get_i(d, "filter_allowed") as usize,
        filter_raw_return: get_f(d, "filter_raw_return"),
        magnet_lightning_mult: get_f_or(d, "magnet_lightning_mult", 1.5),
        actuator_base_mult: get_f(d, "actuator_base_mult"),
        actuator_kin_mult: get_f_or(d, "actuator_kin_mult", 1.5),
        actuator_ltg_mult: get_f_or(d, "actuator_ltg_mult", 2.0),
        shield_mult: get_f_or(d, "shield_mult", 1.0),
        acc_charge_div: get_f_or(d, "acc_charge_div", 1.0),
        acc_damage: get_f_or(d, "acc_damage", 1.0),
        acc_auto_dump: get_f(d, "acc_auto_dump"),
        acc_trigger: get_i(d, "acc_trigger"),
        acc_quality: get_f_or(d, "acc_quality", 1.0),
        res_baseline_mult: get_f_or(d, "res_baseline_mult", 1.0),
        res_remnant_boost: get_f(d, "res_remnant_boost"),
        sync_dropoff,
        range_mult_stamp: get_f_or(d, "range_mult_stamp", 1.0),
        mythic_remnants: get_b(d, "mythic_remnants"),
        extra_cells,
    };

    let mut state = TileState::default();
    state.remnant = get_f10(d, "remnant");
    state.remnant_present = get_b10(d, "remnant_present");
    state.magnetic_power = get_f(d, "magnetic_power");
    if let Some(v) = d.get("residue_syn") {
        let arr = v.to::<PackedInt32Array>();
        let s = arr.as_slice();
        for i in 0..3.min(s.len()) {
            state.residue_syn[i] = s[i] as i64;
        }
    } else {
        state.residue_syn = [-1; 3];
    }
    if let Some(v) = d.get("residue_steps") {
        let arr = v.to::<PackedInt32Array>();
        let s = arr.as_slice();
        for i in 0..3.min(s.len()) {
            state.residue_steps[i] = s[i] as i64;
        }
    }
    (desc, state)
}

fn parse_packet(d: &VDict) -> Packet {
    Packet {
        magnitude: get_f(d, "magnitude").min(MAX_MAGNITUDE),
        syn: get_f10(d, "syn"),
        syn_present: get_b10(d, "syn_present"),
        proc_syn: get_f10(d, "proc"),
        proc_present: get_b10(d, "proc_present"),
        dir: get_i(d, "dir"),
        q: get_i(d, "q"),
        r: get_i(d, "r"),
        steps: get_i(d, "steps"),
        active: true,
        charge_required: get_f(d, "charge_required"),
        accumulator_quality: get_f_or(d, "accumulator_quality", 1.0),
        aoe_bonus: get_f(d, "aoe_bonus"),
        acc_charge_mult: get_f_or(d, "acc_charge_mult", 1.0),
        acc_damage_mult: get_f_or(d, "acc_damage_mult", 1.0),
        range_mult: get_f_or(d, "range_mult", 1.0),
        auto_dump_threshold: get_f(d, "auto_dump_threshold"),
        trigger: get_i(d, "trigger"),
    }
}

fn f10_to_packed(v: &[f64; SYN_COUNT]) -> PackedFloat64Array {
    let mut out = PackedFloat64Array::new();
    for x in v {
        out.push(*x);
    }
    out
}

fn b10_to_packed(v: &[bool; SYN_COUNT]) -> PackedInt32Array {
    let mut out = PackedInt32Array::new();
    for x in v {
        out.push(if *x { 1 } else { 0 });
    }
    out
}

fn packet_to_dict(p: &Packet) -> VDict {
    let mut d: VDict = Dictionary::new();
    let syn = f10_to_packed(&p.syn);
    let present = b10_to_packed(&p.syn_present);
    let proc_v = f10_to_packed(&p.proc_syn);
    let proc_p = b10_to_packed(&p.proc_present);
    let _ = d.insert("magnitude", p.magnitude);
    let _ = d.insert("syn", &syn);
    let _ = d.insert("syn_present", &present);
    let _ = d.insert("proc", &proc_v);
    let _ = d.insert("proc_present", &proc_p);
    let _ = d.insert("steps", p.steps);
    let _ = d.insert("charge_required", p.charge_required);
    let _ = d.insert("accumulator_quality", p.accumulator_quality);
    let _ = d.insert("aoe_bonus", p.aoe_bonus);
    let _ = d.insert("acc_charge_mult", p.acc_charge_mult);
    let _ = d.insert("acc_damage_mult", p.acc_damage_mult);
    let _ = d.insert("range_mult", p.range_mult);
    let _ = d.insert("auto_dump_threshold", p.auto_dump_threshold);
    let _ = d.insert("trigger", p.trigger);
    d
}

struct SimOutputs {
    captures: Vec<(usize, Packet, i64)>,
    stores: Vec<(usize, f64)>,
    mech_merges: Vec<(usize, Packet)>,
    lance_hits: Vec<(usize, i64, i64, Packet)>,
    conduit_dominant: HashMap<usize, i64>,
}

// Non-Mythic Resonator baseline, shared by RESONATOR and the Resonator
// stage of PRIME_CIRCUIT. Mirrors ResonatorTile.process_energy exactly.
fn resonator_baseline(p: &mut Packet, tile: &TileDesc, state: &mut TileState) {
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
fn process_energy(
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
            let mut cell_idx: i64 = 0;
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
        _ => vec![p],
    }
}

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct HexGridSim {
    _base: Base<RefCounted>,
}

#[godot_api]
impl HexGridSim {
    #[func]
    fn is_implemented(&self) -> bool {
        true
    }

    /// Full-coverage grid simulation - see the module header for the kind
    /// table and RustGridSim.gd for the bridge contract.
    #[func]
    fn simulate_grid(
        &self,
        tiles: Array<Variant>,
        valid_cells: PackedInt32Array,
        packets: Array<Variant>,
    ) -> VDict {
        let mut descs: Vec<TileDesc> = Vec::new();
        let mut states: Vec<TileState> = Vec::new();
        let mut anchors: Vec<(i64, i64)> = Vec::new();
        let mut grid: HashMap<(i64, i64), usize> = HashMap::new();
        for (idx, v) in tiles.iter_shared().enumerate() {
            let d = v.to::<VDict>();
            let q = get_i(&d, "q");
            let r = get_i(&d, "r");
            let (desc, state) = parse_tile(&d);
            grid.insert((q, r), idx);
            for off in &desc.extra_cells {
                grid.insert((q + off.0, r + off.1), idx);
            }
            anchors.push((q, r));
            descs.push(desc);
            states.push(state);
        }

        let mut valid: HashMap<(i64, i64), bool> = HashMap::new();
        let vc = valid_cells.as_slice();
        let mut i = 0;
        while i + 1 < vc.len() {
            valid.insert((vc[i] as i64, vc[i + 1] as i64), true);
            i += 2;
        }

        let mut active: Vec<Packet> = Vec::new();
        for v in packets.iter_shared() {
            active.push(parse_packet(&v.to::<VDict>()));
        }

        let mut outs = SimOutputs {
            captures: Vec::new(),
            stores: Vec::new(),
            mech_merges: Vec::new(),
            lance_hits: Vec::new(),
            conduit_dominant: HashMap::new(),
        };

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
                        entering = p.split(NORMAL_MAGNITUDE_CAP / p.magnitude);
                        entering.steps = p.steps;
                        p.dir = (dir + 3).rem_euclid(6);
                        next.push(p.clone());
                    }

                    let entry = (dir + 3).rem_euclid(6);
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
        }

        let mut out_captures = Array::<Variant>::new();
        for (tidx, p, step) in &outs.captures {
            let mut d: VDict = Dictionary::new();
            let _ = d.insert("tile", *tidx as i64);
            let _ = d.insert("step", *step);
            let packet_dict = packet_to_dict(p);
            let _ = d.insert("packet", &packet_dict);
            out_captures.push(&d.to_variant());
        }
        let mut out_stores = Array::<Variant>::new();
        for (tidx, amount) in &outs.stores {
            let mut d: VDict = Dictionary::new();
            let _ = d.insert("tile", *tidx as i64);
            let _ = d.insert("amount", *amount);
            out_stores.push(&d.to_variant());
        }
        let mut out_merges = Array::<Variant>::new();
        for (tidx, p) in &outs.mech_merges {
            let mut d: VDict = Dictionary::new();
            let _ = d.insert("tile", *tidx as i64);
            let packet_dict = packet_to_dict(p);
            let _ = d.insert("packet", &packet_dict);
            out_merges.push(&d.to_variant());
        }
        let mut out_lance = Array::<Variant>::new();
        for (tidx, cell_idx, entry_dir, p) in &outs.lance_hits {
            let mut d: VDict = Dictionary::new();
            let _ = d.insert("tile", *tidx as i64);
            let _ = d.insert("cell", *cell_idx);
            let _ = d.insert("entry", *entry_dir);
            let packet_dict = packet_to_dict(p);
            let _ = d.insert("packet", &packet_dict);
            out_lance.push(&d.to_variant());
        }
        let mut out_dominant: VDict = Dictionary::new();
        for (tidx, syn) in &outs.conduit_dominant {
            let _ = out_dominant.insert(*tidx as i64, *syn);
        }
        let mut out_states = Array::<Variant>::new();
        for (idx, st) in states.iter().enumerate() {
            let mut d: VDict = Dictionary::new();
            let _ = d.insert("tile", idx as i64);
            let remnant = f10_to_packed(&st.remnant);
            let remnant_p = b10_to_packed(&st.remnant_present);
            let stored_syn = f10_to_packed(&st.stored_syn);
            let mut residue_syn = PackedInt32Array::new();
            let mut residue_steps = PackedInt32Array::new();
            for i in 0..3 {
                residue_syn.push(st.residue_syn[i] as i32);
                residue_steps.push(st.residue_steps[i] as i32);
            }
            let _ = d.insert("remnant", &remnant);
            let _ = d.insert("remnant_present", &remnant_p);
            let _ = d.insert("magnetic_power", st.magnetic_power);
            let _ = d.insert("stored_energy", st.stored_energy);
            let _ = d.insert("stored_syn", &stored_syn);
            let _ = d.insert("speed_bonus", st.speed_bonus);
            let _ = d.insert("residue_syn", &residue_syn);
            let _ = d.insert("residue_steps", &residue_steps);
            out_states.push(&d.to_variant());
        }

        let mut result: VDict = Dictionary::new();
        let _ = result.insert("captures", &out_captures);
        let _ = result.insert("stores", &out_stores);
        let _ = result.insert("mech_merges", &out_merges);
        let _ = result.insert("lance_hits", &out_lance);
        let _ = result.insert("conduit_dominant", &out_dominant);
        let _ = result.insert("tile_states", &out_states);
        result
    }
}
