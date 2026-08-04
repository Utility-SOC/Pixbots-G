extends Node

# Regression check for Phase 2 of the AI-tactics Rust-cutover plan (see
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md) -
# SightAndSearchBatcher.gd's sight-check gate (range + Phase 1 grid-LOS +
# blind-field short-circuit), replacing the old per-mech
# PhysicsRayQueryParameters2D call in SightAndSearch._update_player_sight.
#
# Uses real Mech/MapGenerator/JammerField instances (same convention as
# JammerWiringCheck.gd), with the map's obstacles overridden to a
# deterministic wall (same synthetic layout as SolidGridLosCheck.gd) so LOS
# outcomes are hand-verifiable instead of depending on random generation.

const MechScript = preload("res://scripts/entities/Mech.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const JammerFieldScript = preload("res://scripts/visuals/JammerField.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var map = MapGeneratorScript.new()
	map.map_type = "Tabletop"
	world.add_child(map) # _ready() generates synchronously

	# Deterministic obstacle wall (x=10, y=5..14), same layout as
	# SolidGridLosCheck.gd - overrides whatever the real generation produced.
	map.obstacles = {}
	for y in range(5, 15):
		map.obstacles[Vector2i(10, y)] = "Boulder"
	SolidGridBatcher._ensure_rust()
	if not SolidGridBatcher._rasterizer:
		print("SKIPPED: SolidGridRs not built (DLL missing)")
		get_tree().quit(0)
		return
	SolidGridBatcher._rebuild_grid(map)
	SolidGridBatcher._last_obstacle_count = map.obstacles.size()

	var ts = float(map.tile_size)
	var row9_y = 9 * ts + ts / 2.0

	var player = MechScript.new()
	player.is_player = true
	player.global_position = Vector2(2 * ts + ts / 2.0, row9_y)
	world.add_child(player)

	# Case 1: same row, both left of the wall (x=10) - clear LOS, in range.
	var enemy_clear = MechScript.new()
	enemy_clear.is_player = false
	enemy_clear.target = player
	enemy_clear.global_position = Vector2(4 * ts + ts / 2.0, row9_y)
	world.add_child(enemy_clear)

	# Case 2: same row, on the far side of the wall - in range, LOS blocked.
	var enemy_blocked = MechScript.new()
	enemy_blocked.is_player = false
	enemy_blocked.target = player
	enemy_blocked.global_position = Vector2(18 * ts + ts / 2.0, row9_y)
	world.add_child(enemy_blocked)

	# Case 3: clear LOS but well outside SIGHT_RANGE - range gate should
	# deny it before ever reaching a grid-LOS query.
	var enemy_far = MechScript.new()
	enemy_far.is_player = false
	enemy_far.target = player
	enemy_far.global_position = player.global_position + Vector2(Mech.SIGHT_RANGE * 5.0, 0)
	world.add_child(enemy_far)

	await get_tree().physics_frame
	await get_tree().physics_frame

	if not enemy_clear.has_sight_of_player:
		push_error("FAIL: clear-LOS in-range enemy should have gained sight")
		failures += 1
	else:
		print("PASS: clear-LOS in-range enemy gained sight")

	if enemy_blocked.has_sight_of_player:
		push_error("FAIL: wall-blocked enemy should NOT have sight")
		failures += 1
	else:
		print("PASS: wall-blocked enemy correctly denied sight")

	if enemy_far.has_sight_of_player:
		push_error("FAIL: out-of-range enemy should NOT have sight (range gate)")
		failures += 1
	else:
		print("PASS: out-of-range enemy correctly denied sight (range gate)")

	# Case 4: blind field - a player-owned JammerField should deny sight and
	# snap last_known_player_pos to the field's own position. Field anchored
	# AT the player's own position (not somewhere else) so JammerField's
	# built-in anchor-lag easing toward owner_mech.global_position - a real,
	# intentional per-frame behavior, see JammerField.gd's _process - has
	# nothing to drift toward and stays put for a stable assertion; enemy
	# moved well inside the field's radius (same offset JammerWiringCheck.gd
	# already uses for this exact scenario) rather than reusing its
	# case-1 position.
	var field = JammerFieldScript.new()
	field.global_position = player.global_position
	field.setup(player, 200.0)
	world.add_child(field)
	enemy_clear.global_position = player.global_position + Vector2(20, 0)
	enemy_clear.has_sight_of_player = false # reset from case 1's result
	await get_tree().physics_frame
	await get_tree().physics_frame

	if enemy_clear.has_sight_of_player:
		push_error("FAIL: enemy standing inside player's jammer field should be blinded")
		failures += 1
	elif enemy_clear.last_known_player_pos != field.global_position:
		push_error("FAIL: blinded enemy's last_known_player_pos should snap to the field's position, got %s want %s" % [enemy_clear.last_known_player_pos, field.global_position])
		failures += 1
	else:
		print("PASS: blind-field enemy denied sight, last_known_player_pos snapped to field position")

	if failures == 0:
		print("PASS: SightAndSearchBatcherCheck - range/LOS/blind gates all correct")
	get_tree().quit(0 if failures == 0 else 1)
