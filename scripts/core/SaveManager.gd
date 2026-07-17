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

# Tournament arc scaffold (Natalia, decision #12 on the Narrative/Rival
# design pass): placeholder plumbing only - nothing sets this true yet, since
# it's meant to unlock on the Level 100 milestone and the milestone/Round
# system doesn't exist yet either. Same pattern as tutorial_completed above:
# a simple per-save singleton flag, written into save_game()'s payload and
# restored in load_game(). MainMenu.gd reads it to show the Tournament mode
# button locked or unlocked. When the real milestone system lands, it just
# needs to set this to true and call save_game() - no other plumbing needed.
var tournament_arc_unlocked: bool = false

# Whether this save has ever beaten (or even reached) the first boss (wave 5,
# non-mega). Gates the one-time "First boss" dialogue pair in STORY_SCRIPT.md
# (get_first_boss_intro()/get_first_boss_defeat()) vs. the regular rotating
# boss_defeats pool for every subsequent boss. Same per-save singleton-flag
# pattern as tournament_arc_unlocked above.
var first_boss_encountered: bool = false

# Tracks the highest wave ever achieved on this save file (used to unlock Boss Rush).
var max_wave_reached: int = 1

# Runtime flag set by the main menu so Main.gd knows what mode to launch.
var current_game_mode: String = "normal"

# --- Difficulty (lives here because SaveManager is a global autoload) ------
# 0 Casual, 1 Normal, 2 Hard, 3 "Why would you do this to yourself?"
# The top tier keeps enemies NEAR-PEERS with the player's actual build
# power at all times - see SquadDirector's near-peer scaling.
const DIFFICULTY_NAMES = ["Casual", "Normal", "Hard", "Why would you do this to yourself?"]
# Per-wave HP growth base (old flat value was 1.10 for everyone)
const DIFFICULTY_HP_GROWTH = [1.08, 1.14, 1.20, 1.25]
# Wave enemy-count multiplier
const DIFFICULTY_COUNT_MULT = [0.7, 1.0, 1.3, 1.6]
# Where per-wave HP growth stops compounding and goes linear - see
# wave_hp_multiplier below.
const WAVE_HP_KNEE = 25

# THE per-wave enemy HP multiplier - every scaling site must use this, not
# its own pow() (two copies of that formula had already appeared).
# Pure exponential growth walls out the long game: at Normal's 1.14 the old
# pow(growth, wave-1) hits ~610x by wave 50 and ~430,000x by wave 100 -
# and Boss Rush is GATED on reaching wave 100 - while a player's damage
# curve grows a few dozen x over the same run at best. The exponential now
# runs only to WAVE_HP_KNEE (by which point it already outpaces any
# realistic build curve), then continues LINEARLY at that difficulty's
# per-wave rate. Wave-100 multipliers per difficulty: ~47x / ~300x /
# ~1500x / ~5200x (previously ~2000x / ~430k / ~69M / ~3.9B).
static func wave_hp_multiplier(p_difficulty: int, wave: int) -> float:
	var growth = DIFFICULTY_HP_GROWTH[clamp(p_difficulty, 0, DIFFICULTY_HP_GROWTH.size() - 1)]
	var n = max(0, wave - 1)
	var mult = pow(growth, min(n, WAVE_HP_KNEE))
	if n > WAVE_HP_KNEE:
		mult *= 1.0 + (growth - 1.0) * (n - WAVE_HP_KNEE)
	return mult

var difficulty: int = 1

# Install-wide (not per-save) identity used to attribute AI profiles shared
# via the War Room's export/import clipboard flow - when an imported
# template collides by name with one you already have, the importer's
# pilot_name gets appended to disambiguate instead of silently overwriting
# your own learned progress (see SquadDirector._merge_learned). Same
# ConfigFile as difficulty above, not tied to any single save slot since a
# pilot's identity for sharing purposes isn't campaign-specific.
var pilot_name: String = "Unknown Pilot"

