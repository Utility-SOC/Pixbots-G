extends Node

const SAVE_DIR = "user://saves/"
var save_to_load: String = ""

func _ready():
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")

func save_game(save_name: String, mech: Node, inventory: Array):
	var data = {
		"version": 2,
		"components": {},
		"inventory": [],
		"component_inventory": [],
		"scrap": 0
	}
	
	if "player_scrap" in mech.get_parent():
		data["scrap"] = mech.get_parent().player_scrap

	
	# Serialize Components
	for slot in mech.components.keys():
		data["components"][str(slot)] = _serialize_component(mech.components[slot])
		
	# Serialize Component Inventory
	if "player_component_inventory" in mech.get_parent():
		for comp in mech.get_parent().player_component_inventory:
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
	
	if json.has("scrap"):
		result["scrap"] = json["scrap"]

	
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
		"tiles": [],
		"fixed_sinks": []
	}
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
	comp.generate_shape()
	
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
		"version": 2,
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
