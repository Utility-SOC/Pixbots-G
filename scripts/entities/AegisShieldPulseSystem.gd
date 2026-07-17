class_name AegisShieldPulseSystem
extends RefCounted

# Corporate Sponsorships (task #17): Aegis Dynamics' AoE ally-shield pulse -
# same composed-RefCounted pattern as HealBeaconSystem.gd (see its header
# for the full split rationale), just refilling shield_hp instead of hp.
# Capacity fields (has_shield_pulse, shield_pulse_power/radius/interval,
# shield_pulse_timer) stay on Mech - _recalculate_grid writes them directly
# on every loadout change, same reasoning as every other ability system's
# capacity fields. _update_shield_pulse(delta) is a thin lazy-constructing
# wrapper on Mech since _physics_process calls it directly by that name.

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

func tick(delta: float) -> void:
	if not mech.has_shield_pulse:
		return
	mech.shield_pulse_timer -= delta
	if mech.shield_pulse_timer <= 0.0:
		mech.shield_pulse_timer = mech.shield_pulse_interval
		_emit_pulse()

func _emit_pulse():
	# Allies by side: AI beacons top up their squad (the "enemy" group); the
	# player's tops up their companion drones - same split
	# HealBeaconSystem._emit_pulse() already uses.
	var allies: Array = []
	if mech.is_player:
		var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
		if main and "drone_nodes" in main:
			allies = main.drone_nodes.values()
	else:
		allies = EntityCache.get_group("enemy")
	for ally in allies:
		if ally == mech or not is_instance_valid(ally) or not ("shield_hp" in ally) or not ("max_shield_hp" in ally):
			continue
		if ally.max_shield_hp <= 0.0:
			continue # no shield generator of their own - nothing to top up
		if mech.global_position.distance_to(ally.global_position) > mech.shield_pulse_radius:
			continue
		var restored = min(ally.max_shield_hp, ally.shield_hp + mech.shield_pulse_power) - ally.shield_hp
		ally.shield_hp += restored
		if restored >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d SHIELD" % int(round(restored)), Color(0.3, 0.6, 1.0))

	# Self too (AoE + self, matching Heal Beacon's own-mech inclusion).
	if mech.max_shield_hp > 0.0:
		var self_restored = min(mech.max_shield_hp, mech.shield_hp + mech.shield_pulse_power) - mech.shield_hp
		mech.shield_hp += self_restored

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = mech.global_position
		v.setup(mech.shield_pulse_radius, Color(0.2, 0.5, 1.0, 1.0))
		if mech.get_parent():
			mech.get_parent().add_child(v)