func set_pilot_name(name: String):
	pilot_name = name.strip_edges() if name.strip_edges() != "" else "Unknown Pilot"
	var config = ConfigFile.new()
	config.load(SETTINGS_PATH) # keep existing sections if present
	config.set_value("Game", "PilotName", pilot_name)
	config.save(SETTINGS_PATH)

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
		pilot_name = str(config.get_value("Game", "PilotName", "Unknown Pilot"))

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
		"tutorial_completed": tutorial_completed,
		"tournament_arc_unlocked": tournament_arc_unlocked,
		"first_boss_encountered": first_boss_encountered,
		"max_wave_reached": max_wave_reached
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
	# The run's wave counter - was never serialized, so loading a save
	# silently restarted the run at wave 1 while keeping the gear.
	if main and "current_wave" in main:
		data["current_wave"] = main.current_wave
	if main and "player_sponsorship" in main:
		data["player_sponsorship"] = main.player_sponsorship

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
		"scrap": 0,
		"max_wave_reached": 1
	}

	# Restore the per-save tutorial-seen bit onto the singleton directly -
	# see the field's own comment above. Older saves without the key just
	# leave whatever's already there (governed by the legacy flag file).
	if json.has("tutorial_completed"):
		tutorial_completed = bool(json["tutorial_completed"])

	# See tournament_arc_unlocked's own comment above - older saves without
	# the key just stay locked, same has()-guarded pattern as everything else
	# in this loader.
	if json.has("tournament_arc_unlocked"):
		tournament_arc_unlocked = bool(json["tournament_arc_unlocked"])
	else:
		tournament_arc_unlocked = false

	# See first_boss_encountered's own comment above - older saves without the
	# key are treated as "not yet encountered" so they still get the one-time
	# dialogue on their next boss wave, rather than silently skipping it.
	if json.has("first_boss_encountered"):
		first_boss_encountered = bool(json["first_boss_encountered"])
	else:
		first_boss_encountered = false

	if json.has("max_wave_reached"):
		max_wave_reached = int(json["max_wave_reached"])
		result["max_wave_reached"] = max_wave_reached
	else:
		max_wave_reached = 1
		result["max_wave_reached"] = 1

	if json.has("scrap"):
		result["scrap"] = json["scrap"]
	if json.has("modifier_chips"):
		result["modifier_chips"] = json["modifier_chips"]
	if json.has("current_wave"):
		result["current_wave"] = int(json["current_wave"])
	if json.has("player_sponsorship"):
		result["player_sponsorship"] = str(json["player_sponsorship"])

	
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
	# get_all_tiles() (not raw .grid.keys()) - a multi-cell tile (Lance -
	# see HexTile.footprint_offsets) occupies several grid keys but is one
	# logical tile; the raw keys loop this replaced would have serialized
	# it once per occupied key, producing duplicate tile resources on load.
	for tile in comp.hex_grid.get_all_tiles():
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

	# Safety net: a tile must never sit OUTSIDE its component's footprint.
	# Legacy pre-v3 loadout files carried no valid_hexes, so a random
	# regenerated shape could land under saved tiles - producing hexes you
	# could clear but never re-place. Absorb any stray tile's hex into the
	# footprint instead.
	for h in comp.hex_grid.grid.keys():
		var covered = false
		for v in comp.valid_hexes:
			if v.q == h.x and v.r == h.y:
				covered = true
				break
		if not covered:
			comp.valid_hexes.append(HexCoord.new(h.x, h.y))
				
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

	# Re-orient any Energy Intake tile now that the component's real shape is
	# fully settled - the custom-valid_hexes override above, the stray-tile
	# absorption loop, and the backwards-compat block can all still change
	# valid_hexes after generate_shape() already built _valid_hex_set once,
	# so it must be rebuilt before re-deriving orientation from it.
	# active_faces was never part of Energy Intake's serialized data (see
	# _serialize_tile/_deserialize_tile - only Splitter/Core Reactor/
	# Microcore save it), so a saved/named loadout always deserialized the
	# intake back to ComponentLinkTile's class-level default (direction 0,
	# East) instead of keeping whatever direction ComponentEquipment.
	# _orient_intake_to_shape() picked when the part was first built -
	# playtest report: "worked last time" (freshly generated), broken again
	# after loading a saved build (deserialized, orientation lost).
	comp._rebuild_valid_hex_set()
	for tile in comp.hex_grid.get_all_tiles():
		if tile.tile_type == "Energy Intake":
			ScriptComponentEquipment._orient_intake_to_shape(comp, tile, tile.grid_position)
		
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
	if tile.footprint_offsets.size() > 0:
		data["footprint_offsets"] = []
		for off in tile.footprint_offsets:
			data["footprint_offsets"].append({"x": off.x, "y": off.y})

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
		data["visual_class"] = tile.visual_class

	# Mythic ability state - generic sweep so every current and future
	# mythic toggle persists without this list needing per-type branches.
	# The tail entries are the tile-config knobs (Resonator per-path
	# dropoff, Splitter ratios, Accumulator auto-dump, Catalyst gating) -
	# same sweep, JSON-safe types only (Arrays/floats/ints/strings).
	for prop in ["mythic_pattern", "mythic_mode", "mythic_focus", "inverted", "repel_mode", "min_attract_rarity", "trigger_key", "power_lost", "sync_dropoff_per_path", "output_ratios", "auto_dump_threshold", "gate_min_magnitude", "gate_every_n"]:
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
	if data.has("footprint_offsets"):
		tile.footprint_offsets = []
		for off in data["footprint_offsets"]:
			tile.footprint_offsets.append(Vector2i(int(off.x), int(off.y)))

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

	if tile.tile_type == "Drone Bay":
		if data.has("drone_loadout"):
			tile.drone_loadout = _deserialize_component(data["drone_loadout"])
		if data.has("visual_class"):
			tile.visual_class = int(data["visual_class"])

	# Mythic ability state + tile-config knobs (see _serialize_tile's sweep)
	for prop in ["mythic_pattern", "mythic_mode", "mythic_focus", "inverted", "repel_mode", "min_attract_rarity", "trigger_key", "power_lost", "sync_dropoff_per_path", "output_ratios", "auto_dump_threshold", "gate_min_magnitude", "gate_every_n"]:
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

