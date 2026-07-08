extends Node

const SAVE_DIR = "user://saves/"
var save_to_load: String = ""

# Per-save tutorial-seen bit (Natalia asked for this instead of the tutorial
# only tracking completion via the old global user://tutorial_completed.flag
# file, which didn't distinguish between save slots). Runtime state here,
# same pattern as save_to_load: written into every save_game() payload,
# restored by load_game(), and reset on New Game. TutorialManager.gd is the
# reader/writer; the legacy flag file is still honored as a fallback so
# players who already dismissed the tutorial under the old system don't see
# it replay.
var tutorial_completed: bool = false

# --- Difficulty (lives here because SaveManager is a global autoload) ------
# 0 Casual, 1 Normal, 2 Hard, 3 "Why would you do this to yourself?"
# The top tier keeps enemies NEAR-PEERS with the player's actual build
# power at all times - see SquadDirector's near-peer scaling.
const DIFFICULTY_NAMES = ["Casual", "Normal", "Hard", "Why would you do this to yourself?"]
# Per-wave HP growth base (old flat value was 1.10 for everyone)
const DIFFICULTY_HP_GROWTH = [1.08, 1.14, 1.20, 1.25]
# Wave enemy-count multiplier
const DIFFICULTY_COUNT_MULT = [0.7, 1.0, 1.3, 1.6]

var difficulty: int = 1

# Settings live at user:// (writable in exported builds - res:// is
# READ-ONLY once exported, so the old res://settings.cfg writes silently
# failed for players). SETTINGS_PATH is the single source of truth;
# SettingsMenu and MainMenu read the same constant. A one-time migration
# in _ready() carries any old res:// settings forward.
const SETTINGS_PATH = "user://settings.cfg"
const LEGACY_SETTINGS_PATH = "res://settings.cfg"

func set_difficulty(d: int):
	difficulty = clamp(d, 0, 3)
	var config = ConfigFile.new()
	config.load(SETTINGS_PATH) # keep existing sections if present
	config.set_value("Game", "Difficulty", difficulty)
	config.save(SETTINGS_PATH)

func _ready():
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")

	# One-time settings migration: res:// (legacy, read-only when exported)
	# -> user:// (writable everywhere).
	if not FileAccess.file_exists(SETTINGS_PATH) and FileAccess.file_exists(LEGACY_SETTINGS_PATH):
		var legacy = ConfigFile.new()
		if legacy.load(LEGACY_SETTINGS_PATH) == OK:
			legacy.save(SETTINGS_PATH)

	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		difficulty = clamp(int(config.get_value("Game", "Difficulty", 1)), 0, 3)

# SAVE FORMAT VERSION LOG (bump on any schema change; loaders are
# has()-guarded so old saves keep working, this is for humans + future
# migration code):
#   2 - original component/inventory/scrap format
#   3 - adds: valid_hexes + forbidden_tile_types per component, modifier
#       chips, mythic tile ability props (pattern/mode/focus/inverted/
#       repel/min_attract_rarity/trigger_key)
#   4 - persists tile power_lost, closing the "quit and reload to heal
#       fried tiles for free" loophole (permanence ruling: combat damage
#       disables tiles; only a Garage repair brings them back)
const SAVE_FORMAT_VERSION = 4

