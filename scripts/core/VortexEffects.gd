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
# Crash damage: hostile bodies dragged into each other by a pull hurt each other. Damage grows with the vortex energy doing
# the pulling and with how fast the two close on one another, and each body has a short cooldown so a pile-up is not a
# per-tick damage spam. It is VORTEX damage, so an Anchor's damage reduction applies to it.
const CRASH_DISTANCE = 48.0 # centre-to-centre
const CRASH_MIN_SPEED = 60.0 # px/s of closing speed below which bodies just nudge
const CRASH_REF_SPEED = 300.0 # closing speed that deals 1x CRASH_DAMAGE_PER_ENERGY
const CRASH_MAX_SPEED_MULT = 3.0
const CRASH_DAMAGE_PER_ENERGY = 0.35 # (tune) of the vortex energy (damage x vortex ratio), per crash at the reference speed
const CRASH_COOLDOWN = 0.4
const CRASH_WINDOW = 0.3 # a body counts as caught in the vortex this long after its last pull
const CRASH_FORGET = 1.0
static var _pulled: Dictionary = {} # instance_id -> {node, pos, vel, t, cd}

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
	if hostile and pull_mult > 0.0 and col is Node2D and col.has_method("apply_damage"):
		note_pull(col, _now(), power * r_vtx)
	# Pin: a hostile body inside the pin radius rides along with the shot (move_and_collide so walls still stop it).
	if hostile and pull_mult > 0.0 and carry != Vector2.ZERO and col is Node2D \
			and col.global_position.distance_to(src_pos) <= radius_pin and col.has_method("move_and_collide"):
		col.move_and_collide(carry)


static func crash_damage(energy: float, closing_speed: float) -> float:
	if closing_speed < CRASH_MIN_SPEED or energy <= 0.0:
		return 0.0
	return CRASH_DAMAGE_PER_ENERGY * energy * minf(closing_speed / CRASH_REF_SPEED, CRASH_MAX_SPEED_MULT)

static func _now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)

static func reset_crashes() -> void:
	_pulled.clear()

# Records that `col` is being pulled right now (sim time `now`, vortex energy `energy`) and crashes it into any other
# pulled body it overlaps while closing on it. Called from pull_target for hostile bodies; `now` is a parameter so a check
# can drive the clock. Velocity is measured from the body's own movement between notes, so it works for any mover.
static func note_pull(col: Node2D, now: float, energy: float, source: Node = null) -> void:
	var id = col.get_instance_id()
	var pos = col.global_position
	var e: Dictionary = _pulled.get(id, {})
	if e.is_empty():
		e = {"node": col, "pos": pos, "vel": Vector2.ZERO, "t": now, "cd": 0.0}
		_pulled[id] = e
	else:
		var dt = now - float(e["t"])
		if dt >= 0.03: # two shots pulling the same body in one tick must not zero its measured velocity
			e["vel"] = (pos - e["pos"]) / dt
			e["pos"] = pos
			e["t"] = now
		else:
			e["pos"] = pos
	for other_id in _pulled.keys():
		if other_id == id:
			continue
		var o: Dictionary = _pulled[other_id]
		if not is_instance_valid(o["node"]) or now - float(o["t"]) > CRASH_FORGET:
			_pulled.erase(other_id)
			continue
		if now - float(o["t"]) > CRASH_WINDOW or now < float(o["cd"]) or now < float(e["cd"]):
			continue
		var other: Node2D = o["node"]
		var delta_pos: Vector2 = other.global_position - pos
		if delta_pos.length() > CRASH_DISTANCE or delta_pos == Vector2.ZERO:
			continue
		var closing = ((e["vel"] as Vector2) - (o["vel"] as Vector2)).dot(delta_pos.normalized())
		var dmg = crash_damage(energy, closing)
		if dmg <= 0.0:
			continue
		var src = source if is_instance_valid(source) else null
		for victim in [col, other]:
			if is_instance_valid(victim) and victim.get("is_dead") != true and victim.has_method("apply_damage"):
				victim.apply_damage(dmg, "VORTEX", src, false, "VORTEX CRASH")
		e["cd"] = now + CRASH_COOLDOWN
		o["cd"] = now + CRASH_COOLDOWN
		break # one crash per body per note; the cooldown covers the rest of the pile-up
