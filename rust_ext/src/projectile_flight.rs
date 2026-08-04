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
// Three entry points share the same core math (compute_step_core_prim
// below):
//   compute_step      - single projectile, one dispatch, Dictionary in/out.
//                        Kept as the fallback path for a projectile's very
//                        first tick, before ProjectileManager has had a
//                        chance to register and batch it (see
//                        ProjectileManager.gd). Rare enough that Dictionary
//                        marshalling cost doesn't matter here.
//   compute_batch      - ORIGINAL batched entry point, Array<Dictionary> in/
//                        out. Kept only as the parity-check reference
//                        implementation (see ProjectileFlightFlatParityCheck.gd)
//                        - no longer called from the real per-frame hot path.
//   compute_batch_flat - the REAL per-frame path (2026-08-03 rewrite): same
//                        batching idea as compute_batch, but the payload is
//                        two packed arrays (PackedInt64Array instance_ids +
//                        PackedFloat64Array requests_flat, fixed
//                        REQUEST_STRIDE per projectile) instead of an
//                        Array<Dictionary>. Measured cause: compute_batch's
//                        per-entry Dictionary marshalling (unpacking a
//                        top-level dict + a nested 7-key "ratios" sub-dict +
//                        a nested "lightning_state" sub-dict, ~11 Variant
//                        key lookups per projectile) cost ~1.94ms/tick on
//                        its own at 500 live projectiles - a real cost this
//                        session's earlier "batch it into one call" fix
//                        didn't eliminate, since marshalling cost scales
//                        with DATA volume, not just call COUNT. Packed
//                        arrays marshal via direct memory copy instead of
//                        per-key Variant conversion. instance_id rides in a
//                        SEPARATE PackedInt64Array (not folded into the
//                        float payload) to avoid ANY f64-precision risk on
//                        an opaque 64-bit ID that's also used as a lightning
//                        zig-zag hash seed - correctness must not depend on
//                        exact bit-for-bit ID preservation.
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
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

// The actual math, shared by every entry point. Primitive in, primitive out
// (a tuple) - no Dictionary construction here at all, so callers decide
// their own marshalling shape (Dictionary for compute_step/compute_batch,
// flat packed arrays for compute_batch_flat) without duplicating the math.
// Returns (direction, velocity, visual_offset, current_speed,
// gravity_velocity, new_lightning_segment_index, new_lightning_prev_offset,
// new_lightning_target_offset).
#[allow(clippy::too_many_arguments)]
fn compute_step_core_prim(
    r_kin: f64, r_vamp: f64, r_fire: f64, r_psn: f64, r_vtx: f64, r_ltg: f64, r_prc: f64,
    direction: Vector2, target_direction: Vector2, has_homing_target: bool,
    final_speed: f64, time_alive: f64, delta: f64,
    steering_resistance: f64, straighten: f64,
    lightning_segment_index: i64, lightning_prev_offset: f64, lightning_target_offset: f64,
    instance_id: i64,
) -> (Vector2, Vector2, Vector2, f64, Vector2, i64, f64, f64) {
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

    (dir, velocity, visual_offset, current_speed, gravity_velocity, new_segment_index, new_prev_offset, new_target_offset)
}

// Dictionary-shaped wrapper around compute_step_core_prim, used by both
// compute_step and compute_batch (see module comment for why those two
// still exist).
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

    let lightning_segment_index = lightning_state.get("segment_index").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(-1);
    let lightning_prev_offset = get_f(lightning_state, "prev_offset");
    let lightning_target_offset = get_f(lightning_state, "target_offset");

    let (dir, velocity, visual_offset, current_speed, gravity_velocity, new_segment_index, new_prev_offset, new_target_offset) =
        compute_step_core_prim(
            r_kin, r_vamp, r_fire, r_psn, r_vtx, r_ltg, r_prc,
            direction, target_direction, has_homing_target,
            final_speed, time_alive, delta, steering_resistance, straighten,
            lightning_segment_index, lightning_prev_offset, lightning_target_offset,
            instance_id,
        );

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

// Field order contract for compute_batch_flat - MUST match
// ProjectileManager.gd's _physics_process / Projectile._prepare_flight_request_flat
// exactly (documented on both sides).
const REQUEST_STRIDE: usize = 20;
const RESPONSE_STRIDE: usize = 12;

#[godot_api]
impl ProjectileFlight {
    // gdext's #[func] has a hard arity cap well under the ~19 individual
    // scalars this needs, so the ratios and lightning zig-zag's persistent
    // state each ride in as a small Dictionary instead of a wall of
    // separate float params. Rare call (a projectile's very first tick
    // only), so Dictionary marshalling cost here doesn't matter.
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

