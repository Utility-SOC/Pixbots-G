extends Node

# Disabled/destroyed weapon mounts and broken limbs must stop contributing:
# no firing, no routing, no abilities, legs slow the mech; repair restores it.

const MechScript = preload("res://scripts/entities/Mech.gd")
var failures := 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _slots(m) -> Dictionary:
	var d = {}
	for w in m.precalculated_weapons:
		d[w.slot_type] = d.get(w.slot_type, 0) + 1
	return d

func _make():
	var m = MechScript.new()
	m.is_player = false
	m.max_hp = 1000.0
	m.hp = 1000.0
	add_child(m)
	return m

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame

	# --- disabled mounts stop being listed/fired after a recalculation ---
	var m = _make()
	await get_tree().process_frame
	m._recalculate_grid()
	var start = m.precalculated_weapons.size()
	_check("test mech starts with weapons (%d)" % start, start >= 2)
	var first = m.precalculated_weapons[0]
	first.mount.is_disabled = true
	_check("a disabled mount is reported offline immediately (before any recalc)", m._weapon_offline(first))
	m._on_tile_went_offline(first.mount)
	m._recalculate_grid()
	_check("after recalculation the disabled mount is no longer a weapon", m.precalculated_weapons.size() == start - 1)
	first.mount.is_disabled = false
	m.is_grid_dirty = true
	m._recalculate_grid()
	_check("a rebooted mount returns", m.precalculated_weapons.size() == start)

	m.update_status_effects(0.016)
	var s_full = m.current_move_speed
	var s_full_mult = m._get_mass_speed_mult()

	# --- breaking an arm removes exactly that arm's weapons ---
	var before = _slots(m)
	var arm_slot = HexTile.BodySlot.ARM_L if before.has(HexTile.BodySlot.ARM_L) else HexTile.BodySlot.ARM_R
	var arm_weapons = before.get(arm_slot, 0)
	_check("the arm carries a weapon to lose", arm_weapons > 0)
	m.apply_part_damage(arm_slot, m.max_hp * 0.5, "RAW")
	_check("a heavy hit breaks the arm", m.components[arm_slot].is_broken)
	var after = _slots(m)
	_check("broken arm's weapons are gone, the other limbs' remain", after.get(arm_slot, 0) == 0 and m.precalculated_weapons.size() == start - arm_weapons)
	var part_name = {HexTile.BodySlot.ARM_L: "Arm_true", HexTile.BodySlot.ARM_R: "Arm_false"}[arm_slot]
	var drawn = m._renderer.drawn_parts.get(part_name)
	_check("the broken arm's sprite is hidden", drawn != null and not drawn.visible)
	var torso_hp = m.hp
	m.apply_part_damage(arm_slot, 100.0, "RAW")
	_check("hits on the stump are redirected to the torso (not a free decoy)", m.components[arm_slot].is_broken and m.hp < torso_hp)

	# --- legs slow the mech ---
	m.update_status_effects(0.016)
	var s_ok = s_full * (m._get_mass_speed_mult() / s_full_mult) # same mass state (arm gone) as the leg checks
	m.apply_part_damage(HexTile.BodySlot.LEG_L, m.max_hp, "RAW")
	m.update_status_effects(0.016)
	_check("one broken leg slows movement", m.current_move_speed < s_ok * 0.7)
	m.apply_part_damage(HexTile.BodySlot.LEG_R, m.max_hp, "RAW")
	m.update_status_effects(0.016)
	_check("two broken legs slow it to a crawl", m.current_move_speed < s_ok * 0.4)

	# --- repair restores everything ---
	m.repair_broken_parts()
	for comp in m.components.values(): # Garage repair also reboots every offline tile
		for t in comp.hex_grid.get_all_tiles():
			t.is_disabled = false
			t.power_lost = false
	m._recalculate_grid()
	_check("repair shows the arm sprite again", m._renderer.drawn_parts[part_name].visible)
	_check("repair restores all limbs and weapons", m.precalculated_weapons.size() == start and not m.components[arm_slot].is_broken)
	m.update_status_effects(0.016)
	_check("repair restores movement speed", absf(m.current_move_speed - s_full) < 0.01)

	print("limb breakage check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
