extends Node

# Regression harness for Blueprint Cards (ChampionCard.assemble_blueprint):
# a card payload applied as a blueprint must rebuild the loadout using ONLY
# owned inventory (exact placement, inventory consumed), report unowned
# tiles as a shopping list, and never conjure or duplicate infrastructure
# (Core/links).

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const ChampionCard = preload("res://scripts/pvp/ChampionCard.gd")

func _strip_to_torso(mech: Node):
	for slot in mech.components.keys().duplicate():
		if slot != HexTile.BodySlot.TORSO:
			mech.unequip_component(slot)

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- source mech A: torso with a mount + an amplifier ---
	var mech_a = MechScript.new()
	mech_a.is_player = true
	world.add_child(mech_a)
	mech_a.set_physics_process(false)
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	var mount_hex = ComponentEquipmentScript._first_free_hex(torso, [HexCoord.new(0, 0)])
	torso.hex_grid.add_tile(mount_hex, mount)
	var amp = AmplifierTileScript.new()
	amp.rarity = HexTile.Rarity.RARE
	amp.body_slot = HexTile.BodySlot.TORSO
	var amp_hex = ComponentEquipmentScript._first_free_hex(torso, [HexCoord.new(0, 0), mount_hex])
	torso.hex_grid.add_tile(amp_hex, amp)
	mech_a.equip_component(torso) # installs the Core
	_strip_to_torso(mech_a) # _ready auto-equips default arms/legs/head - keep the check deterministic

	var payload = ChampionCard.build_payload(mech_a, "Blueprint Author")

	# --- target mech B: SAME torso shape, tiles stripped; owns one Amplifier ---
	var mech_b = MechScript.new()
	mech_b.is_player = true
	world.add_child(mech_b)
	mech_b.set_physics_process(false)
	var torso_b = SaveManager._deserialize_component(SaveManager._serialize_component(torso))
	torso_b.hex_grid.remove_tile(mount_hex)
	torso_b.hex_grid.remove_tile(amp_hex)
	mech_b.equip_component(torso_b)
	_strip_to_torso(mech_b)

	var owned_amp = AmplifierTileScript.new()
	owned_amp.rarity = HexTile.Rarity.RARE
	var inventory: Array = [owned_amp]

	var result = ChampionCard.assemble_blueprint(payload, mech_b, inventory)

	# 1. Placed exactly the owned amplifier; the mount lands on the list.
	if result.placed != 1 or result.total != 2:
		push_error("FAIL: expected placed=1 total=2, got placed=%d total=%d" % [result.placed, result.total])
		failures += 1
	else:
		print("1) placed 1/2 from stock")
	var mount_missing = false
	for m in result.missing:
		if "Weapon Mount" in m:
			mount_missing = true
	if result.missing.size() != 1 or not mount_missing:
		push_error("FAIL: shopping list wrong: %s" % str(result.missing))
		failures += 1
	else:
		print("2) shopping list: ", result.missing[0])

	# 3. The amplifier really sits at the blueprint's coordinate, consumed
	# from inventory.
	var placed_tile = torso_b.hex_grid.get_tile(amp_hex) if torso_b.hex_grid.has_tile(amp_hex) else null
	if placed_tile == null or placed_tile.tile_type != "Amplifier" or not inventory.is_empty():
		push_error("FAIL: amplifier not placed at blueprint coord / inventory not consumed")
		failures += 1
	else:
		print("3) amplifier placed at the exact blueprint hex, inventory consumed")

	# 4. Core untouched (infrastructure is never part of a blueprint).
	var core = torso_b.hex_grid.get_tile(HexCoord.new(0, 0)) if torso_b.hex_grid.has_tile(HexCoord.new(0, 0)) else null
	if core == null or core.tile_type != "Core Reactor":
		push_error("FAIL: core reactor was disturbed by blueprint assembly")
		failures += 1
	else:
		print("4) core untouched")

	if failures == 0:
		print("PASS: blueprint assembly honest - owned parts only, exact placement, shopping list for the rest")
	get_tree().quit(0 if failures == 0 else 1)
