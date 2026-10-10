use godot::prelude::*;
use godot::classes::RefCounted;
use pixbots_core::hexgrid_sim::*;
use std::collections::HashMap;

type VDict = Dictionary<Variant, Variant>;

// All six helpers use try_to().ok() rather than to() - a modded/edited
// tile or a bridge/schema drift can hand us a key with the wrong Variant
// type, and to() panics on a conversion failure, which takes down the
// whole Godot process rather than just that one tile's stat. try_to()
// turns a bad type into "missing", falling back to the same default a
// truly-absent key would get.
fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

fn get_f_or(d: &VDict, k: &str, default: f64) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(default)
}

fn get_b(d: &VDict, k: &str) -> bool {
    d.get(k).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false)
}

fn get_f10(d: &VDict, k: &str) -> [f64; SYN_COUNT] {
    let mut out = [0.0; SYN_COUNT];
    if let Some(arr) = d.get(k).and_then(|v| v.try_to::<PackedFloat64Array>().ok()) {
        let s = arr.as_slice();
        for i in 0..SYN_COUNT.min(s.len()) {
            out[i] = s[i];
        }
    }
    out
}

fn get_b10(d: &VDict, k: &str) -> [bool; SYN_COUNT] {
    let mut out = [false; SYN_COUNT];
    if let Some(arr) = d.get(k).and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
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
    if let Some(arr) = d.get("faces").and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
        for f in arr.as_slice() {
            faces.push(*f as i64);
        }
    }
    if let Some(arr) = d.get("weights").and_then(|v| v.try_to::<PackedFloat64Array>().ok()) {
        for w in arr.as_slice() {
            weights.push(*w);
        }
    }
    // A SPLITTER whose weights don't cover faces.len()-1 entries (mismatched
    // dict from a modded/edited tile, or bridge drift) used to index
    // tile.weights[i] out of bounds and panic mid-simulation. Fall back to
    // an even split across all faces instead of crashing the whole process.
    if !faces.is_empty() && weights.len() < faces.len().saturating_sub(1) {
        weights = vec![1.0; faces.len()];
    }
    let mut extra_cells = Vec::new();
    if let Some(arr) = d.get("extra_cells").and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
        let s = arr.as_slice();
        let mut i = 0;
        while i + 1 < s.len() {
            extra_cells.push((s[i] as i64, s[i + 1] as i64));
            i += 2;
        }
    }
    let mut sync_dropoff = [3i64; 3];
    if let Some(arr) = d.get("sync_dropoff").and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
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
        gate_min_magnitude: get_f(d, "gate_min_magnitude"),
        gate_every_n: get_i(d, "gate_every_n"),
        inverted: get_b(d, "inverted"),
    };

    let mut state = TileState::default();
    state.remnant = get_f10(d, "remnant");
    state.remnant_present = get_b10(d, "remnant_present");
    state.magnetic_power = get_f(d, "magnetic_power");
    state.gate_counter = get_i(d, "gate_counter");
    if let Some(arr) = d.get("residue_syn").and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
        let s = arr.as_slice();
        for i in 0..3.min(s.len()) {
            state.residue_syn[i] = s[i] as i64;
        }
    } else {
        state.residue_syn = [-1; 3];
    }
    if let Some(arr) = d.get("residue_steps").and_then(|v| v.try_to::<PackedInt32Array>().ok()) {
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
        reflected: false,
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
        let t_start = std::time::Instant::now();
        let mut descs: Vec<TileDesc> = Vec::new();
        let mut states: Vec<TileState> = Vec::new();
        let mut anchors: Vec<(i64, i64)> = Vec::new();
        let mut grid: HashMap<(i64, i64), usize> = HashMap::new();
        for (idx, v) in tiles.iter_shared().enumerate() {
            let d = v.try_to::<VDict>().unwrap_or_default();
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
            active.push(parse_packet(&v.try_to::<VDict>().unwrap_or_default()));
        }

        let t_parsed = t_start.elapsed().as_micros() as i64;
        let sim = simulate(&descs, &mut states, &anchors, &grid, &valid, active);
        let SimResult { outs, flow_visits, flow_energy, flow_syn, entry_steps, overload_peak, hit_step_cap, steps } = sim;
        let t_simmed = t_start.elapsed().as_micros() as i64;
        // Captures are the bulk of the result (~100 per sim), so they are
        // returned as one flat array (stride CAPTURE_STRIDE) instead of a
        // Dictionary + 4 packed arrays each. Layout: tile, step, then
        // magnitude, syn[10], syn_present[10], proc[10], proc_present[10],
        // steps, charge_required, accumulator_quality, aoe_bonus,
        // acc_charge_mult, acc_damage_mult, range_mult, auto_dump_threshold,
        // trigger. Mirrored by RustGridSim._decode_captures.
        let mut cap_flat: Vec<f64> = Vec::with_capacity(outs.captures.len() * CAPTURE_STRIDE);
        for (tidx, p, step) in &outs.captures {
            cap_flat.push(*tidx as f64);
            cap_flat.push(*step as f64);
            cap_flat.push(p.magnitude);
            cap_flat.extend_from_slice(&p.syn);
            for b in &p.syn_present {
                cap_flat.push(if *b { 1.0 } else { 0.0 });
            }
            cap_flat.extend_from_slice(&p.proc_syn);
            for b in &p.proc_present {
                cap_flat.push(if *b { 1.0 } else { 0.0 });
            }
            cap_flat.push(p.steps as f64);
            cap_flat.push(p.charge_required);
            cap_flat.push(p.accumulator_quality);
            cap_flat.push(p.aoe_bonus);
            cap_flat.push(p.acc_charge_mult);
            cap_flat.push(p.acc_damage_mult);
            cap_flat.push(p.range_mult);
            cap_flat.push(p.auto_dump_threshold);
            cap_flat.push(p.trigger as f64);
        }
        let out_captures = PackedFloat64Array::from(cap_flat.as_slice());
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
            let _ = d.insert("gate_counter", st.gate_counter);
            out_states.push(&d.to_variant());
        }

        // tile_flow: stride 4 per tile = visits, energy, dominant synergy (-1
        // if none), loop flag (1 if some entry face was used on
        // LOOP_ENTRY_STEPS+ steps).
        let mut flow_flat: Vec<f64> = Vec::with_capacity(descs.len() * 4);
        for i in 0..descs.len() {
            let mut dom: i64 = -1;
            let mut best = 0.0f64;
            for k in 0..SYN_COUNT {
                if flow_syn[i][k] > best {
                    best = flow_syn[i][k];
                    dom = k as i64;
                }
            }
            let looped = entry_steps[i].iter().any(|&n| n >= LOOP_ENTRY_STEPS);
            flow_flat.push(flow_visits[i]);
            flow_flat.push(flow_energy[i]);
            flow_flat.push(dom as f64);
            flow_flat.push(if looped { 1.0 } else { 0.0 });
        }

        let mut result: VDict = Dictionary::new();
        let _ = result.insert("tile_overload", &PackedFloat64Array::from(overload_peak.as_slice()));
        let _ = result.insert("tile_flow", &PackedFloat64Array::from(flow_flat.as_slice()));
        let _ = result.insert("hit_step_cap", hit_step_cap);
        let _ = result.insert("capture_flat", &out_captures);
        let _ = result.insert("stores", &out_stores);
        let _ = result.insert("mech_merges", &out_merges);
        let _ = result.insert("lance_hits", &out_lance);
        let _ = result.insert("conduit_dominant", &out_dominant);
        let _ = result.insert("tile_states", &out_states);
        let _ = result.insert("t_parse_us", t_parsed);
        let _ = result.insert("t_sim_us", t_simmed - t_parsed);
        let _ = result.insert("t_out_us", t_start.elapsed().as_micros() as i64 - t_simmed);
        let _ = result.insert("steps", steps);
        result
    }
}