# Lightweight peek at a save's max_wave_reached without doing the full
# component/tile-grid deserialization load_game() does - lets MainMenu
# compare progress across every save file cheaply (Natalia: "Continue
# should pick up from the highest level I've made it to", not just
# whichever save happens to be named "autosave" or sorts last).
func peek_max_wave(save_name: String) -> int:
	var path = SAVE_DIR + save_name + ".json"
	if not FileAccess.file_exists(path):
		return 0
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return 0
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	if not json or typeof(json) != TYPE_DICTIONARY:
		return 0
	return int(json.get("max_wave_reached", 1))

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
	return load_loadout_file(SAVE_DIR + "loadout_" + str(slot_index) + ".json", mech)

# Shared by the legacy numbered quick-slots and the named-slot system below.
func load_loadout_file(path: String, mech: Node) -> bool:
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

	# Swap them onto the mech PROPERLY - through unequip/equip, not a raw
	# dict assignment. The old assignment left the previous component nodes
	# parented to the mech forever (leak + ghost grids) and never
	# add_child'd the new ones, which is how loadout loads produced the
	# "tiles outside the footprint that can be removed but never replaced"
	# stuck state (playtest report).
	for slot in mech.components.keys().duplicate():
		var old = mech.unequip_component(slot)
		if old:
			old.queue_free()
	for slot in new_comps.keys():
		if new_comps[slot]:
			mech.equip_component(new_comps[slot])
	mech.is_grid_dirty = true
	return true

