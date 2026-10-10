class_name VortexEffects
extends RefCounted

# Vortex rework (docs/ELEMENTAL_REWORK_SPEC.md): pin, gravity-well mine, bezier wander. Shared by Projectile.gd (legacy
# per-shot nodes) and ProjectileBatchPool.gd (live combat default) so both agree. The maths is pure; `pull_target` is the
# one place that touches a body. Numbers marked (tune) need a balance pass.

const QUERY_INTERVAL = 0.05
const WELL_MIN_RATIO = 0.2 # both Poison and Vortex at least this share of the shot
const WELL_MIN_ENERGY = 150.0 # (tune) "large": damage x vortex ratio
const WELL_BASE_RADIUS = 200.0
const WELL_RADIUS_PER_SQRT_ENERGY = 14.0 # radius grows with the vortex energy
const WELL_MAX_RADIUS = 1000.0
const EXPLOSIVE_WIDEN = 1.0 # +100% radius at 100% Explosive
const PIN_BASE_RADIUS = 36.0
const PIN_PER_RATIO = 30.0
const WANDER_SEGMENT_SEC = 0.55
const WANDER_AMPLITUDE = 260.0
const WANDER_MIN_RATIO = 0.15

static func pull_magnitude_mult(power: float) -> float:
	return minf(1.0 + log(1.0 + power / 200.0) * 0.4, 3.0)

# A shot is a gravity-well mine when it is already a poison mine AND carries a large vortex share.
static func is_well(r_psn: float, r_vtx: float, damage: float) -> bool:
	return r_psn >= WELL_MIN_RATIO and r_vtx >= WELL_MIN_RATIO and damage * r_vtx >= WELL_MIN_ENERGY

# AoE radius from the vortex energy; Explosive widens it.
static func well_radius(vortex_energy: float, r_exp: float) -> float:
	var base = WELL_BASE_RADIUS + WELL_RADIUS_PER_SQRT_ENERGY * sqrt(maxf(vortex_energy, 0.0))
	return minf(base * (1.0 + EXPLOSIVE_WIDEN * clampf(r_exp, 0.0, 1.0)), WELL_MAX_RADIUS)

static func pin_radius(r_vtx: float) -> float:
	return PIN_BASE_RADIUS + PIN_PER_RATIO * r_vtx

# Deterministic value in [-1, 1] for (seed, index): integer mix, no global RNG, same on every platform.
static func _mix(seed_value: int, index: int) -> float:
	var h: int = (seed_value * 73856093) ^ (index * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 32767.5 - 1.0

# Lateral VELOCITY (px/s along the shot's normal) of a quadratic-Bezier wander: each segment bends from one control value
# to the next through a third, so the path curves instead of zig-zagging. `seed_value` is the shot's spawn seed.
static func wander_velocity(time_alive: float, seed_value: int, r_vtx: float, straighten: float = 1.0) -> float:
	if r_vtx < WANDER_MIN_RATIO:
		return 0.0
	var seg = int(time_alive / WANDER_SEGMENT_SEC)
	var u = fmod(time_alive, WANDER_SEGMENT_SEC) / WANDER_SEGMENT_SEC
	var p0 = _mix(seed_value, seg)
	var p1 = _mix(seed_value, seg + 1)
	var c = _mix(seed_value ^ 0x5bd1, seg) * 1.6
	# d/du of (1-u)^2 p0 + 2(1-u)u c + u^2 p1
	var dy = 2.0 * (1.0 - u) * (c - p0) + 2.0 * u * (p1 - c)
	return dy / WANDER_SEGMENT_SEC * WANDER_AMPLITUDE * r_vtx * straighten * 0.5

# One target's share of a vortex pull; pins (carries) enemies already inside the pin radius. Returns nothing.
# `carry` is how far the shot itself moved since the last query (zero for a stationary well).
static func pull_target(col: Node, src_pos: Vector2, fired_by_player: bool, r_vtx: float, power: float, delta: float, carry: Vector2, radius_pin: float, skip: Object = null) -> void:
	if col == skip or not is_instance_valid(col):
		return
	var pull_mult = 3.0 # targets get pulled 300% as hard
	var hostile = true
	if "is_player" in col:
		if fired_by_player == col.is_player:
			hostile = false
			pull_mult = 0.0 if col.get("is_vortex_immune") else 0.05 # the shooter's side is barely affected
		else:
			var prot = col.get("vortex_pull_protection_ratio")
			if prot != null and float(prot) > 0.0:
				pull_mult *= (1.0 - float(prot))
	var pull_strength = 600.0 * r_vtx * pull_mult * pull_magnitude_mult(power)
	if col.has_method("pull_towards"):
		col.pull_towards(src_pos, delta, pull_strength)
	elif col is CharacterBody2D:
		var p_dir = (src_pos - col.global_position).normalized()
		col.velocity = col.velocity.lerp(p_dir * pull_strength, minf(10.0 * delta, 1.0))
	# Pin: a hostile body inside the pin radius rides along with the shot (move_and_collide so walls still stop it).
	if hostile and pull_mult > 0.0 and carry != Vector2.ZERO and col is Node2D \
			and col.global_position.distance_to(src_pos) <= radius_pin and col.has_method("move_and_collide"):
		col.move_and_collide(carry)
