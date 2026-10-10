class_name IceEffects
extends RefCounted

# Ice embrittlement + shatter (docs/ELEMENTAL_REWORK_SPEC.md). The maths is pure (no nodes) so it can move to
# pixbots_core unchanged; apply_hit / try_shatter are the thin Mech-facing wrappers. Numbers marked (tune) need a balance pass.

const FROZEN_SPEED_MULT = 0.4 # existing "frozen" slow
const EMBRITTLE_BASE_SEC = 2.0 # (tune)
const EMBRITTLE_MAX_SEC = 8.0
const FLOW_REF = 200.0 # actuator flow assumed for mechs that carry no tracked actuator energy (enemies) (tune)
const SHATTER_MIN_KINETIC = 40.0 # (tune) a kinetic hit smaller than this is an ordinary hit
const SHATTER_BASE_RADIUS = 60.0
const SHATTER_MAX_RADIUS = 360.0
const SHATTER_MAX_ICE_ENERGY = 400.0 # ice energy beyond this adds no extra violence

# Share of actuator flow F blocked by a cold hit of energy I: I == F blocks half.
static func blocked_fraction(ice_energy: float, flow: float) -> float:
	if ice_energy <= 0.0:
		return 0.0
	return ice_energy / (ice_energy + maxf(flow, 0.0))

static func embrittle_duration(ice_energy: float) -> float:
	return clampf(EMBRITTLE_BASE_SEC + 2.0 * log(1.0 + maxf(ice_energy, 0.0) / 50.0), EMBRITTLE_BASE_SEC, EMBRITTLE_MAX_SEC)

# Violence of a shatter from the frozen target's ice energy and the kinetic hit. Returns {"radius", "damage"}; zeros when
# the hit is below the threshold.
static func shatter(ice_energy: float, kinetic: float) -> Dictionary:
	if ice_energy <= 0.0 or kinetic < SHATTER_MIN_KINETIC:
		return {"radius": 0.0, "damage": 0.0}
	var ice = minf(ice_energy, SHATTER_MAX_ICE_ENERGY)
	var k = sqrt(kinetic / SHATTER_MIN_KINETIC) # 1.0 at threshold, grows with the hit
	var radius = clampf(SHATTER_BASE_RADIUS * k * (1.0 + ice / 100.0), SHATTER_BASE_RADIUS, SHATTER_MAX_RADIUS)
	var damage = 0.5 * kinetic * (ice / (ice + 100.0)) * 2.0
	return {"radius": radius, "damage": damage}

# Called where the old code did apply_status("frozen", 3 * ratio). `damage` is the shot's damage (the energy proxy).
static func apply_hit(target: Node, ice_ratio: float, damage: float) -> void:
	target.apply_status("frozen", 3.0 * ice_ratio)
	if not ("embrittle_timer" in target):
		return
	var ice_energy = damage * ice_ratio
	var flow = FLOW_REF
	if "actuator_energy" in target and target.actuator_energy != null and target.actuator_energy.magnitude > 0.0:
		flow = target.actuator_energy.magnitude
	# Freeze Guard remediation shortens and weakens embrittlement the same way it shortens the frozen status.
	var resist = float(target.status_duration_mult.get("frozen", 1.0)) if "status_duration_mult" in target else 1.0
	var frac = blocked_fraction(ice_energy, flow) * resist
	# Stack by keeping the stronger block / longer timer rather than adding (a second hit refreshes, not doubles).
	target.embrittle_block = maxf(target.embrittle_block if target.embrittle_timer > 0.0 else 0.0, frac)
	target.embrittle_timer = maxf(target.embrittle_timer, embrittle_duration(ice_energy) * resist)
	target.frozen_ice_energy = maxf(target.frozen_ice_energy, ice_energy)

# Called from MechDamage.apply_damage before hp is reduced. Shatters a frozen mech on a big kinetic hit.
static func try_shatter(victim, element: String, amount: float, source) -> void:
	if element != "KINETIC" or victim.frozen_ice_energy <= 0.0 or not victim.status_effects.has("frozen"):
		return
	var s = shatter(victim.frozen_ice_energy, amount)
	if s["radius"] <= 0.0:
		return
	victim.status_effects.erase("frozen")
	victim.embrittle_timer = 0.0
	victim.frozen_ice_energy = 0.0
	victim.pending_shatter = {"radius": s["radius"], "damage": s["damage"], "source": source}

# Deals the collateral from a pending shatter (called after the victim has taken its hit, so it works off a settled state).
static func resolve_shatter(victim) -> void:
	var ps: Dictionary = victim.pending_shatter
	victim.pending_shatter = {}
	if ps.is_empty() or not victim.is_inside_tree():
		return
	var mask = SimPhysics.LAYER_ENEMY | SimPhysics.LAYER_PLAYER
	for c in SimPhysics.circle_colliders(victim, Transform2D(0.0, victim.global_position), ps["radius"], mask, 24):
		if c == victim or not is_instance_valid(c) or not c.has_method("apply_damage"):
			continue
		var d = victim.global_position.distance_to(c.global_position)
		var falloff = clampf(1.0 - d / ps["radius"], 0.2, 1.0)
		c.apply_damage(ps["damage"] * falloff, "ICE", victim, true, "SHATTER")
	if victim.has_method("_show_floating_text"):
		victim._show_floating_text("SHATTER!", Color(0.6, 0.9, 1.0))
