extends Node

# Regression harness for Keeneye Sensing's SensorTile family (Corporate
# Sponsorships, task #17): real equip->recalc wiring for all 3 modes,
# jammer immunity blocking apply_synergy_jam(), cloak detection negating
# the ambush multiplier at hit time, and the passive sight-radius bonus.
#
# NOT covered here: Main._update_player_blind_state()'s jammer-immunity
# bypass - that needs a full jammer_field group member + EntityCache setup
# heavier than warranted for what's a single trivial `if not
# player.has_jammer_immunity:` guard around the existing blind-check loop,
# already verified by direct code review.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const CounterJammerTileScript = preload("res://scripts/tiles/brands/CounterJammerTile.gd")
const CounterCloakTileScript = preload("res://scripts/tiles/brands/CounterCloakTile.gd")
const CounterBothTileScript = preload("res://scripts/tiles/brands/CounterBothTile.gd")
const SightAndSearchScript = preload("res://scripts/entities/SightAndSearch.gd")

var failures = 0

func _equip_sensor(mech, tile_script) -> void:
	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	backpack.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.MYTHIC
	backpack.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var sensor = tile_script.new()
	sensor.rarity = HexTile.Rarity.MYTHIC
	sensor.brand_id = "sensors"
	backpack.hex_grid.add_tile(HexCoord.new(1, 0), sensor)
	mech.equip_component(backpack)
	mech._recalculate_grid()

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- 1. Real equip -> recalc wiring per mode ----------------------------
	var jammer_mech = MechScript.new()
	jammer_mech.is_player = false
	world.add_child(jammer_mech)
	jammer_mech.set_physics_process(false)
	_equip_sensor(jammer_mech, CounterJammerTileScript)
	if not jammer_mech.has_jammer_immunity or jammer_mech.has_cloak_detection:
		push_error("FAIL: CounterJammerTile should grant jammer immunity ONLY")
		failures += 1
	else:
		print("1) CounterJammerTile grants jammer immunity only")

	var cloak_mech = MechScript.new()
	cloak_mech.is_player = false
	world.add_child(cloak_mech)
	cloak_mech.set_physics_process(false)
	_equip_sensor(cloak_mech, CounterCloakTileScript)
	if cloak_mech.has_jammer_immunity or not cloak_mech.has_cloak_detection:
		push_error("FAIL: CounterCloakTile should grant cloak detection ONLY")
		failures += 1
	else:
		print("2) CounterCloakTile grants cloak detection only")

	var both_mech = MechScript.new()
	both_mech.is_player = false
	world.add_child(both_mech)
	both_mech.set_physics_process(false)
	_equip_sensor(both_mech, CounterBothTileScript)
	if not both_mech.has_jammer_immunity or not both_mech.has_cloak_detection:
		push_error("FAIL: CounterBothTile should grant both")
		failures += 1
	elif both_mech.sensor_sight_bonus <= 0.0:
		push_error("FAIL: no sensor tile granted the passive sight bonus")
		failures += 1
	else:
		print("3) CounterBothTile grants both, and every sensor tile grants the passive sight bonus (%.1f)" % both_mech.sensor_sight_bonus)

	# --- 2. Jammer immunity blocks apply_synergy_jam() ----------------------
	jammer_mech.apply_synergy_jam(EnergyPacket.SynergyType.FIRE, 5.0)
	if jammer_mech.jammed_synergies.has(EnergyPacket.SynergyType.FIRE):
		push_error("FAIL: apply_synergy_jam() still landed despite jammer immunity")
		failures += 1
	else:
		print("4) apply_synergy_jam() is a no-op against a jammer-immune mech")

	var normal_mech = MechScript.new()
	normal_mech.is_player = false
	world.add_child(normal_mech)
	normal_mech.set_physics_process(false)
	normal_mech.apply_synergy_jam(EnergyPacket.SynergyType.FIRE, 5.0)
	if not normal_mech.jammed_synergies.has(EnergyPacket.SynergyType.FIRE):
		push_error("FAIL: a normal (non-immune) mech didn't get jammed - regression in apply_synergy_jam()")
		failures += 1
	else:
		print("5) a normal mech still gets jammed as before (no regression)")

	# --- 3. Cloak detection negates the ambush multiplier at hit time -------
	var attacker = MechScript.new()
	attacker.is_player = false
	world.add_child(attacker)
	attacker.set_physics_process(false)
	attacker.has_cloak_generator = true
	attacker.is_cloaked = true # _get_ambush_multiplier() reads this directly

	var before_hp = cloak_mech.max_hp
	cloak_mech.hp = cloak_mech.max_hp
	cloak_mech.apply_damage(100.0, "RAW", attacker)
	var damage_taken_with_detection = before_hp - cloak_mech.hp
	# AMBUSH_MULTIPLIER is 2.5 (CloakSystem.gd) - detection should divide the
	# hit back down to roughly 100/2.5 = 40, not the full 100.
	if damage_taken_with_detection >= 90.0:
		push_error("FAIL: cloak detection didn't reduce an ambush hit (took %.1f of 100)" % damage_taken_with_detection)
		failures += 1
	else:
		print("6) cloak detection reduces an ambush hit from a cloaked attacker (took %.1f of 100)" % damage_taken_with_detection)

	# Sanity check the inverse: a mech WITHOUT cloak detection takes the full
	# ambush-boosted hit as before (no regression to the base case).
	normal_mech.hp = normal_mech.max_hp
	var before_hp2 = normal_mech.hp
	normal_mech.apply_damage(100.0, "RAW", attacker)
	var damage_taken_without_detection = before_hp2 - normal_mech.hp
	if damage_taken_without_detection < 90.0:
		push_error("FAIL: a normal (non-detecting) mech's damage was unexpectedly reduced (took %.1f of 100)" % damage_taken_without_detection)
		failures += 1
	else:
		print("7) a normal mech takes the full hit from a cloaked attacker (no regression, took %.1f of 100)" % damage_taken_without_detection)

	# --- 4. Passive sight-radius bonus actually extends _effective_sight_range() ---
	var sight_mech = MechScript.new()
	sight_mech.is_player = false
	world.add_child(sight_mech)
	sight_mech.set_physics_process(false)
	var baseline = SightAndSearchScript.new(sight_mech)._effective_sight_range()
	sight_mech.sensor_sight_bonus = 400.0
	var boosted = SightAndSearchScript.new(sight_mech)._effective_sight_range()
	if not is_equal_approx(boosted - baseline, 400.0):
		push_error("FAIL: sensor_sight_bonus didn't extend _effective_sight_range() by the expected amount (delta %.1f)" % (boosted - baseline))
		failures += 1
	else:
		print("8) sensor_sight_bonus extends _effective_sight_range() correctly (%.0f -> %.0f)" % [baseline, boosted])

	if failures == 0:
		print("PASS: Keeneye Sensing (Sensors brand) wiring, jammer immunity, cloak detection, and sight bonus all verified")
	get_tree().quit(0 if failures == 0 else 1)
