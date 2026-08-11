use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::collections::HashSet;

type VDict = Dictionary<Variant, Variant>;

#[derive(Copy, Clone, PartialEq, Eq, Hash)]
struct HexCoord {
    q: i32,
    r: i32,
}

const DIRECTIONS: [HexCoord; 6] = [
    HexCoord { q: 1, r: 0 },
    HexCoord { q: 0, r: 1 },
    HexCoord { q: -1, r: 1 },
    HexCoord { q: -1, r: 0 },
    HexCoord { q: 0, r: -1 },
    HexCoord { q: 1, r: -1 },
];

impl HexCoord {
    fn neighbor(&self, dir: usize) -> HexCoord {
        let d = DIRECTIONS[dir % 6];
        HexCoord { q: self.q + d.q, r: self.r + d.r }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProceduralShapeGen {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for ProceduralShapeGen {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl ProceduralShapeGen {
    #[func]
    fn generate_shape(&self, slot_type: i64, rarity: i64, role_variant: GString, grid_width: i64, grid_height: i64) -> Array<Variant> {
        let mut valid_hexes: Vec<HexCoord> = Vec::new();
        let mut valid_hex_set: HashSet<HexCoord> = HashSet::new();

        let hex_budget = [10, 18, 28, 48, 72, 100];
        let mut budget_tier = rarity.clamp(0, 4) as usize;
        // HexTile.BodySlot.TORSO == 1
        if slot_type == 1 {
            budget_tier += 1;
        }
        let base_count = hex_budget[budget_tier];
        let role = role_variant.to_string();

        match slot_type {
            6 => { // HEAD = 6
                let mut head_len = 3;
                if rarity >= 1 { head_len = 4; } // UNCOMMON
                if rarity >= 2 { head_len = 5; } // RARE
                if rarity >= 3 { head_len = 6; } // LEGENDARY
                
                for i in 0..head_len {
                    let q = i / 2;
                    valid_hexes.push(HexCoord { q, r: -i });
                }
                
                if rarity >= 1 {
                    for i in 1..head_len {
                        let q = i / 2;
                        valid_hexes.push(HexCoord { q: q - 1, r: -i });
                        valid_hexes.push(HexCoord { q: q + 1, r: -i });
                    }
                }
                
                if rarity >= 3 {
                    for i in 1..(head_len - 1) {
                        let q = i / 2;
                        valid_hexes.push(HexCoord { q: q - 2, r: -i });
                        valid_hexes.push(HexCoord { q: q + 2, r: -i });
                    }
                }
            }
            7 => { // BACKPACK = 7
                let mut pack_width = 3;
                let mut pack_height = 2;
                if rarity >= 1 { pack_width = 4; pack_height = 3; }
                if rarity >= 2 { pack_width = 5; pack_height = 4; }
                if rarity >= 3 { pack_width = 7; pack_height = 5; }
                
                for q in -(pack_width / 2)..=(pack_width / 2) {
                    for r in -(pack_height / 2)..=(pack_height / 2) {
                        valid_hexes.push(HexCoord { q, r });
                    }
                }
            }
            1 => { // TORSO = 1
                valid_hexes.push(HexCoord { q: 0, r: 0 });
                valid_hex_set.insert(HexCoord { q: 0, r: 0 });

                // Class-constrained torso shapes (design doc, 2026-08-10):
                // silhouette should communicate class, but the core's full
                // 6-neighbor hub is a hard, non-negotiable constraint - an
                // earlier "thin the torso per role" attempt got reverted
                // because it left a Splitter in the hub with nowhere to fan
                // power out to. Role identity lives entirely in how the
                // shape grows OUTWARD from that guaranteed hub, gated by
                // the same base_count budget every rarity tier already
                // uses. Every role not listed below keeps the exact
                // original disc-growth behavior, hub-guarantee included -
                // this only ADDS new branches, never changes the default.
                match role.as_str() {
                    "scout" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_scout_spine(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "sniper" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_sniper_mast(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "brawler" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_brawler_slab(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "ambusher" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_ambusher_hook(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    _ => {
                        let mut radius: i32 = 1;
                        while valid_hexes.len() < base_count {
                            for q in -radius..=radius {
                                for r in -radius..=radius {
                                    if valid_hexes.len() >= base_count { break; }
                                    if (q + r).abs() <= radius {
                                        let h = HexCoord { q, r };
                                        let h_sym = HexCoord { q: -q - r, r };

                                        if !valid_hex_set.contains(&h) {
                                            valid_hexes.push(h);
                                            valid_hex_set.insert(h);
                                        }

                                        if valid_hexes.len() < base_count {
                                            if !valid_hex_set.contains(&h_sym) {
                                                valid_hexes.push(h_sym);
                                                valid_hex_set.insert(h_sym);
                                            }
                                        }
                                    }
                                }
                            }
                            radius += 1;
                        }
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                }
            }
            2 | 3 => { // ARM_L = 2, ARM_R = 3
                let dir_q = if slot_type == 2 { -1 } else { 1 };
                let mut width = if rarity <= 1 { 2 } else { 3 };
                
                if role == "scout" { width = 1; }
                if role == "brawler" { width = if rarity <= 1 { 3 } else { 4 }; }
                
                let mut length = base_count as i32 / width;
                
                if role == "sniper" && slot_type == 3 {
                    width = 1;
                    length = base_count as i32;
                }
                
                for l in 0..length {
                    for w in 0..width {
                        if valid_hexes.len() >= base_count { break; }
                        valid_hexes.push(HexCoord { q: dir_q * l, r: w - width / 2 });
                    }
                }
            }
            4 | 5 => { // LEG_L = 4, LEG_R = 5
                let mut width = if rarity <= 1 { 3 } else { 4 };
                
                if role == "scout" { width = 2; }
                if role == "brawler" { width = if rarity <= 1 { 4 } else { 5 }; }
                
                let length = base_count as i32 / width;
                for l in 0..length {
                    let mut tilt = l / 2;
                    if role == "scout" { tilt = l; }
                    let shift = -tilt;
                    for w in 0..width {
                        if valid_hexes.len() >= base_count { break; }
                        valid_hexes.push(HexCoord { q: w - width / 2 + shift, r: l });
                    }
                }
            }
            _ => { // Fallback generic shape
                for q in 0..grid_width as i32 {
                    for r in 0..grid_height as i32 {
                        valid_hexes.push(HexCoord { q, r });
                    }
                }
            }
        }
        
        let mut ret = Array::new();
        // Since other logic bulk appends without modifying valid_hex_set, we'll
        // just use the final `valid_hexes` to build the result.
        for h in valid_hexes {
            let mut dict = VDict::new();
            dict.set("q", h.q);
            dict.set("r", h.r);
            ret.push(&dict.to_variant());
        }
        ret
    }

    #[func]
    fn generate_procedural_shape(&self, slot_type: i64, rarity: i64, role_variant: GString, seed: i64) -> Array<Variant> {
        let mut valid_hexes: Vec<HexCoord> = Vec::new();
        let mut valid_hex_set: HashSet<HexCoord> = HashSet::new();

        let hex_budget = [10, 18, 28, 48, 72, 100];
        let mut budget_tier = rarity.clamp(0, 4) as usize;
        if slot_type == 1 { // TORSO
            budget_tier += 1;
        }
        let base_count = hex_budget[budget_tier];

        let start = HexCoord { q: 0, r: 0 };
        valid_hexes.push(start);
        valid_hex_set.insert(start);

        let mut rng = godot::classes::RandomNumberGenerator::new_gd();
        rng.set_seed(seed as u64);

        let mut role = role_variant.to_string();
        if role.is_empty() {
            let roles = ["ambusher", "brawler", "sniper", "jammer"];
            role = roles[(rng.randi() as usize) % roles.len()].to_string();
        }

        let weights = Self::get_archetype_weights(&role);
        
        let num_primitives = match rarity {
            0 => 1,
            1 => 2,
            2 => 3,
            3 | 4 => 4,
            _ => 1,
        };

        let mut remaining = base_count - 1;
        let mut p = 0;
        let mut stall_guard = num_primitives * 8;
        
        while remaining > 0 && stall_guard > 0 {
            stall_guard -= 1;
            let slots_left = std::cmp::max(1, num_primitives - p);
            let budget = std::cmp::max(2, (remaining as f64 / slots_left as f64).ceil() as i32);
            let attach = valid_hexes[(rng.randi() as usize) % valid_hexes.len()];
            let archetype = Self::pick_weighted_archetype(&weights, &mut rng);
            let added = Self::grow_primitive(&mut valid_hexes, &mut valid_hex_set, attach, &archetype, budget, &mut rng);
            remaining -= added;
            p += 1;
        }
        
        let mut ret = Array::new();
        for h in &valid_hexes {
            let mut dict = VDict::new();
            dict.set("q", h.q);
            dict.set("r", h.r);
            ret.push(&dict.to_variant());
        }
        ret
    }

    fn get_archetype_weights(role: &str) -> Vec<(&'static str, f64)> {
        match role {
            "sniper" | "scout" => vec![("line", 0.6), ("hook", 0.15), ("block", 0.25)],
            "brawler" => vec![("line", 0.15), ("hook", 0.15), ("block", 0.7)],
            "ambusher" => vec![("line", 0.15), ("hook", 0.6), ("block", 0.25)],
            "jammer" | "support" => vec![("line", 0.3), ("hook", 0.2), ("block", 0.5)],
            _ => vec![("line", 0.33), ("hook", 0.33), ("block", 0.34)],
        }
    }

    fn pick_weighted_archetype(weights: &[(&'static str, f64)], rng: &mut Gd<godot::classes::RandomNumberGenerator>) -> String {
        let total: f64 = weights.iter().map(|(_, w)| w).sum();
        let roll = (rng.randf() as f64) * total;
        let mut acc = 0.0;
        for (key, w) in weights {
            acc += w;
            if roll <= acc {
                return key.to_string();
            }
        }
        "block".to_string()
    }

    // --- Class-constrained torso shape helpers (design doc, 2026-08-10) ---
    // See generate_shape()'s TORSO branch for the full rationale. All five
    // mirror ComponentEquipment.gd's GDScript fallback exactly (same
    // direction indices, same thresholds) so the Rust/GDScript parity
    // check (ProceduralShapeParityCheck.gd) stays green.

    fn guarantee_torso_hub(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>) {
        for d in 0..6 {
            let n = HexCoord { q: 0, r: 0 }.neighbor(d);
            if !valid_hex_set.contains(&n) {
                valid_hexes.push(n);
                valid_hex_set.insert(n);
            }
        }
    }

    fn try_add_torso_hex(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, h: HexCoord) -> bool {
        if valid_hex_set.contains(&h) {
            return false;
        }
        valid_hexes.push(h);
        valid_hex_set.insert(h);
        true
    }

    // Scout: vertical spine (NW), with a lateral "rung" pair every 2
    // segments once budget allows - the T-branch the design started from:
    // a torso limited to a single line has no branch point to fan power
    // out past 3 tiles, so rungs are what unlock real capacity as rarity
    // climbs.
    fn grow_scout_spine(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize) {
        let mut tip = HexCoord { q: 0, r: -1 }; // already in the hub - spine's start
        let mut segment = 0;
        while valid_hexes.len() < base_count {
            tip = tip.neighbor(4); // NW
            if !Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip) {
                break;
            }
            segment += 1;
            if segment % 2 == 0 && valid_hexes.len() < base_count {
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip.neighbor(3)); // W rung
                if valid_hexes.len() < base_count {
                    Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip.neighbor(0)); // E rung
                }
            }
        }
    }

    // Sniper: straight single-file mast, no branching at all - the most
    // extreme "one dominant axis" read in the roster, echoing the
    // existing extra-long right-arm rifle identity.
    fn grow_sniper_mast(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize) {
        let mut tip = HexCoord { q: 0, r: -1 };
        while valid_hexes.len() < base_count {
            tip = tip.neighbor(4); // NW
            if !Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip) {
                break;
            }
        }
    }

    // Brawler: wide horizontal slab - alternates extending left/right
    // from the hub's own W/E hexes, thickening upward every third
    // addition so it reads as a broad block, not a thin bar.
    fn grow_brawler_slab(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize) {
        let mut right_tip = HexCoord { q: 1, r: 0 };
        let mut left_tip = HexCoord { q: -1, r: 0 };
        let mut toggle_right = true;
        while valid_hexes.len() < base_count {
            let tip = if toggle_right {
                right_tip = right_tip.neighbor(0); // E
                right_tip
            } else {
                left_tip = left_tip.neighbor(3); // W
                left_tip
            };
            let added = Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip);
            toggle_right = !toggle_right;
            if !added {
                continue;
            }
            if valid_hexes.len() % 3 == 0 && valid_hexes.len() < base_count {
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip.neighbor(5)); // thicken (NE)
            }
        }
    }

    // Ambusher: diagonal spike (NE), then hooks flat (E) partway through -
    // the same "hook" primitive already used for Ambusher's procedural
    // loot shapes, applied to the deterministic starter torso too.
    fn grow_ambusher_hook(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize) {
        let mut tip = HexCoord { q: 1, r: -1 }; // already in the hub - spike's start
        let phase_len = std::cmp::max(2, base_count / 6);
        let mut i = 0;
        while valid_hexes.len() < base_count {
            tip = tip.neighbor(if i < phase_len { 5 } else { 0 }); // NE then E
            if !Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip) {
                break;
            }
            i += 1;
        }
    }

    fn try_add_hex(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, h: HexCoord) -> bool {
        if h.q.abs() > 12 || h.r.abs() > 12 {
            return false;
        }
        if valid_hex_set.contains(&h) {
            return false;
        }
        valid_hexes.push(h);
        valid_hex_set.insert(h);
        true
    }

    fn grow_primitive(
        valid_hexes: &mut Vec<HexCoord>,
        valid_hex_set: &mut HashSet<HexCoord>,
        attach: HexCoord,
        archetype: &str,
        budget: i32,
        rng: &mut Gd<godot::classes::RandomNumberGenerator>
    ) -> i32 {
        let mut added = 0;
        match archetype {
            "line" => {
                let dir = (rng.randi() % 6) as usize;
                let mut cur = attach;
                for _ in 0..budget {
                    cur = cur.neighbor(dir);
                    if Self::try_add_hex(valid_hexes, valid_hex_set, cur) {
                        added += 1;
                    }
                }
            }
            "hook" => {
                let dir = (rng.randi() % 6) as usize;
                let bend_at = std::cmp::max(1, (budget as f64 * (rng.randf_range(0.3f32, 0.6f32) as f64)) as i32);
                let mut cur = attach;
                for _ in 0..bend_at {
                    cur = cur.neighbor(dir);
                    if Self::try_add_hex(valid_hexes, valid_hex_set, cur) {
                        added += 1;
                    }
                }
                let turn = if rng.randf() < 0.5f32 { 1 } else { -1 };
                let new_dir = (((dir as i32) + turn + 6) % 6) as usize;
                for _ in 0..(budget - bend_at) {
                    cur = cur.neighbor(new_dir);
                    if Self::try_add_hex(valid_hexes, valid_hex_set, cur) {
                        added += 1;
                    }
                }
            }
            "block" => {
                let mut frontier = vec![attach];
                let mut attempts = 0;
                while added < budget && !frontier.is_empty() && attempts < budget * 20 {
                    attempts += 1;
                    let idx = (rng.randi() as usize) % frontier.len();
                    let cell = frontier[idx];
                    let d = (rng.randi() % 6) as usize;
                    let n = cell.neighbor(d);
                    if Self::try_add_hex(valid_hexes, valid_hex_set, n) {
                        frontier.push(n);
                        added += 1;
                    } else if rng.randf() < 0.3 {
                        frontier.remove(idx);
                    }
                }
            }
            _ => {}
        }
        added
    }
}
