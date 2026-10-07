class_name HealBeaconSystem
extends RefCounted

# Heal Beacon runtime behavior (Support backpack ability), split out of
# Mech.gd's _update_healer/_emit_heal_pulse block - see CloakSystem.gd's
# header for the full split rationale (same composed-RefCounted pattern,
# same reason it can't be a sibling Node).
#
# Capacity fields (has_healer, heal_pulse_power, heal_pulse_radius,
# heal_pulse_interval) and the runtime heal_pulse_timer all stay on Mech -
# _recalculate_grid writes the capacity fields directly on every loadout
# change AND seeds heal_pulse_timer indirectly through them, same reasoning
# as CloakSystem/JammerModuleSystem's capacity fields. _update_healer(delta)
# stays a real Mech method (now a thin lazy-constructing wrapper) since
# _physics_process calls it directly by that name.

const AllySystemHelper = preload("res://scripts/entities/AllySystemHelper.gd")

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

func tick(delta: float) -> void:
	if not mech.has_healer:
		return
	if mech.has_field_repair and mech.is_player:
		_tick_field_repair(delta)
	mech.heal_pulse_timer -= delta
	if mech.is_player:
		# Module-keybind ruling ("I need to be able to use every type of
		# module"): the player's Heal Beacon is a BUTTON, not an autocast -
		# press H (registered in Main._ready) when the pulse is charged.
		if mech.heal_pulse_timer <= 0.0 and InputMap.has_action("heal_pulse") and Input.is_action_just_pressed("heal_pulse"):
			mech.heal_pulse_timer = mech.heal_pulse_interval
			_emit_pulse()
	elif mech.heal_pulse_timer <= 0.0:
		mech.heal_pulse_timer = mech.heal_pulse_interval
		_emit_pulse()

func _emit_pulse():
	# Allies by side: AI beacons heal their squad (the "enemy" group); the
	# player's beacon heals their companion drones. See AllySystemHelper.
	var allies: Array = AllySystemHelper.get_allies(mech)
	for ally in allies:
		if ally == mech or not is_instance_valid(ally) or not ("hp" in ally):
			continue
		if mech.global_position.distance_to(ally.global_position) > mech.heal_pulse_radius:
			continue
		var healed = min(ally.max_hp, ally.hp + mech.heal_pulse_power) - ally.hp
		ally.hp += healed
		if healed >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d" % int(round(healed)), Color(0.3, 1.0, 0.4))

	# AI beacons self-heal at half strength (the squad is the point); the
	# player's manual pulse self-heals at full - it's their button.
	var self_mult = 1.0 if mech.is_player else 0.5
	var self_healed = min(mech.max_hp, mech.hp + mech.heal_pulse_power * self_mult) - mech.hp
	mech.hp += self_healed
	if self_healed >= 1.0:
		mech._show_floating_text("+%d" % int(round(self_healed)), Color(0.3, 1.0, 0.4))

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = mech.global_position
		v.setup(mech.heal_pulse_radius, Color(0.2, 0.9, 0.5, 1.0))
		if mech.get_parent():
			mech.get_parent().add_child(v)

# --- MYTHIC Field Repair -----------------------------------------------------------------------------------
# Banks the mythic beacon's routed energy; at repair_pulse_cost (huge by design) it mends the player's own mech:
# each pulse has repair_points_per_pulse (3) points spent in priority order - revive a destroyed limb (3 points,
# back at half integrity), restore a fried tile (1 each), top up every damaged tile's HP (1), top up hurt limbs'
# integrity (1). Charge banks at most ONE pulse while there is nothing to fix, so a pulse fires the moment
# something breaks. Enemy beacons never get this (player only), so bosses cannot repair themselves.
const LIMB_REVIVE_COST := 3

func _repair_stat(key: String, default_value: float) -> float:
	return TileStatsRegistry.get_stat("HealBeaconTile", key, default_value)

func _tick_field_repair(delta: float) -> void:
	var cost: float = _repair_stat("repair_pulse_cost", 240000.0)
	mech.repair_cooldown = maxf(0.0, mech.repair_cooldown - delta)
	mech.repair_charge = minf(mech.repair_charge + mech.repair_energy_flow * delta, cost)
	if mech.repair_charge >= cost and mech.repair_cooldown <= 0.0:
		if field_repair_pulse():
			mech.repair_charge -= cost
			mech.repair_cooldown = _repair_stat("repair_min_interval", 8.0)

# Spends one pulse's repair points; returns true if anything was actually repaired.
func field_repair_pulse() -> bool:
	var points: int = int(_repair_stat("repair_points_per_pulse", 3.0))
	var revived := 0
	var restored := 0
	var topped := false
	for comp in mech.components.values():
		if points >= LIMB_REVIVE_COST and comp.is_broken:
			comp.is_broken = false
			comp.integrity = comp.max_integrity * 0.5 if comp.max_integrity > 0.0 else -1.0
			points -= LIMB_REVIVE_COST
			revived += 1
	for comp in mech.components.values():
		if points <= 0:
			break
		for t in comp.hex_grid.get_all_tiles():
			if points > 0 and t.power_lost:
				t.power_lost = false
				t.is_disabled = false
				t.disable_timer = 0.0
				t.hp = t.max_hp
				points -= 1
				restored += 1
	if points > 0:
		var any_hurt := false
		for comp in mech.components.values():
			for t in comp.hex_grid.get_all_tiles():
				if not t.power_lost and t.hp < t.max_hp:
					t.hp = t.max_hp
					any_hurt = true
		if any_hurt:
			points -= 1
			topped = true
	var limbs_healed := false
	if points > 0:
		for comp in mech.components.values():
			if not comp.is_broken and comp.integrity >= 0.0 and comp.max_integrity > 0.0 and comp.integrity < comp.max_integrity:
				comp.integrity = comp.max_integrity
				limbs_healed = true
		if limbs_healed:
			points -= 1
	if revived == 0 and restored == 0 and not topped and not limbs_healed:
		return false
	mech.is_grid_dirty = true # re-route energy and rebuild weapon/ability lists with the mended parts
	if revived > 0 and mech._renderer and mech._renderer.has_method("apply_broken_parts"):
		mech._renderer.apply_broken_parts()
	var parts: Array = []
	if revived > 0: parts.append("%d limb" % revived)
	if restored > 0: parts.append("%d tile" % restored)
	if topped or limbs_healed: parts.append("integrity")
	mech._show_floating_text("FIELD REPAIR: " + ", ".join(parts), Color(0.5, 1.0, 0.9))
	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class and mech.get_parent():
		var v = visual_class.new()
		v.global_position = mech.global_position
		v.setup(mech.heal_pulse_radius, Color(0.5, 1.0, 0.9, 1.0))
		mech.get_parent().add_child(v)
	return true
