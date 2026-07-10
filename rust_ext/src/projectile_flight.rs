use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

type VDict = Dictionary<Variant, Variant>;

// Ports Projectile.gd's per-frame "ORGANIC VELOCITY ACCUMULATION" block
// (kinetic steering response, fire drag, poison gravity lob, vortex swirl,
// lightning zig-zag) to Rust. Deliberately does NOT include the physics-
// server queries around it (homing target acquisition, vortex item-pull) -
// those cost the same regardless of which language calls them, since the
// query itself (not the GDScript glue) is what's expensive. This is pure
// per-projectile vector math with no scene-tree/physics-server coupling.
//
// Two entry points share the same core math (compute_step_core below):
//   compute_step  - single projectile, one dispatch. Kept as the fallback
//                   path for a projectile's very first tick, before
//                   ProjectileManager has had a chance to register and
//                   batch it (see ProjectileManager.gd).
//   compute_batch - the real per-frame path once combat gets busy: ONE
//                   Rust call carrying every live projectile's request,
//                   instead of one dispatch per projectile. Godot's
//                   per-call FFI dispatch overhead, not the trig itself,
//                   is what actually scaled badly with projectile count -
//                   this is the fix for that, not a bigger login on the
//                   math.
//
// Lightning's zig-zag used GDScript's hash(get_instance_id()) as a
// deterministic per-projectile seed - not replicated bit-for-bit here
// (Godot's internal hash() isn't a published, stable algorithm), so a
// Rust-path shot's zig-zag pattern looks similarly jagged/random but isn't
// pixel-identical to what the same shot would produce under the GDScript
// path. Purely cosmetic (the zig-zag's SHAPE isn't gameplay-critical, it
// just needs to read as "jagged"), so this is an accepted, deliberate
// difference, not a bug.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProjectileFlight {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for ProjectileFlight {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

// Cheap deterministic scramble (splitmix64-style) - not Godot's actual
// hash(), see the module comment above for why that's fine here.
fn simple_hash(seed: i64) -> i64 {
    let mut x = seed as u64;
    x = x.wrapping_add(0x9E3779B97F4A7C15);
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D049BB133111EB);
    x ^= x >> 31;
    x as i64
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).map(|v| v.to::<f64>()).unwrap_or(0.0)
}

// The actual math, shared by both compute_step and compute_batch (see the
// module comment for why there are two entry points).
#[allow(clippy::too_many_arguments)]
fn compute_step_core(
    ratios: &VDict,
    direction: Vector2, target_direction: Vector2, has_homing_target: bool,
    final_speed: f64, time_alive: f64, delta: f64,
    steering_resistance: f64, straighten: f64,
    lightning_state: &VDict,
    instance_id: i64,
) -> VDict {
    let r_kin = get_f(ratios, "r_kin");
    let r_vamp = get_f(ratios, "r_vamp");
    let r_fire = get_f(ratios, "r_fire");
    let r_psn = get_f(ratios, "r_psn");
    let r_vtx = get_f(ratios, "r_vtx");
    let r_ltg = get_f(ratios, "r_ltg");
    let r_prc = get_f(ratios, "r_prc");

    let lightning_segment_index = lightning_state.get("segment_index").map(|v| v.to::<i64>()).unwrap_or(-1);
    let lightning_prev_offset = get_f(lightning_state, "prev_offset");
    let lightning_target_offset = get_f(lightning_state, "target_offset");

    let mut dir = direction;
    let mut effective_r_prc = r_prc;

    // 3. KINETIC STEERING ("The Straightener") & VAMPIRIC OVERRIDE
    if has_homing_target {
        let turn_speed = (8.0 * r_vamp) / steering_resistance;
        dir = dir.lerp(target_direction, (turn_speed * delta) as f32).normalized();
        if r_kin > 0.0 && r_vamp > 0.0 {
            effective_r_prc = r_prc.max(0.5); // Kinetic+Vampiric grants pierce
        }
    } else if target_direction != Vector2::ZERO {
        let mut turn_speed: f64 = 0.5; // Passive drift
        if r_kin > 0.0 {
            turn_speed += 6.0 * r_kin;
        }
        turn_speed /= steering_resistance;
        dir = dir.lerp(target_direction, (turn_speed * delta) as f32).normalized();
    }

    // 4. FIRE DECELERATION ("The Plume") vs PIERCE / KINETIC
    let mut current_speed = final_speed;
    if r_fire > 0.0 {
        let mut drag_coefficient = 800.0 * r_fire;
        drag_coefficient *= 1.0 - effective_r_prc; // Pierce cancels drag organically
        drag_coefficient = (drag_coefficient - 500.0 * r_kin).max(0.0); // Kinetic fights it
        current_speed = (final_speed - drag_coefficient * time_alive).max(50.0);
    }

    // 5. POISON GRAVITY LOB ("The Mortar") - dampened by Kinetic's straightening
    let mut gravity_velocity = Vector2::ZERO;
    if r_psn > 0.0 {
        gravity_velocity = Vector2::new(0.0, (400.0 * r_psn * time_alive * straighten) as f32);
    }

    let ortho = Vector2::new(-dir.y, dir.x);
    let mut velocity = dir * (current_speed as f32) + gravity_velocity;
    let mut visual_offset = Vector2::ZERO;

    // 6. VORTEX SWIRL ("The Swirler") - self-movement only; the nearby-
    // item pull query stays in GDScript (it touches other physics
    // bodies, not pure per-projectile math).
    if r_vtx > 0.0 {
        let swirl_amplitude = 250.0 * r_vtx * straighten;
        let swirl_freq: f64 = 6.0;
        let swirl_vel = ortho * ((time_alive * swirl_freq).cos() as f32) * (swirl_amplitude as f32);
        velocity += swirl_vel;
    }

    // 7. LIGHTNING ZIG-ZAG ("The Arc")
    let mut new_segment_index = lightning_segment_index;
    let mut new_prev_offset = lightning_prev_offset;
    let mut new_target_offset = lightning_target_offset;
    if r_ltg > 0.0 {
        let segment_length: f64 = 0.045;
        let segment_index = (time_alive / segment_length) as i64;
        if segment_index != lightning_segment_index {
            new_segment_index = segment_index;
            new_prev_offset = lightning_target_offset;
            let seed = simple_hash(instance_id) ^ segment_index;
            new_target_offset = ((seed.rem_euclid(2000)) as f64 / 1000.0) - 1.0;
        }
        let seg_t_raw = ((time_alive.rem_euclid(segment_length)) / segment_length).clamp(0.0, 1.0);
        let seg_t = seg_t_raw * seg_t_raw; // ease sharply so it snaps rather than glides
        let lightning_wave = new_prev_offset + (new_target_offset - new_prev_offset) * seg_t;
        visual_offset += ortho * (lightning_wave as f32) * (26.0 * r_ltg) as f32;
    }

    let mut result = VDict::new();
    result.set("instance_id", instance_id);
    result.set("direction", dir);
    result.set("velocity", velocity);
    result.set("visual_offset", visual_offset);
    result.set("current_speed", current_speed);
    result.set("gravity_velocity", gravity_velocity);
    result.set("lightning_segment_index", new_segment_index);
    result.set("lightning_prev_offset", new_prev_offset);
    result.set("lightning_target_offset", new_target_offset);
    result
}

