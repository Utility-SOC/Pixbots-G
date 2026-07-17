extends Node

# Regression harness for Aegis Dynamics' AegisJammerShieldTile (Corporate
# Sponsorships, task #17): real equip->recalc wiring (jammer capacity +
# elemental Aegis + shield-pulse all from ONE tile), the elemental Aegis
# damage cap applying to elemental synergies but NOT physical ones, the
# ally shield-pulse actually restoring shield_hp, and a regression check
# that the pre-existing Mythic Shield Generator's own Aegis mode still
# works unaffected.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const AegisJammerShieldTileScript = preload("res://scripts/tiles/brands/AegisJammerShieldTile.gd")
const ShieldGeneratorTileScript = preload("res://scripts/tiles/ShieldGeneratorTile.gd")

const DT := 1.0 / 30.0

var failures = 0

func _check(label: String, actual, expected):
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		if not is_equal_approx(float(actual), float(expected)):
			push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
			failures += 1
			return
	elif actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
		return
	print("ok: %s = %s" % [label, actual])

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- 1. Real equip -> recalc wiring: one tile grants jammer capacity +
	# elemental Aegis + shield-pulse all together -----------------------
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)
	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	backpack.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.MYTHIC
	backpack.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var aegis_tile = AegisJammerShieldTileScript.new()
	aegis_tile.rarity = HexTile.Rarity.MYTHIC
	aegis_tile.brand_id = "defensive"
	backpack.hex_grid.add_tile(HexCoord.new(1, 0), aegis_tile)
	mech.equip_component(backpack)
	mech._recalculate_grid()

	if not mech.has_jammer_module:
		push_error("FAIL: AegisJammerShieldTile didn't grant jammer capacity (inherits JammerModuleTile)")
		failures += 1
	elif not mech.has_elemental_aegis:
		push_error("FAIL: AegisJammerShieldTile didn't grant elemental Aegis")
		failures += 1
	elif not mech.has_shield_pulse or mech.shield_pulse_power <= 0.0 or mech.shield_pulse_radius <= 0.0:
		push_error("FAIL: AegisJammerShieldTile didn't grant shield-pulse capacity")
		failures += 1
	else:
		print("1) one AegisJammerShieldTile grants jammer capacity + elemental Aegis + shield-pulse together (power=%.1f radius=%.1f)" % [mech.shield_pulse_power, mech.shield_pulse_radius])

	# --- 2. Elemental Aegis caps FIRE/etc but NOT RAW/KINETIC/PIERCE/EXPLOSION ---
	mech.max_shield_hp = 100.0
	mech.shield_mythic_mode = -1 # not the base Mythic Aegis toggle - isolate the brand effect
	mech.dominant_shield_synergy = "" # no rock-paper-scissors bonus muddying the numbers

	mech.shield_hp = 100.0
	var elemental_leftover = mech._apply_shield_mitigation(1000.0, "FIRE")
	# AEGIS_HIT_CAP_RATIO = 0.15 -> capped at 15 damage to shield_hp, the other
	# 985 as overflow (shield_mythic_mode isn't Deflector, so overflow bleeds
	# through as the return value).
	var fire_damage_to_shield = 100.0 - mech.shield_hp
	if fire_damage_to_shield > 20.0:
		push_error("FAIL: elemental Aegis didn't cap a FIRE hit (shield took %.1f, expected ~15)" % fire_damage_to_shield)
		failures += 1
	else:
		print("2) elemental Aegis caps a FIRE hit to shield_hp (%.1f of a 1000 hit, expected ~15)" % fire_damage_to_shield)

	mech.shield_hp = 100.0
	var kinetic_leftover = mech._apply_shield_mitigation(80.0, "KINETIC")
	var kinetic_damage_to_shield = 100.0 - mech.shield_hp
	if kinetic_damage_to_shield < 70.0:
		push_error("FAIL: elemental Aegis incorrectly capped a KINETIC (non-elemental) hit (shield took %.1f of 80)" % kinetic_damage_to_shield)
		failures += 1
	else:
		print("3) elemental Aegis does NOT cap a KINETIC hit - physical damage types pass through uncapped (%.1f of 80)" % kinetic_damage_to_shield)

	# --- 3. Shield pulse actually restores ally shield_hp -------------------
	var sharer = MechScript.new()
	sharer.is_player = false
	sharer.add_to_group("enemy")
	world.add_child(sharer)
	sharer.set_physics_process(false)
	sharer.has_shield_pulse = true
	sharer.shield_pulse_power = 40.0
	sharer.shield_pulse_radius = 150.0
	sharer.shield_pulse_interval = 4.0
	sharer.shield_pulse_timer = 0.0 # fires on the very first tick
	sharer.global_position = Vector2.ZERO

	var ally = MechScript.new()
	ally.is_player = false
	ally.add_to_group("enemy")
	world.add_child(ally)
	ally.set_physics_process(false)
	ally.max_shield_hp = 100.0
	ally.shield_hp = 20.0
	ally.global_position = Vector2(80, 0) # inside the 150 radius

	var far_ally = MechScript.new()
	far_ally.is_player = false
	far_ally.add_to_group("enemy")
	world.add_child(far_ally)
	far_ally.set_physics_process(false)
	far_ally.max_shield_hp = 100.0
	far_ally.shield_hp = 20.0
	far_ally.global_position = Vector2(5000, 0) # well outside the radius

	await get_tree().process_frame # EntityCache group snapshot staleness - see ShadowCloakBrandCheck.gd's identical note

	sharer._update_shield_pulse(DT)

	if ally.shield_hp <= 20.0:
		push_error("FAIL: shield-pulse didn't restore an in-range ally's shield_hp (still %.1f)" % ally.shield_hp)
		failures += 1
	else:
		print("4) shield-pulse restores an in-range ally's shield_hp (20.0 -> %.1f)" % ally.shield_hp)

	if far_ally.shield_hp != 20.0:
		push_error("FAIL: shield-pulse incorrectly restored an out-of-range ally's shield_hp (%.1f)" % far_ally.shield_hp)
		failures += 1
	else:
		print("5) an out-of-range ally is correctly NOT restored")

	# --- 4. Regression: the pre-existing Mythic Shield Generator Aegis mode
	# still works exactly as before, independent of the brand system --------
	var mythic_mech = MechScript.new()
	mythic_mech.is_player = false
	world.add_child(mythic_mech)
	mythic_mech.set_physics_process(false)
	mythic_mech.max_shield_hp = 100.0
	mythic_mech.shield_hp = 100.0
	mythic_mech.shield_mythic_mode = 0 # Aegis
	mythic_mech.has_elemental_aegis = false # NOT brand-equipped
	var mythic_leftover = mythic_mech._apply_shield_mitigation(1000.0, "KINETIC") # Aegis caps ALL elements, not just "elemental" ones
	var mythic_damage_to_shield = 100.0 - mythic_mech.shield_hp
	if mythic_damage_to_shield > 20.0:
		push_error("FAIL: the pre-existing Mythic Shield Generator Aegis mode regressed (shield took %.1f, expected ~15)" % mythic_damage_to_shield)
		failures += 1
	else:
		print("6) pre-existing Mythic Shield Generator Aegis mode still caps every element as before (no regression)")

	if failures == 0:
		print("PASS: Aegis Dynamics (Defensive brand) wiring, elemental Aegis, shield-pulse, and Mythic Aegis regression all verified")
	get_tree().quit(0 if failures == 0 else 1)