# --- Named, unlimited build/part slots (design ruling: "a wider variety of
# builds ... not just 3 slots") ---------------------------------------------
# One file per slot under user://loadouts/. Full builds are the same JSON
# shape as the numbered quick-slots (which still work and are listed as
# "Quick Slot N"); parts carry their body-slot type so a saved arm can
# never land on a torso.
const NAMED_LOADOUT_DIR = "user://loadouts/"

func _slot_filename(display_name: String) -> String:
	var s = display_name.validate_filename().replace(" ", "_").to_lower()
	return s if s != "" else "unnamed"

func save_named_loadout(display_name: String, mech: Node) -> bool:
	DirAccess.make_dir_recursive_absolute(NAMED_LOADOUT_DIR)
	var data = {
		"version": SAVE_FORMAT_VERSION,
		"display_name": display_name,
		"components": {},
	}
	for slot in mech.components.keys():
		data["components"][str(slot)] = _serialize_component(mech.components[slot])
	var f = FileAccess.open(NAMED_LOADOUT_DIR + "full_" + _slot_filename(display_name) + ".json", FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

# [{name, path}] - named slots plus any legacy numbered quick-slots.
func list_named_loadouts() -> Array:
	var out: Array = []
	var dir = DirAccess.open(NAMED_LOADOUT_DIR)
	if dir:
		for file in dir.get_files():
			if file.begins_with("full_") and file.ends_with(".json"):
				var f = FileAccess.open(NAMED_LOADOUT_DIR + file, FileAccess.READ)
				if not f:
					continue
				var json = JSON.parse_string(f.get_as_text())
				f.close()
				if json is Dictionary and json.has("components"):
					out.append({"name": str(json.get("display_name", file)), "path": NAMED_LOADOUT_DIR + file})
	for i in range(1, 4):
		var legacy = SAVE_DIR + "loadout_" + str(i) + ".json"
		if FileAccess.file_exists(legacy):
			out.append({"name": "Quick Slot " + str(i), "path": legacy})
	return out

func delete_named_loadout(path: String) -> bool:
	# Only files our two loadout systems own - never arbitrary paths.
	if not (path.begins_with(NAMED_LOADOUT_DIR) or (path.begins_with(SAVE_DIR) and path.get_file().begins_with("loadout_"))):
		return false
	return DirAccess.remove_absolute(path) == OK

func save_named_component(display_name: String, comp) -> bool:
	if not comp:
		return false
	DirAccess.make_dir_recursive_absolute(NAMED_LOADOUT_DIR)
	var data = {
		"version": 1,
		"display_name": display_name,
		"slot_type": comp.slot_type,
		"component": _serialize_component(comp),
	}
	var f = FileAccess.open(NAMED_LOADOUT_DIR + "part_%d_%s.json" % [comp.slot_type, _slot_filename(display_name)], FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func list_named_components(slot_type: int) -> Array:
	var out: Array = []
	var dir = DirAccess.open(NAMED_LOADOUT_DIR)
	if dir:
		var prefix = "part_%d_" % slot_type
		for file in dir.get_files():
			if file.begins_with(prefix) and file.ends_with(".json"):
				var f = FileAccess.open(NAMED_LOADOUT_DIR + file, FileAccess.READ)
				if not f:
					continue
				var json = JSON.parse_string(f.get_as_text())
				f.close()
				if json is Dictionary and json.has("component"):
					out.append({"name": str(json.get("display_name", file)), "path": NAMED_LOADOUT_DIR + file})
	return out

# Returns a fresh ComponentEquipment or null; slot_type must match.
func load_named_component(path: String, slot_type: int):
	if not FileAccess.file_exists(path):
		return null
	var f = FileAccess.open(path, FileAccess.READ)
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	if not (json is Dictionary) or int(json.get("slot_type", -1)) != slot_type:
		return null
	return _deserialize_component(json["component"])

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