#[godot_api]
impl ProjectileFlight {
    // gdext's #[func] has a hard arity cap well under the ~19 individual
    // scalars this needs, so the ratios and lightning zig-zag's persistent
    // state each ride in as a small Dictionary instead of a wall of
    // separate float params.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn compute_step(
        &self,
        ratios: VDict,
        direction: Vector2, target_direction: Vector2, has_homing_target: bool,
        final_speed: f64, time_alive: f64, delta: f64,
        steering_resistance: f64, straighten: f64,
        lightning_state: VDict,
        instance_id: i64,
    ) -> VDict {
        compute_step_core(
            &ratios, direction, target_direction, has_homing_target,
            final_speed, time_alive, delta, steering_resistance, straighten,
            &lightning_state, instance_id,
        )
    }

    // Batched entry point: `requests` is an Array of Dictionaries, each
    // shaped exactly like compute_step's individual params bundled into
    // one dict (keys: ratios, direction, target_direction,
    // has_homing_target, final_speed, time_alive, delta,
    // steering_resistance, straighten, lightning_state, instance_id).
    // Returns an Array of result Dictionaries in the SAME order, each
    // tagged with its own instance_id so the caller can match results back
    // to projectiles by key rather than relying on order (GDScript-side
    // caller does this defensively even though order is preserved here).
    #[func]
    fn compute_batch(&self, requests: Array<Variant>) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        for req_variant in requests.iter_shared() {
            let req: VDict = match req_variant.try_to() {
                Ok(d) => d,
                Err(_) => continue,
            };
            let ratios: VDict = req.get("ratios").and_then(|v| v.try_to().ok()).unwrap_or_default();
            let lightning_state: VDict = req.get("lightning_state").and_then(|v| v.try_to().ok()).unwrap_or_default();
            let direction = req.get("direction").and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO);
            let target_direction = req.get("target_direction").and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO);
            let has_homing_target = req.get("has_homing_target").and_then(|v| v.try_to().ok()).unwrap_or(false);
            let final_speed = get_f(&req, "final_speed");
            let time_alive = get_f(&req, "time_alive");
            let delta = get_f(&req, "delta");
            let steering_resistance = get_f(&req, "steering_resistance");
            let straighten = get_f(&req, "straighten");
            let instance_id = req.get("instance_id").and_then(|v| v.try_to().ok()).unwrap_or(0i64);

            let result = compute_step_core(
                &ratios, direction, target_direction, has_homing_target,
                final_speed, time_alive, delta, steering_resistance, straighten,
                &lightning_state, instance_id,
            );
            results.push(&result.to_variant());
        }
        results
    }
}