func save_game(save_name: String, mech: Node, inventory: Array):
	var data = {
		"version": SAVE_FORMAT_VERSION,
		"components": {},
		"inventory": [],
		"component_inventory": [],
		"scrap": 0,
		"tutorial_completed": tutorial_completed
	}

	# NOTE: was mech.get_parent() - that broke when the player mech moved
	# from being a direct child of Main to a child of Main.world (the
	# pixel-viewport game world). current_scene still resolves to Main
	# regardless of nesting depth.
	var main = mech.get_tree().current_scene if mech.is_inside_tree() else null

	if main and "player_scrap" in main:
		data["scrap"] = main.player_scrap
	if main and "player_modifier_chips" in main:
		data["modifier_chips"] = main.player_modifier_chips

	# Serialize Components
	for slot in mech.components.keys():
		data["components"][str(slot)] = _serialize_component(mech.components[slot])

	# Serialize Component Inventory
	if main and "player_component_inventory" in main:
		for comp in main.player_component_inventory:
			data["component_inventory"].append(_serialize_component(comp))
		
	# Serialize Inventory
	for tile in inventory:
		data["inventory"].append(_serialize_tile(tile))
		
	var file = FileAccess.open(SAVE_DIR + save_name + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_game(save_name: String) -> Dictionary:
	var path = SAVE_DIR + save_name + ".json"
	if not FileAccess.file_exists(path):
		return {}
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	if not json or typeof(json) != TYPE_DICTIONARY:
		return {}

	var result = {
		"components": {},
		"inventory": [],
		"component_inventory": [],
		"scrap": 0
	}

	# Restore the per-save tutorial-seen bit onto the singleton directly -
	# see the field's own comment above. Older saves without the key just
	# leave whatever's already there (governed by the legacy flag file).
	if json.has("tutorial_completed"):
		tutorial_completed = bool(json["tutorial_completed"])

	if json.has("scrap"):
		result["scrap"] = json["scrap"]
	if json.has("modifier_chips"):
		result["modifier_chips"] = json["modifier_chips"]

	
	var ScriptComponentEquipment = load("res://scripts/core/ComponentEquipment.gd")
	
	if json.has("components"):
		for slot_str in json["components"].keys():
			var cdata = json["components"][slot_str]
			var comp = _deserialize_component(cdata)
			if comp:
				result["components"][int(slot_str)] = comp
				
	if json.has("component_inventory"):
		for cdata in json["component_inventory"]:
			var comp = _deserialize_component(cdata)
			if comp:
				result["component_inventory"].append(comp)
			
	if json.has("inventory"):
		for tdata in json["inventory"]:
			var tile = _deserialize_tile(tdata)
			if tile:
				result["inventory"].append(tile)
				
	return result

func _serialize_component(comp) -> Dictionary:
	var comp_data = {
		"slot_type": comp.slot_type,
		"rarity": comp.rarity,
		"component_name": comp.component_name,
		"infusion_level": comp.get("infusion_level") if comp.get("infusion_level") != null else 0,
		"infusion_xp": comp.get("infusion_xp") if comp.get("infusion_xp") != null else 0,
		"stat_modifiers": comp.get("stat_modifiers") if comp.get("stat_modifiers") != null else {},
		"forbidden_tile_types": comp.get("forbidden_tile_types") if comp.get("forbidden_tile_types") != null else [],
		"tiles": [],
		"fixed_sinks": [],
		"valid_hexes": []
	}
	# The shape itself must persist: manual-hex upgrades and Black Market
	# oversized parts have shapes generate_shape() can't reproduce.
	for h in comp.valid_hexes:
		comp_data["valid_hexes"].append({"q": h.q, "r": h.r})
	for h in comp.fixed_sinks:
		comp_data["fixed_sinks"].append({"q": h.q, "r": h.r})
	for h in comp.hex_grid.grid.keys():
		var tile = comp.hex_grid.grid[h]
		comp_data["tiles"].append(_serialize_tile(tile))
	return comp_data

func _deserialize_component(cdata: Dictionary):
	var ScriptComponentEquipment = load("res://scripts/core/ComponentEquipment.gd")
	var slot_type = cdata.get("slot_type", 0)
	var rarity = cdata.get("rarity", 0)
	var comp = ScriptComponentEquipment.new(int(slot_type), int(rarity))
	comp.component_name = cdata.get("component_name", "Unknown")
	if cdata.has("infusion_level"): comp.set("infusion_level", cdata["infusion_level"])
	if cdata.has("infusion_xp"): comp.set("infusion_xp", cdata["infusion_xp"])
	if cdata.has("stat_modifiers"): comp.set("stat_modifiers", cdata["stat_modifiers"])
	if cdata.has("forbidden_tile_types"): comp.set("forbidden_tile_types", cdata["forbidden_tile_types"])
	comp.generate_shape()

	# Restore the exact saved shape over the generated default - required
	# for manual-hex upgrades and Black Market oversized parts to survive
	# a save/load round trip. Old saves without the key keep the default.
	if cdata.has("valid_hexes") and cdata["valid_hexes"] is Array and cdata["valid_hexes"].size() > 0:
		comp.valid_hexes.clear()
		for hdata in cdata["valid_hexes"]:
			comp.valid_hexes.append(HexCoord.new(int(hdata["q"]), int(hdata["r"])))

	if cdata.has("tiles"):
		for tdata in cdata["tiles"]:
			var tile = _deserialize_tile(tdata)
			if tile and tile.grid_position:
				comp.hex_grid.add_tile(tile.grid_position, tile)
				
	comp.fixed_sinks.clear()
	if cdata.has("fixed_sinks"):
		for hdata in cdata["fixed_sinks"]:
			comp.fixed_sinks.append(HexCoord.new(int(hdata["q"]), int(hdata["r"])))
	else:
		for h in comp.hex_grid.grid.keys():
			var tile = comp.hex_grid.grid[h]
			if tile.tile_type == "Component Link" and tile.get("is_fixed"):
				comp.fixed_sinks.append(HexCoord.new(h.x, h.y))
			elif tile.tile_type == "Core Reactor" or tile.tile_type == "Weapon Mount" or tile.tile_type == "Actuator" or tile.tile_type == "Torso Return" or tile.tile_type == "Energy Intake" or tile.tile_type == "Backpack Link" or tile.tile_type == "Accessory Return":
				comp.fixed_sinks.append(HexCoord.new(h.x, h.y))
				
	# Backwards compatibility: Ensure peripheral components have an entry point at (0,0)
	if comp.slot_type != HexTile.BodySlot.TORSO and not comp.hex_grid.has_tile(HexCoord.new(0, 0)):
		if comp.slot_type == HexTile.BodySlot.HEAD or comp.slot_type == HexTile.BodySlot.BACKPACK:
			var tor_link = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
			tor_link.tile_type = "Torso Return"
			tor_link.body_slot = comp.slot_type
			comp.hex_grid.add_tile(HexCoord.new(0, 0), tor_link)
		else:
			var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
			intake.tile_type = "Energy Intake"
			intake.body_slot = comp.slot_type
			comp.hex_grid.add_tile(HexCoord.new(0, 0), intake)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
		
	return comp

func _serialize_tile(tile) -> Dictionary:
	var data = {
		"script_path": tile.get_script().resource_path,
		"tile_type": tile.tile_type,
		"category": tile.category,
		"rarity": tile.rarity,
		"body_slot": tile.body_slot,
		"level": tile.level,
		"q": tile.grid_position.q if tile.grid_position else 0,
		"r": tile.grid_position.r if tile.grid_position else 0
	}
	
	if tile.tile_type == "Splitter":
		data["active_faces"] = tile.active_faces
	elif tile.tile_type == "Core Reactor" or tile.tile_type == "Microcore":
		data["active_faces"] = tile.active_faces
		data["face_outputs"] = tile.face_outputs
	elif tile.tile_type == "Elemental Infuser":
		data["secondary_synergy"] = tile.secondary_synergy
	elif tile.tile_type == "Catalyst":
		data["target_synergy"] = tile.target_synergy
	elif "rotation_steps" in tile:
		data["rotation_steps"] = tile.rotation_steps
	elif tile.tile_type == "Component Link" or tile.tile_type == "Actuator" or tile.tile_type == "Torso Return" or tile.tile_type == "Backpack Link":
		data["target_slot"] = tile.get("target_slot")
		data["is_fixed"] = tile.get("is_fixed")
	elif tile.tile_type == "Drone Bay":
		# The Drone Bay is the one tile that owns a whole nested
		# ComponentEquipment (the drone's own hex-grid loadout) rather than a
		# few flat fields - recurse through the same component serializer
		# used for top-level body-slot components so a player-customized
		# drone loadout survives a save/load round trip instead of silently
		# resetting to its default weapon mount.
		if tile.drone_loadout:
			data["drone_loadout"] = _serialize_component(tile.drone_loadout)

	# Mythic ability state - generic sweep so every current and future
	# mythic toggle persists without this list needing per-type branches.
	for prop in ["mythic_pattern", "mythic_mode", "mythic_focus", "inverted", "repel_mode", "min_attract_rarity", "trigger_key", "power_lost"]:
		if prop in tile:
			data[prop] = tile.get(prop)

	return data

func _deserialize_tile(data: Dictionary):
	if not data.has("script_path"): return null
	
	var script = load(data["script_path"])
	if not script: return null
	
	var tile
	if data["script_path"].ends_with("ComponentLinkTile.gd"):
		tile = script.new(int(data.get("target_slot", 0)), bool(data.get("is_fixed", false)))
	else:
		tile = script.new()
		
	tile.tile_type = data.get("tile_type", "Unknown")
	tile.category = int(data.get("category", 0))
	tile.rarity = int(data.get("rarity", 0))
	tile.body_slot = int(data.get("body_slot", 0))
	tile.level = int(data.get("level", 1))
	tile.grid_position = HexCoord.new(int(data.get("q", 0)), int(data.get("r", 0)))
	
	if tile.tile_type == "Splitter":
		tile.active_faces.clear()
		var faces = data.get("active_faces", [])
		for f in faces: tile.active_faces.append(int(f))
	elif tile.tile_type == "Elemental Infuser":
		if data.has("secondary_synergy"):
			tile.secondary_synergy = int(data["secondary_synergy"])
	elif tile.tile_type == "Catalyst":
		if data.has("target_synergy"):
			tile.target_synergy = int(data["target_synergy"])
	elif tile.tile_type == "Core Reactor" or tile.tile_type == "Microcore":
		tile.active_faces.clear()
		var faces = data.get("active_faces", [])
		for f in faces: tile.active_faces.append(int(f))
		var fo = data.get("face_outputs", {})
		for k in fo.keys():
			tile.face_outputs[int(k)] = int(fo[k])
	elif "rotation_steps" in tile:
		tile.rotation_steps = int(data.get("rotation_steps", 1))

	if tile.tile_type == "Drone Bay" and data.has("drone_loadout"):
		tile.drone_loadout = _deserialize_component(data["drone_loadout"])

	# Mythic ability state (see _serialize_tile's generic sweep)
	for prop in ["mythic_pattern", "mythic_mode", "mythic_focus", "inverted", "repel_mode", "min_attract_rarity", "trigger_key", "power_lost"]:
		if data.has(prop) and prop in tile:
			tile.set(prop, data[prop])

	return tile

func get_save_files() -> Array[String]:
	var saves: Array[String] = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				if not file_name.begins_with("loadout_"):
					saves.append(file_name.replace(".json", ""))
			file_name = dir.get_next()
	return saves

func save_loadout(slot_index: int, mech: Node):
	var data = {
		"version": SAVE_FORMAT_VERSION,
		"components": {}
	}
	for slot in mech.components.keys():
		data["components"][str(slot)] = _serialize_component(mech.components[slot])
		
	var file = FileAccess.open(SAVE_DIR + "loadout_" + str(slot_index) + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_loadout(slot_index: int, mech: Node, inventory: Array) -> bool:
	var path = SAVE_DIR + "loadout_" + str(slot_index) + ".json"
	if not FileAccess.file_exists(path):
		return false
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	
	if not json or typeof(json) != TYPE_DICTIONARY or not json.has("components"):
		return false
		
	var components = json["components"]
	# Load new components
	var new_comps = {}
	for slot_str in components.keys():
		var slot = int(slot_str)
		new_comps[slot] = _deserialize_component(components[slot_str])
		
	# Swap them onto the mech
	mech.components = new_comps
	mech.is_grid_dirty = true
	return true

# --- Per-component loadout slots (FEATURE_ROADMAP.md group 1) --------------
# Full-build loadouts (above) snapshot the entire mech; these snapshot ONE
# component - its shape, rarity, and complete tile wiring - so a favorite
# arm or torso circuit can be reused across otherwise different builds.
# Files are keyed by body-slot type AND slot index, so a saved Left Arm can
# never be loaded onto a Torso.

func save_component_loadout(slot_index: int, comp) -> bool:
	if not comp:
		return false
	var data = {
		"version": 1,
		"slot_type": comp.slot_type,
		"component": _serialize_component(comp),
	}
	var path = SAVE_DIR + "comp_loadout_" + str(comp.slot_type) + "_" + str(slot_index) + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

# Returns a fresh ComponentEquipment, or null if the slot is empty / wrong type.
func load_component_loadout(slot_index: int, slot_type: int):
	var path = SAVE_DIR + "comp_loadout_" + str(slot_type) + "_" + str(slot_index) + ".json"
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	if not json or typeof(json) != TYPE_DICTIONARY or not json.has("component"):
		return null
	if int(json.get("slot_type", -1)) != slot_type:
		return null
	return _deserialize_component(json["component"])

func has_component_loadout(slot_index: int, slot_type: int) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "comp_loadout_" + str(slot_type) + "_" + str(slot_index) + ".json")
