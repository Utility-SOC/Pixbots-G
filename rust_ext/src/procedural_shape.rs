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
                // power out to. Two iterations before this one both got the
                // WHOLE approach wrong, caught only by actually rendering
                // the result and (for the second) by the user's own direct
                // reaction to a rendered comparison: (1) a role-specific
                // spine/slab/spike grown WITHOUT any size cap - a Mythic
                // torso stretched into a 50+ hex diagonal staircase,
                // consuming the ENTIRE budget. (2) capped that spine and let
                // the plain default disc fill the rest - looked distinct in
                // isolation but was still "one round blob with a thin stick
                // coming off it" for every role, since ~90-95% of the shape
                // was still the same isotropic disc regardless of class.
                // Fixed by growing the WHOLE region anisotropically instead
                // via grow_hex_region/grow_diagonal_band (mirrors
                // ComponentEquipment.gd's own versions exactly - see their
                // comments for the axial-vs-screen-space rationale). Every
                // role not listed below keeps the exact original isotropic
                // disc-growth behavior, hub-guarantee included.
                match role.as_str() {
                    "scout" | "jammer" | "anti_missile" => {
                        // Both jammer variants are electronic-warfare
                        // subtypes of Scout (design ruling, 2026-08-11) -
                        // same tall lean silhouette, no separate identity.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 1.0, 1.0, 1.8, 1.8, false);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "sniper" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 0.4, 0.4, 2.5, 2.5, false);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "brawler" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 2.2, 2.2, 0.6, 0.6, false);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "ambusher" => {
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_diagonal_band(&mut valid_hexes, &mut valid_hex_set, base_count, 0.6, 2.2, 2.2);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "diver" => {
                        // Sniper's narrowness carried along Ambusher's
                        // diagonal (design ruling, 2026-08-11: "shaped
                        // like snipers and ambushers") - a sleek diagonal
                        // torpedo body, narrower/longer than Ambusher's own.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_diagonal_band(&mut valid_hexes, &mut valid_hex_set, base_count, 0.4, 2.6, 2.6);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "remediation" => {
                        // Squat and genuinely RECTANGULAR, not another wide
                        // diamond like Brawler - "more a pleco than a
                        // goldfish, more a bulldozer than a mecha" (design
                        // ruling, 2026-08-11). boxy=true fills complete
                        // screen-space rows outward from center instead of
                        // nearest-origin-first, giving square corners
                        // instead of Brawler's tapered lens shape.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 2.0, 2.0, 0.7, 0.7, true);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "support" => {
                        // Rounded shield/dome, not another hard-edged slab -
                        // mildly wider than tall, non-boxy (keeps the
                        // natural tapered-lens rounding), small downward
                        // bias (sy_pos > sy_neg) leaning toward whoever
                        // it's shielding. Mirrors ComponentEquipment.gd's
                        // own "support" branch exactly.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 1.6, 1.6, 1.1, 1.3, false);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "commander" => {
                        // Tall, wide, genuinely BLOCKY - an imposing
                        // monument/command-tower silhouette, boxy=true,
                        // biased taller-toward-the-top (sy_neg > sy_pos).
                        // Mirrors ComponentEquipment.gd's own "commander"
                        // branch exactly.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 1.5, 1.5, 2.2, 1.3, true);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                    }
                    "flamethrower" => {
                        // Forward-lurching aggressive wedge - the first
                        // role with a genuinely ASYMMETRIC horizontal
                        // bound (sx_pos far exceeds sx_neg), squat
                        // vertically. Mirrors ComponentEquipment.gd's own
                        // "flamethrower" branch exactly.
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
                        Self::grow_hex_region(&mut valid_hexes, &mut valid_hex_set, base_count, 0.9, 2.1, 1.0, 1.0, false);
                        Self::guarantee_torso_hub(&mut valid_hexes, &mut valid_hex_set);
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

    // Anisotropic hex-region grower for axis-aligned (vertical/
    // horizontal) silhouettes - Scout/Sniper/Brawler. Mirrors
    // ComponentEquipment.gd's _grow_hex_region exactly - see that
    // function's own comment for the full axial-vs-screen-space skew
    // rationale (bounds are in SCREEN-SPACE, px=2q+r/py=r, not raw
    // axial q/r, since axial coordinates are a skewed/non-orthogonal
    // basis relative to the game's own blueprint projection).
    // boxy=true switches the fill order from nearest-origin-first to
    // nearest-center-ROW-first (mirrors ComponentEquipment.gd's own
    // _grow_hex_region boxy parameter exactly - see that function's
    // comment for why Remediation needs this for a genuinely rectangular,
    // square-cornered read instead of Brawler's tapered lens shape).
    fn grow_hex_region(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize, sx_neg: f64, sx_pos: f64, sy_neg: f64, sy_pos: f64, boxy: bool) {
        let mut scale: f64 = 1.0;
        let mut candidates: Vec<HexCoord> = Vec::new();
        while candidates.len() < base_count && scale < 80.0 {
            candidates.clear();
            let half_span = (sx_neg.max(sx_pos).max(sy_neg).max(sy_pos) * scale).ceil() as i32 + 3;
            for q in -half_span..=half_span {
                for r in -half_span..=half_span {
                    let px = 2.0 * q as f64 + r as f64;
                    let py = r as f64;
                    if px < -sx_neg * scale - 0.5 || px > sx_pos * scale + 0.5 {
                        continue;
                    }
                    if py < -sy_neg * scale - 0.5 || py > sy_pos * scale + 0.5 {
                        continue;
                    }
                    candidates.push(HexCoord { q, r });
                }
            }
            scale += 1.0;
        }

        if boxy {
            candidates.sort_by(|a, b| {
                let pya = a.r.abs();
                let pyb = b.r.abs();
                let pxa = (2 * a.q + a.r).abs();
                let pxb = (2 * b.q + b.r).abs();
                pya.cmp(&pyb).then(pxa.cmp(&pxb)).then(a.q.cmp(&b.q)).then(a.r.cmp(&b.r))
            });
        } else {
            // Tie-break by (q, r) after distance - GDScript's Array.sort_custom
            // is not guaranteed stable, and this bound frequently has many
            // same-distance candidates right at the base_count cutoff
            // (confirmed by the parity check: same set size, different tail
            // hexes, until this secondary key was added). A full deterministic
            // order means an unstable sort on the GDScript side can't diverge.
            candidates.sort_by(|a, b| {
                let da = a.q.abs() + a.r.abs() + (a.q + a.r).abs();
                let db = b.q.abs() + b.r.abs() + (b.q + b.r).abs();
                da.cmp(&db).then(a.q.cmp(&b.q)).then(a.r.cmp(&b.r))
            });
        }
        for h in candidates {
            if valid_hexes.len() >= base_count {
                break;
            }
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, h);
        }
    }

    // Diagonal-band grower for Ambusher's blade silhouette. Mirrors
    // ComponentEquipment.gd's _grow_diagonal_band exactly - stays in raw
    // axial terms (unlike grow_hex_region above) because a fixed-q,
    // varying-r band genuinely IS a 45-degree diagonal line in this same
    // screen projection (the NW-SE hex direction).
    fn grow_diagonal_band(valid_hexes: &mut Vec<HexCoord>, valid_hex_set: &mut HashSet<HexCoord>, base_count: usize, q_half: f64, r_neg: f64, r_pos: f64) {
        let mut scale: f64 = 1.0;
        let mut candidates: Vec<HexCoord> = Vec::new();
        while candidates.len() < base_count && scale < 80.0 {
            candidates.clear();
            let q_max = (q_half * scale).ceil() as i32;
            let r_min = (-r_neg * scale).floor() as i32;
            let r_max = (r_pos * scale).ceil() as i32;
            for q in -q_max..=q_max {
                for r in r_min..=r_max {
                    candidates.push(HexCoord { q, r });
                }
            }
            scale += 1.0;
        }

        // Tie-break by (q, r) after distance - GDScript's Array.sort_custom
        // is not guaranteed stable, and this bound frequently has many
        // same-distance candidates right at the base_count cutoff
        // (confirmed by the parity check: same set size, different tail
        // hexes, until this secondary key was added). A full deterministic
        // order means an unstable sort on the GDScript side can't diverge.
        candidates.sort_by(|a, b| {
            let da = a.q.abs() + a.r.abs() + (a.q + a.r).abs();
            let db = b.q.abs() + b.r.abs() + (b.q + b.r).abs();
            da.cmp(&db).then(a.q.cmp(&b.q)).then(a.r.cmp(&b.r))
        });
        for h in candidates {
            if valid_hexes.len() >= base_count {
                break;
            }
            Self::try_add_torso_hex(valid_hexes, valid_hex_set, h);
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
