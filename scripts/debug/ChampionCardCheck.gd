extends Node

# End-to-end harness for the PvP Traveling Champion pipeline
# (scripts/pvp/ChampionCard.gd + Main's ghost spawning rules):
#   1. Export: player mech -> Champion Card PNG with embedded iTXt payload.
#   2. The PNG must still be a valid, loadable image after chunk insertion.
#   3. Extract: payload round-trips (pilot name, components).
#   4. Import: card file -> registered ghost in user://pvp_ghosts/.
#   5. Spawn: a mech equipped from the ghost payload is ARMED (the exact
#      exported build produces weapons).
#   6. Rank: beating a ghost raises the local (encrypted) rank.
#   7. Ghost loot: always at least one component + one tile pickup.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const LootPickupScript = preload("res://scripts/entities/LootPickup.gd")
const ChampionCard = preload("res://scripts/pvp/ChampionCard.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- player mech with a real (small) build ---
	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount)
	player.equip_component(torso) # installs the Core at (0,0)

	# --- 1-2: export + PNG still valid ---
	var path = ChampionCard.export_card(player, "Harness Pilot")
	if path == "" or not FileAccess.file_exists(path):
		push_error("FAIL: export_card produced no file")
		get_tree().quit(1)
		return
	var f = FileAccess.open(path, FileAccess.READ)
	var png_bytes = f.get_buffer(f.get_length())
	f.close()
	var reload = Image.new()
	if reload.load_png_from_buffer(png_bytes) != OK:
		push_error("FAIL: card PNG no longer loads after chunk embedding")
		failures += 1
	else:
		print("1-2) card exported (%d bytes) and still loads as a PNG" % png_bytes.size())

	# --- 3: payload round trip ---
	var payload = ChampionCard.extract_payload(png_bytes)
	if payload.get("pilot_name", "") != "Harness Pilot" or payload.get("components", {}).is_empty():
		push_error("FAIL: embedded payload didn't round-trip: %s" % str(payload.keys()))
		failures += 1
	else:
		print("3) payload round-trips (pilot + %d component(s))" % payload["components"].size())

	# --- 4: import registers a ghost ---
	var ghost = ChampionCard.import_card(path)
	if ghost.is_empty() or not FileAccess.file_exists(ChampionCard.GHOSTS_DIR + ghost["ghost_id"] + ".json"):
		push_error("FAIL: import_card did not register a ghost")
		failures += 1
	else:
		print("4) ghost registered: %s" % ghost["ghost_id"])

	# --- 5: ghost spawns ARMED ---
	var champ = MechScript.new()
	champ.is_player = false
	world.add_child(champ)
	champ.set_physics_process(false)
	for slot_str in ghost.get("components", {}):
		var comp = SaveManager._deserialize_component(ghost["components"][slot_str])
		if comp:
			champ.equip_component(comp)
	champ._recalculate_grid()
	if champ.precalculated_weapons.is_empty():
		push_error("FAIL: ghost spawned unarmed from its own exported build")
		failures += 1
	else:
		print("5) ghost is armed (%d weapon(s))" % champ.precalculated_weapons.size())

	# --- 6: rank moves on a win ---
	var before = ChampionCard.get_local_rank()
	ChampionCard.record_result(ghost["ghost_id"], true)
	var after = ChampionCard.get_local_rank()
	if after <= before:
		push_error("FAIL: winning against a ghost didn't raise local rank (%.1f -> %.1f)" % [before, after])
		failures += 1
	else:
		print("6) local rank %.1f -> %.1f on a win" % [before, after])

	# --- 7: ghost loot always yields a component + a tile ---
	# Far from the player, or it vacuums the pickups up the frame they spawn
	# (which is also a pass, but makes them uncountable).
	champ.global_position = Vector2(50000, 50000)
	LootManager.generate_ghost_loot(champ)
	await get_tree().process_frame
	await get_tree().process_frame
	var components = 0
	var tiles = 0
	for child in world.get_children():
		if child is LootPickupScript:
			if child.get("equipment_data") != null:
				components += 1
			elif child.get("tile_data") != null:
				tiles += 1
	if components < 1 or tiles < 1:
		push_error("FAIL: ghost loot rules broken (components=%d tiles=%d, expect >=1 each)" % [components, tiles])
		failures += 1
	else:
		print("7) ghost loot: %d component(s), %d tile(s)" % [components, tiles])

	# Cleanup: this runs against the REAL user:// - leaving harness ghosts
	# registered would make "Harness Pilot" challenge Natalia in actual play,
	# and the rank writes would pollute her real Elo.
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ChampionCard.GHOSTS_DIR + ghost["ghost_id"] + ".json")
	DirAccess.remove_absolute(ChampionCard.RANK_FILE)

	if failures == 0:
		print("PASS: champion card export/import/spawn/rank/loot all verified")
	get_tree().quit(0 if failures == 0 else 1)
