extends Node

# Regression harness for the "Counterplay Tells" backlog item (Status.md):
#   1. Decloak reveal tell: CloakSystem.break_cloak() spawns a visual burst
#      ring as a sibling of the mech, distinct from the ongoing shimmer that
#      already existed while a mech stays hidden.
#   2. Heal Beacon targetable: HexTile.get_disable_risk() and
#      Mech._find_disable_priority_tile() both promoted "Heal Beacon" out of
#      the unprioritized "other" bucket into the same secondary tier as
#      Reflector/Resonator/Amplifier, so focused fire on a healer's backpack
#      has a real chance of actually knocking the beacon offline.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const HealBeaconTileScript = preload("res://scripts/tiles/HealBeaconTile.gd")
const MagnetTileScript = preload("res://scripts/tiles/MagnetTile.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

const DT := 1.0 / 30.0

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- 1. get_disable_risk() promotion ---------------------------------
	var beacon = HealBeaconTileScript.new()
	var beacon_risk = beacon.get_disable_risk()
	if beacon_risk < 0.5:
		push_error("FAIL: Heal Beacon disable_risk still low-priority (%f)" % beacon_risk)
		failures += 1
	else:
		print("1) Heal Beacon get_disable_risk() promoted to secondary tier (%f)" % beacon_risk)

	# --- 2. _find_disable_priority_tile() picks the beacon over filler ---
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.RARE)
	world.add_child(comp)
	comp.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var filler = MagnetTileScript.new() # "other"-tier filler - must NOT be picked
	comp.hex_grid.add_tile(HexCoord.new(1, 0), filler)
	var beacon2 = HealBeaconTileScript.new()
	comp.hex_grid.add_tile(HexCoord.new(-1, 0), beacon2)

	var picked = mech._find_disable_priority_tile(comp)
	if picked != beacon2:
		push_error("FAIL: priority search didn't pick the Heal Beacon over filler (picked %s)" % [picked.tile_type if picked else "null"])
		failures += 1
	else:
		print("2) _find_disable_priority_tile() prioritizes Heal Beacon over filler tiles")

	# --- 3. Decloak burst tell --------------------------------------------
	var cloaked_mech = MechScript.new()
	cloaked_mech.is_player = false
	world.add_child(cloaked_mech)
	cloaked_mech.set_physics_process(false)
	cloaked_mech.has_cloak_generator = true
	cloaked_mech.max_cloak_charge = 100.0
	cloaked_mech.cloak_drain_rate = 5.0
	cloaked_mech.cloak_recharge_rate = 10.0
	cloaked_mech.is_cloaked = true

	var before_children = world.get_child_count()
	# _break_cloak() is Mech's thin lazy-constructing wrapper (see CloakSystem.gd's
	# header) - this is the same public entry point BossBrain/apply_damage use.
	cloaked_mech._break_cloak()
	await get_tree().process_frame
	var after_children = world.get_child_count()

	if cloaked_mech.is_cloaked:
		push_error("FAIL: mech still reports is_cloaked after _break_cloak()")
		failures += 1
	elif after_children <= before_children:
		push_error("FAIL: no decloak burst ring spawned (children %d -> %d)" % [before_children, after_children])
		failures += 1
	else:
		print("3) break_cloak() spawns a visual decloak burst ring as a sibling")

	if failures == 0:
		print("PASS: Counterplay tells - decloak burst + Heal Beacon disable-priority")
	get_tree().quit(0 if failures == 0 else 1)
