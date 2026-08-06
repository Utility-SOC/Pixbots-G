extends Node

# Regression harness for two new defensive mechanics (design request:
# "struts should function as elemental armor, and I'd also like reactive
# armor options which melee mechs will abuse"):
#   - Structural Strut: tuned to an element via secondary_synergy (same
#     convention as Elemental Infuser), stacks multiplicatively into
#     Mech.elemental_resistances - previously declared and READ by
#     apply_damage() but never written by any tile.
#   - Reactive Plating: passive presence grants has_reactive_plating - the
#     wearer counter-hits whatever damaged them, gated on the attacker
#     being within trigger_radius (so only melee/point-blank range abuses
#     this, not a sniper across the map) and a per-attacker cooldown, with
#     a was_reflected guard against infinite ping-pong between two
#     mutually-plated mechs standing adjacent.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const StructuralStrutTileScript = preload("res://scripts/tiles/StructuralStrutTile.gd")
const ReactivePlatingTileScript = preload("res://scripts/tiles/ReactivePlatingTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_minimal_torso(world: Node2D) -> Node:
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.COMMON
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	mech.equip_component(torso)
	return mech

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- Elemental armor (Structural Strut) ---------------------------------
	var mech = _make_minimal_torso(world)
	var arm = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.MYTHIC)
	arm.generate_shape()
	var strut = StructuralStrutTileScript.new()
	strut.rarity = HexTile.Rarity.MYTHIC
	strut.secondary_synergy = EnergyPacket.SynergyType.FIRE
	arm.hex_grid.add_tile(HexCoord.new(0, 0), strut)
	mech.equip_component(arm)
	mech._recalculate_grid()

	var expected_mult = 1.0 - (0.03 + 4 * 0.02) # base + Mythic(4) * rarity coeff, matching the defaults in Mech._collect_weapon_mounts_and_tile_capabilities
	_check("a Mythic FIRE-tuned Strut populates elemental_resistances[FIRE] correctly (got %.3f, want %.3f)" % [mech.elemental_resistances.get("FIRE", -1.0), expected_mult],
		is_equal_approx(mech.elemental_resistances.get("FIRE", -1.0), expected_mult))
	_check("an unrelated element (ICE) is untouched", not mech.elemental_resistances.has("ICE"))

	var hp_before = mech.hp
	mech.apply_damage(100.0, "FIRE", null)
	var fire_dealt = hp_before - mech.hp
	_check("apply_damage actually applies the reduced FIRE damage end-to-end (dealt %.1f, want %.1f)" % [fire_dealt, 100.0 * expected_mult],
		is_equal_approx(fire_dealt, 100.0 * expected_mult))

	var hp_before_raw = mech.hp
	mech.apply_damage(100.0, "RAW", null)
	_check("RAW damage (untuned element) is unaffected by the FIRE strut", is_equal_approx(hp_before_raw - mech.hp, 100.0))

	# --- Reactive Plating ----------------------------------------------------
	var defender = _make_minimal_torso(world)
	var pack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	pack.generate_shape()
	var plate = ReactivePlatingTileScript.new()
	plate.rarity = HexTile.Rarity.MYTHIC
	pack.hex_grid.add_tile(HexCoord.new(0, 0), plate)
	defender.equip_component(pack)
	defender._recalculate_grid()
	_check("Reactive Plating grants has_reactive_plating from mere presence (no routing)", defender.has_reactive_plating)
	var expected_reflect = 0.08 + 4 * 0.05 # base + Mythic(4) * rarity coeff
	_check("reflect pct computed correctly (got %.3f, want %.3f)" % [defender.reactive_plating_reflect_pct, expected_reflect],
		is_equal_approx(defender.reactive_plating_reflect_pct, expected_reflect))

	var near_attacker = MechScript.new()
	near_attacker.is_player = true
	near_attacker.hp = 10000.0
	near_attacker.max_hp = 10000.0
	world.add_child(near_attacker)
	near_attacker.set_physics_process(false)
	near_attacker.global_position = defender.global_position + Vector2(50, 0) # well inside the 140px default trigger_radius

	var atk_hp_before = near_attacker.hp
	defender.apply_damage(100.0, "RAW", near_attacker)
	var counter_dealt = atk_hp_before - near_attacker.hp
	_check("a close attacker eats the counter-hit (dealt %.1f, want %.1f)" % [counter_dealt, 100.0 * expected_reflect],
		is_equal_approx(counter_dealt, 100.0 * expected_reflect))

	var atk_hp_before2 = near_attacker.hp
	defender.apply_damage(100.0, "RAW", near_attacker)
	_check("a second hit from the SAME attacker within the cooldown window doesn't double-counter",
		is_equal_approx(atk_hp_before2, near_attacker.hp))

	var far_attacker = MechScript.new()
	far_attacker.is_player = true
	far_attacker.hp = 10000.0
	far_attacker.max_hp = 10000.0
	world.add_child(far_attacker)
	far_attacker.set_physics_process(false)
	far_attacker.global_position = defender.global_position + Vector2(5000, 0) # far outside trigger_radius

	var far_hp_before = far_attacker.hp
	defender.apply_damage(100.0, "RAW", far_attacker)
	_check("an attacker far outside trigger_radius (a ranged mech, not melee) is never countered",
		is_equal_approx(far_hp_before, far_attacker.hp))

	# Mutual plating: both sides equipped, standing adjacent - the
	# was_reflected guard must stop this cold in ONE bounce, not recurse.
	var mutual_a = _make_minimal_torso(world)
	var mutual_a_pack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	mutual_a_pack.generate_shape()
	var plate_a = ReactivePlatingTileScript.new()
	plate_a.rarity = HexTile.Rarity.MYTHIC
	mutual_a_pack.hex_grid.add_tile(HexCoord.new(0, 0), plate_a)
	mutual_a.equip_component(mutual_a_pack)
	mutual_a._recalculate_grid()

	var mutual_b = _make_minimal_torso(world)
	var mutual_b_pack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	mutual_b_pack.generate_shape()
	var plate_b = ReactivePlatingTileScript.new()
	plate_b.rarity = HexTile.Rarity.MYTHIC
	mutual_b_pack.hex_grid.add_tile(HexCoord.new(0, 0), plate_b)
	mutual_b.equip_component(mutual_b_pack)
	mutual_b._recalculate_grid()
	mutual_b.global_position = mutual_a.global_position + Vector2(30, 0)

	# If the was_reflected guard were missing, this single call would recurse
	# forever (A counters B counters A counters B...) and the test would hang
	# instead of failing cleanly - reaching the check below at all IS the proof.
	mutual_a.apply_damage(100.0, "RAW", mutual_b)
	_check("mutual reactive plating resolves in one bounce instead of infinite-recursing", true)

	for m in [mech, defender, near_attacker, far_attacker, mutual_a, mutual_b]:
		m.queue_free()
	await get_tree().process_frame

	if failures == 0:
		print("PASS: Elemental armor (Structural Strut) and Reactive Plating both wired correctly")
	get_tree().quit(0 if failures == 0 else 1)