    // ORIGINAL batched entry point - Array<Dictionary> in/out. No longer
    // called from the real per-frame hot path (see compute_batch_flat
    // below and the module comment) - kept solely as the reference
    // implementation ProjectileFlightFlatParityCheck.gd compares
    // compute_batch_flat against, proving the flat rewrite didn't change
    // behavior.
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

    // THE real per-frame hot path (2026-08-03). `instance_ids[i]` and the
    // REQUEST_STRIDE-wide slice `requests_flat[i*REQUEST_STRIDE .. ]`
    // together describe projectile i, for i in 0..instance_ids.len().
    // Field order within each stride (all f64, has_homing_target as 0.0/
    // 1.0, lightning_segment_index as f64 - safe, bounded well under a few
    // hundred for any realistic projectile lifetime):
    //   0:r_kin 1:r_vamp 2:r_fire 3:r_psn 4:r_vtx 5:r_ltg 6:r_prc
    //   7:direction.x 8:direction.y 9:target_direction.x 10:target_direction.y
    //   11:has_homing_target 12:final_speed 13:time_alive 14:delta
    //   15:steering_resistance 16:straighten
    //   17:lightning_segment_index 18:lightning_prev_offset 19:lightning_target_offset
    //
    // Returns a flat PackedFloat64Array, RESPONSE_STRIDE-wide per
    // projectile, in the SAME order as the input (position i answers for
    // instance_ids[i] - no instance_id echoed back, the caller already has
    // its own parallel array of Projectile references in that same order,
    // see ProjectileManager.gd):
    //   0:direction.x 1:direction.y 2:velocity.x 3:velocity.y
    //   4:visual_offset.x 5:visual_offset.y 6:current_speed
    //   7:gravity_velocity.x 8:gravity_velocity.y
    //   9:lightning_segment_index 10:lightning_prev_offset 11:lightning_target_offset
    #[func]
    fn compute_batch_flat(&self, instance_ids: PackedInt64Array, requests_flat: PackedFloat64Array) -> PackedFloat64Array {
        let n = instance_ids.len();
        let mut out = PackedFloat64Array::new();
        out.resize(n * RESPONSE_STRIDE);

        for i in 0..n {
            let base = i * REQUEST_STRIDE;
            if base + REQUEST_STRIDE > requests_flat.len() {
                break; // malformed input (length mismatch) - stop rather than panic on OOB
            }
            let r_kin = requests_flat[base];
            let r_vamp = requests_flat[base + 1];
            let r_fire = requests_flat[base + 2];
            let r_psn = requests_flat[base + 3];
            let r_vtx = requests_flat[base + 4];
            let r_ltg = requests_flat[base + 5];
            let r_prc = requests_flat[base + 6];
            let direction = Vector2::new(requests_flat[base + 7] as f32, requests_flat[base + 8] as f32);
            let target_direction = Vector2::new(requests_flat[base + 9] as f32, requests_flat[base + 10] as f32);
            let has_homing_target = requests_flat[base + 11] != 0.0;
            let final_speed = requests_flat[base + 12];
            let time_alive = requests_flat[base + 13];
            let delta = requests_flat[base + 14];
            let steering_resistance = requests_flat[base + 15];
            let straighten = requests_flat[base + 16];
            let lightning_segment_index = requests_flat[base + 17] as i64;
            let lightning_prev_offset = requests_flat[base + 18];
            let lightning_target_offset = requests_flat[base + 19];
            let instance_id = instance_ids[i];

            let (dir, velocity, visual_offset, current_speed, gravity_velocity, new_segment_index, new_prev_offset, new_target_offset) =
                compute_step_core_prim(
                    r_kin, r_vamp, r_fire, r_psn, r_vtx, r_ltg, r_prc,
                    direction, target_direction, has_homing_target,
                    final_speed, time_alive, delta, steering_resistance, straighten,
                    lightning_segment_index, lightning_prev_offset, lightning_target_offset,
                    instance_id,
                );

            let out_base = i * RESPONSE_STRIDE;
            out[out_base] = dir.x as f64;
            out[out_base + 1] = dir.y as f64;
            out[out_base + 2] = velocity.x as f64;
            out[out_base + 3] = velocity.y as f64;
            out[out_base + 4] = visual_offset.x as f64;
            out[out_base + 5] = visual_offset.y as f64;
            out[out_base + 6] = current_speed;
            out[out_base + 7] = gravity_velocity.x as f64;
            out[out_base + 8] = gravity_velocity.y as f64;
            out[out_base + 9] = new_segment_index as f64;
            out[out_base + 10] = new_prev_offset;
            out[out_base + 11] = new_target_offset;
        }

        out
    }
}
