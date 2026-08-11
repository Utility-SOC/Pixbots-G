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
                // power out to. Two iterations before this one, both caught
                // by actually rendering the result: (1) a role-specific
                // spine/slab/spike grown WITHOUT any size cap - a Mythic
                // torso stretched into a 50+ hex diagonal staircase,
                // consuming the ENTIRE budget as it scaled. (2) capped at a
                // small FIXED size instead - but that sits well inside the
                // compact disc's OWN natural radius at Mythic (~100 hexes
                // reaches ~5-6 hexes out on its own), so the disc-fill
                // silently swallowed it and every role rendered
                // indistinguishable from the plain default. Fixed by
                // scaling the flourish's reach with budget_tier (via
                // seed_*_flourish's own TORSO_FLOURISH_LEN_BY_TIER) so it
                // always pokes a few hexes past wherever the disc would
                // reach on its own THIS tier - still bounded (~5-11 hexes
                // even at Mythic, a small fraction of the 100-hex total).
                // Every role not listed below keeps the exact original
                // disc-growth behavior, hub-guarantee included - this only
                // ADDS new branches, never changes the default.
                match role.as_str() {
                    "scout" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::seed_scout_flourish(&mut valid_hexes, &mut valid_hex_set, budget_tier);
                        Self::grow_default_disc(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "sniper" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::seed_sniper_flourish(&mut valid_hexes, &mut valid_hex_set, budget_tier);
                        Self::grow_default_disc(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "brawler" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::seed_brawler_flourish(&mut valid_hexes, &mut valid_hex_set, budget_tier);
                        Self::grow_default_disc(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    "ambusher" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::seed_ambusher_flourish(&mut valid_hexes, &mut valid_hex_set, budget_tier);
                        Self::grow_default_disc(&mut valid_hexes, &mut valid_hex_set, base_count);
                    }
                    _ => {
                        Self::grow_default_disc(&mut valid_hexes, &mut valid_hex_set, base_count);
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

    // The exact original disc-growth algorithm, extracted verbatim so it
    // can be reused both as the unlisted-role default AND as the shared
    // "bulk fill" every role-specific flourish below falls through to
    // once its own small fixed-size identity marker is placed.
    // Already-taken cells are silently skipped (try_add_torso_hex's own
    // contains() check), so calling this after a flourish just fills in
    // whatever budget remains around it.
    fn grow_default_disc(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize) {
        let mut radius: i32 = 1;
        while valid_hexes.len() < base_count {
            for q in -radius..=radius {
                for r in -radius..=radius {
                    if valid_hexes.len() >= base_count { break; }
                    if (q + r).abs() <= radius {
                        let h = HexCoord { q, r };
                        let h_sym = HexCoord { q: -q - r, r };
                        Self::try_add_torso_hex(valid_hexes, valid_hex_set, h);
                        if valid_hexes.len() < base_count {
                            Self::try_add_torso_hex(valid_hexes, valid_hex_set, h_sym);
                        }
                    }
                }
            }
            radius += 1;
        }
    }

    // Reach (in hexes beyond the hub) each flourish grows to, indexed by
    // budget_tier (0-5, matching hex_budget's own tiers - torso always
    // uses tier 1-5 since it's base rarity + 1). Tracks the default
    // disc's OWN growth rate (~sqrt(base_count/3) hex-rings) plus a
    // constant so the flourish always pokes a few hexes past wherever
    // the disc would reach on its own THIS tier - a flat constant here
    // got silently swallowed by the disc at Mythic (confirmed by
    // actually rendering it), and an unbounded loop consumed the entire
    // budget as it scaled (confirmed the same way). This stays small
    // even at the top end (~9-11 hexes on a 100-hex Mythic budget).
    const TORSO_FLOURISH_LEN_BY_TIER: [usize; 6] = [5, 5, 6, 7, 8, 9];

    // Scout: vertical spine, with a lateral "rung" pair roughly halfway
    // up - the T-branch the design started from.
    fn seed_scout_flourish(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, budget_tier: usize) {
        let length = Self::TORSO_FLOURISH_LEN_BY_TIER[budget_tier.min(5)];
        let mut tip = HexCoord { q: 0, r: -1 }; // already in the hub - spine's start
        for i in 0..length {
            tip = tip.neighbor(4); // NW
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip);
            if i == length / 2 {
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip.neighbor(3)); // W rung
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip.neighbor(0)); // E rung
            }
        }
    }

    // Sniper: straight single-file mast, no branching at all, reaching
    // further than Scout's - the most extreme "one dominant axis" read
    // in the roster, echoing the existing extra-long right-arm rifle
    // identity.
    fn seed_sniper_flourish(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, budget_tier: usize) {
        let length = Self::TORSO_FLOURISH_LEN_BY_TIER[budget_tier.min(5)] + 2;
        let mut tip = HexCoord { q: 0, r: -1 };
        for _ in 0..length {
            tip = tip.neighbor(4); // NW
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip);
        }
    }

    // Brawler: wide horizontal bump growing left and right from the
    // hub's own W/E hexes together, with a thickening pair partway out -
    // reads as broader than the default disc without a whole separate
    // algorithm. Full (not halved) tier length on EACH side - the disc
    // itself is already widest along this exact q-axis (a halved length
    // here sat entirely inside the disc's own natural horizontal reach
    // and got swallowed, confirmed by actually rendering it), so
    // matching Scout/Sniper's own per-direction reach is what it takes
    // to actually poke past it.
    fn seed_brawler_flourish(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, budget_tier: usize) {
        let length = Self::TORSO_FLOURISH_LEN_BY_TIER[budget_tier.min(5)];
        let mut right_tip = HexCoord { q: 1, r: 0 };
        let mut left_tip = HexCoord { q: -1, r: 0 };
        for i in 0..length {
            right_tip = right_tip.neighbor(0); // E
            left_tip = left_tip.neighbor(3); // W
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, right_tip);
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, left_tip);
            if i == length / 2 {
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, right_tip.neighbor(5)); // thicken (NE)
                Self::try_add_torso_hex(valid_hexes, valid_hex_set, left_tip.neighbor(2)); // thicken (SW)
            }
        }
    }

    // Ambusher: diagonal spike that hooks flat partway through - the
    // same "hook" primitive already used for Ambusher's procedural loot
    // shapes, applied to the deterministic starter torso too.
    fn seed_ambusher_flourish(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, budget_tier: usize) {
        let length = Self::TORSO_FLOURISH_LEN_BY_TIER[budget_tier.min(5)];
        let phase_len = std::cmp::max(2, length * 2 / 3);
        let mut tip = HexCoord { q: 1, r: -1 }; // already in the hub - spike's start
        for i in 0..length {
            tip = tip.neighbor(if i < phase_len { 5 } else { 0 }); // NE then E
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, tip);
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
