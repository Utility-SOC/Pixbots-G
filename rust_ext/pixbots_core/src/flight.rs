//! Per-projectile "organic velocity accumulation": kinetic steering, fire drag, poison gravity lob, vortex swirl,
//! lightning zig-zag. Pure per-projectile vector maths (no physics queries), so the engine layer batches many calls.
//! Vortex wander and pin live in GDScript (`VortexEffects`) for now and are layered on after this step.

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub const ZERO: Vec2 = Vec2 { x: 0.0, y: 0.0 };
    pub const fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
    fn lerp(self, to: Vec2, t: f32) -> Vec2 {
        Vec2::new(self.x + (to.x - self.x) * t, self.y + (to.y - self.y) * t)
    }
    /// Zero stays zero (matches Godot's `Vector2.normalized()`).
    fn normalized(self) -> Vec2 {
        let l = (self.x * self.x + self.y * self.y).sqrt();
        if l > 0.0 {
            Vec2::new(self.x / l, self.y / l)
        } else {
            Vec2::ZERO
        }
    }
    fn scale(self, k: f32) -> Vec2 {
        Vec2::new(self.x * k, self.y * k)
    }
    fn add(self, o: Vec2) -> Vec2 {
        Vec2::new(self.x + o.x, self.y + o.y)
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct FlightInput {
    pub r_kin: f64,
    pub r_vamp: f64,
    pub r_fire: f64,
    pub r_psn: f64,
    pub r_vtx: f64,
    pub r_ltg: f64,
    pub r_prc: f64,
    pub direction: Vec2,
    pub target_direction: Vec2,
    pub has_homing_target: bool,
    pub final_speed: f64,
    pub time_alive: f64,
    pub delta: f64,
    pub steering_resistance: f64,
    pub straighten: f64,
    pub lightning_segment_index: i64,
    pub lightning_prev_offset: f64,
    pub lightning_target_offset: f64,
    pub instance_id: i64,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct FlightOutput {
    pub direction: Vec2,
    pub velocity: Vec2,
    pub visual_offset: Vec2,
    pub current_speed: f64,
    pub gravity_velocity: Vec2,
    pub lightning_segment_index: i64,
    pub lightning_prev_offset: f64,
    pub lightning_target_offset: f64,
}

/// Cheap deterministic scramble (splitmix64-style), not Godot's `hash()`.
pub fn simple_hash(seed: i64) -> i64 {
    let mut x = seed as u64;
    x = x.wrapping_add(0x9E3779B97F4A7C15);
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D049BB133111EB);
    x ^= x >> 31;
    x as i64
}

pub fn step(i: &FlightInput) -> FlightOutput {
    let mut dir = i.direction;
    let mut effective_r_prc = i.r_prc;

    // KINETIC STEERING ("The Straightener") and VAMPIRIC homing override
    if i.has_homing_target {
        let turn_speed = (8.0 * i.r_vamp) / i.steering_resistance;
        dir = dir.lerp(i.target_direction, (turn_speed * i.delta) as f32).normalized();
        if i.r_kin > 0.0 && i.r_vamp > 0.0 {
            effective_r_prc = i.r_prc.max(0.5); // Kinetic + Vampiric grants pierce
        }
    } else if i.target_direction != Vec2::ZERO {
        let mut turn_speed: f64 = 0.5; // passive drift
        if i.r_kin > 0.0 {
            turn_speed += 6.0 * i.r_kin;
        }
        turn_speed /= i.steering_resistance;
        dir = dir.lerp(i.target_direction, (turn_speed * i.delta) as f32).normalized();
    }

    // FIRE DECELERATION ("The Plume") against PIERCE / KINETIC
    let mut current_speed = i.final_speed;
    if i.r_fire > 0.0 {
        let mut drag = 800.0 * i.r_fire;
        drag *= 1.0 - effective_r_prc;
        drag = (drag - 500.0 * i.r_kin).max(0.0);
        current_speed = (i.final_speed - drag * i.time_alive).max(50.0);
    }

    // POISON GRAVITY LOB ("The Mortar"), dampened by Kinetic's straightening
    let mut gravity_velocity = Vec2::ZERO;
    if i.r_psn > 0.0 {
        gravity_velocity = Vec2::new(0.0, (400.0 * i.r_psn * i.time_alive * i.straighten) as f32);
    }

    let ortho = Vec2::new(-dir.y, dir.x);
    let mut velocity = dir.scale(current_speed as f32).add(gravity_velocity);
    let mut visual_offset = Vec2::ZERO;

    // VORTEX SWIRL ("The Swirler")
    if i.r_vtx > 0.0 {
        let amplitude = 250.0 * i.r_vtx * i.straighten;
        let swirl = ortho.scale((i.time_alive * 6.0).cos() as f32).scale(amplitude as f32);
        velocity = velocity.add(swirl);
    }

    // LIGHTNING ZIG-ZAG ("The Arc")
    let mut seg = i.lightning_segment_index;
    let mut prev = i.lightning_prev_offset;
    let mut target = i.lightning_target_offset;
    if i.r_ltg > 0.0 {
        let segment_length: f64 = 0.045;
        let segment_index = (i.time_alive / segment_length) as i64;
        if segment_index != i.lightning_segment_index {
            seg = segment_index;
            prev = i.lightning_target_offset;
            let seed = simple_hash(i.instance_id) ^ segment_index;
            target = ((seed.rem_euclid(2000)) as f64 / 1000.0) - 1.0;
        }
        let t_raw = (i.time_alive.rem_euclid(segment_length) / segment_length).clamp(0.0, 1.0);
        let t = t_raw * t_raw; // ease sharply so it snaps rather than glides
        let wave = prev + (target - prev) * t;
        visual_offset = visual_offset.add(ortho.scale(wave as f32).scale((26.0 * i.r_ltg) as f32));
    }

    FlightOutput {
        direction: dir,
        velocity,
        visual_offset,
        current_speed,
        gravity_velocity,
        lightning_segment_index: seg,
        lightning_prev_offset: prev,
        lightning_target_offset: target,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> FlightInput {
        FlightInput {
            direction: Vec2::new(1.0, 0.0),
            final_speed: 400.0,
            steering_resistance: 1.0,
            straighten: 1.0,
            lightning_segment_index: -1,
            delta: 1.0 / 60.0,
            ..FlightInput::default()
        }
    }

    #[test]
    fn plain_shot_flies_straight_at_its_speed() {
        let o = step(&base());
        assert_eq!(o.direction, Vec2::new(1.0, 0.0));
        assert!((o.velocity.x - 400.0).abs() < 1e-3 && o.velocity.y == 0.0);
        assert_eq!(o.visual_offset, Vec2::ZERO);
    }

    #[test]
    fn fire_drag_slows_but_never_below_the_floor() {
        let o = step(&FlightInput { r_fire: 1.0, time_alive: 10.0, ..base() });
        assert_eq!(o.current_speed, 50.0);
        let early = step(&FlightInput { r_fire: 1.0, time_alive: 0.1, ..base() });
        assert!(early.current_speed < 400.0 && early.current_speed > 50.0);
    }

    #[test]
    fn kinetic_cancels_fire_drag() {
        let drag = step(&FlightInput { r_fire: 0.5, time_alive: 0.5, ..base() }).current_speed;
        let kin = step(&FlightInput { r_fire: 0.5, r_kin: 1.0, time_alive: 0.5, ..base() }).current_speed;
        assert!(kin > drag);
        assert_eq!(kin, 400.0);
    }

    #[test]
    fn poison_lobs_downward_over_time() {
        let o = step(&FlightInput { r_psn: 0.5, time_alive: 1.0, ..base() });
        assert!(o.gravity_velocity.y > 100.0 && o.velocity.y == o.gravity_velocity.y);
    }

    #[test]
    fn homing_turns_toward_the_target() {
        let o = step(&FlightInput { r_vamp: 1.0, has_homing_target: true, target_direction: Vec2::new(0.0, 1.0), delta: 0.1, ..base() });
        assert!(o.direction.y > 0.0 && o.direction.x < 1.0);
        let len = (o.direction.x * o.direction.x + o.direction.y * o.direction.y).sqrt();
        assert!((len - 1.0).abs() < 1e-5);
    }

    #[test]
    fn lightning_state_advances_deterministically() {
        let a = step(&FlightInput { r_ltg: 1.0, time_alive: 0.1, instance_id: 42, ..base() });
        let b = step(&FlightInput { r_ltg: 1.0, time_alive: 0.1, instance_id: 42, ..base() });
        assert_eq!(a.lightning_segment_index, b.lightning_segment_index);
        assert_eq!(a.lightning_target_offset, b.lightning_target_offset);
        assert_eq!(a.lightning_segment_index, 2);
        assert!(a.lightning_target_offset >= -1.0 && a.lightning_target_offset <= 1.0);
    }

    #[test]
    fn vortex_swirl_pushes_sideways_and_straighten_dampens_it() {
        let full = step(&FlightInput { r_vtx: 1.0, ..base() }).velocity.y.abs();
        let damped = step(&FlightInput { r_vtx: 1.0, straighten: 0.2, ..base() }).velocity.y.abs();
        assert!(full > 200.0 && damped < full);
    }
}
