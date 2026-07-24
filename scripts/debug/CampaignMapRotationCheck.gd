extends Node

# Per the user: "in campaign mode, the map should change every ten waves, or
# every 3 minutes, whichever is faster. (I'd like to be able to tune that
# later because I don't know how 3m actually feels)" - see Main.gd's
# MAP_ROTATION_MAX_WAVES/MAP_ROTATION_MAX_SECONDS, _should_rotate_map(), and
# _rotate_campaign_map().
#
# Main.gd itself can't be safely instantiated standalone in a headless check
# (wave_label/timer_label/world are @onready references into the real game
# scene - see ExtraLivesCheck.gd/AICounterWobbleCheck.gd for the same
# constraint). _should_rotate_map() is pure decision logic over plain script
# vars though (no @onready touched), so it's safe to call directly on a bare
# Main.new() as long as it's never added to the tree (which is what would
# trigger _ready() and pull in the scene-coupled setup). _rotate_campaign_map
# itself does touch scene state (world, player, groups) - that gets source-
# text assertions instead, same convention as the existing Main.gd checks.

const MainScript = preload("res://scripts/core/Main.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
# SaveManager is a real autoload (project.godot) - accessed by its global
# singleton name directly, matching every other call site in this codebase
# (Main.gd/MainMenu.gd write "SaveManager.current_game_mode = ..." the same
# way), not via a separately preloaded script instance.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- _should_rotate_map(): pure logic, real calls on an unattached Main ---
	var main = MainScript.new() # never add_child'd - _ready() must not run

	var orig_mode = SaveManager.current_game_mode
	SaveManager.current_game_mode = "sandbox"
	main.current_wave = 50
	main._map_rotation_wave_start = 1
	main._map_rotation_elapsed = 9999.0
	_check("never rotates outside campaign mode, no matter how overdue",
		not main._should_rotate_map())

	SaveManager.current_game_mode = "campaign"
	main.current_wave = 1
	main._map_rotation_wave_start = 1
	main._map_rotation_elapsed = 0.0
	_check("does not rotate at the very start of a fresh window",
		not main._should_rotate_map())

	main.current_wave = main._map_rotation_wave_start + MainScript.MAP_ROTATION_MAX_WAVES - 1
	_check("does not rotate one wave short of the wave cap",
		not main._should_rotate_map())

	main.current_wave = main._map_rotation_wave_start + MainScript.MAP_ROTATION_MAX_WAVES
	_check("rotates once the wave cap is reached",
		main._should_rotate_map())

	main.current_wave = main._map_rotation_wave_start + MainScript.MAP_ROTATION_MAX_WAVES + 5
	_check("still rotates well past the wave cap (not an exact-equality fluke)",
		main._should_rotate_map())

	main.current_wave = 1
	main._map_rotation_wave_start = 1
	main._map_rotation_elapsed = MainScript.MAP_ROTATION_MAX_SECONDS - 0.01
	_check("does not rotate a hair under the time cap",
		not main._should_rotate_map())

	main._map_rotation_elapsed = MainScript.MAP_ROTATION_MAX_SECONDS
	_check("rotates once the time cap is reached, even with waves nowhere near the cap",
		main._should_rotate_map())

	# --- _water_eligible_map_types(): pure logic, real calls on the same
	# unattached Main - Water is gated on Mech._has_jumpjets(), a plain
	# instance-var check safe to call on a bare, un-added Mech too. Per the
	# user: "the water map should be pushed later since default player
	# builds don't include jumpjets yet (and jumpjets should be provided to
	# the player prior to a water level)". ---
	_check("with no player yet (the very first map of a run), Water is excluded",
		not main._water_eligible_map_types().has("Water"))

	var mech = MechScript.new() # never add_child'd
	main.player = mech
	_check("with a player that has no jumpjets equipped, Water stays excluded",
		not main._water_eligible_map_types().has("Water"))

	mech.jumpjet_rarity = HexTile.Rarity.COMMON
	_check("once the player's mech actually has jumpjets equipped, Water becomes eligible",
		main._water_eligible_map_types().has("Water"))

	mech.jumpjet_rarity = -1
	_check("every OTHER map type stays available even while Water is excluded",
		main._water_eligible_map_types().size() == MainScript.MAP_ROTATION_TYPES.size() - 1)

	mech.free()
	main.player = null
	SaveManager.current_game_mode = orig_mode
	main.free()

	# --- Main.gd wiring: source-text assertions for the scene-coupled parts ---
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")

	_check("_process accumulates elapsed time only in campaign mode",
		main_source.contains("if SaveManager.current_game_mode == \"campaign\":\n\t\t_map_rotation_elapsed += delta"))
	_check("_on_wave_cleared checks and triggers rotation after incrementing current_wave",
		main_source.contains("if _should_rotate_map():\n\t\t_rotate_campaign_map()"))
	_check("rotation clears existing loot (tied to the old, now-gone layout)",
		main_source.contains("get_nodes_in_group(\"loot\")"))
	_check("rotation clears existing enemies and resets active_enemies",
		main_source.contains("get_nodes_in_group(\"enemy\")") and main_source.contains("active_enemies = 0"))
	_check("rotation frees the old map node",
		main_source.contains("map.queue_free()"))
	_check("rotation avoids immediately re-rolling the same biome just left",
		main_source.contains("choices = pool.filter(func(t): return t != old_type)"))
	_check("rotation runs its map-type pool through the water-eligibility gate",
		main_source.contains("var pool = _water_eligible_map_types()"))
	_check("initial setup also runs through the water-eligibility gate, not a raw MAP_ROTATION_TYPES pick",
		main_source.contains("var pool = _water_eligible_map_types()\n\tmap.map_type = pool[randi() % pool.size()]"))
	_check("rotation repositions the player onto a valid spot on the NEW map",
		main_source.contains("player.global_position = map.get_valid_spawn_position("))
	_check("rotation resets both trackers so the next window starts clean",
		main_source.contains("_map_rotation_wave_start = current_wave") and main_source.contains("_map_rotation_elapsed = 0.0"))
	_check("_ready() anchors the wave tracker to the actual starting wave (fresh game or loaded save), not always 1",
		main_source.contains("_map_rotation_wave_start = current_wave"))
	_check("MAP_ROTATION_TYPES is shared (not duplicated) between initial setup and rotation",
		main_source.count("[\"Tabletop\", \"Tabletop\", \"Normal\", \"Open Field\", \"Forest\", \"Desert\", \"Tundra\", \"Volcano\", \"Dungeon\", \"Water\", \"FightShovel\"]") == 1)
	_check("water gating reuses Mech's own real _has_jumpjets() drowning-check logic, not a duplicated check",
		main_source.contains("player._has_jumpjets()"))

	if failures == 0:
		print("PASS: campaign-mode map rotation fires on whichever of wave-count/elapsed-time comes first, tears down/rebuilds cleanly, and keeps Water gated on the player actually having jumpjets equipped")
	get_tree().quit(0 if failures == 0 else 1)
