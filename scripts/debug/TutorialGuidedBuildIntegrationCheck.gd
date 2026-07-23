extends Node

# Integration harness for TutorialManager's guided-build wiring (the
# "type": "guided_build" step handling added for the hand-over-hand
# walkthrough). GuidedBuildPlannerCheck.gd/GuidedBuildRunnerCheck.gd
# already cover the underlying plan/runner logic in isolation - this
# verifies the GLUE: readiness gating (won't start until the right
# component tab is actually active), that the spotlight-on-hex geometry
# call doesn't crash against a real GarageGridRenderer, and that
# completing the plan actually advances the OUTER tutorial step_index.
#
# Uses a lightweight stub for "garage_ui" (exposing only the fields
# TutorialManager actually reads: grid_renderer/mech_components/inventory/
# active_component) rather than a full GarageMenu, since GarageMenu's own
# _ready() builds a large UI tree unrelated to what's under test here.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const TutorialManagerScript = preload("res://scripts/ui/TutorialManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

class GarageStub:
	extends Node
	var grid_renderer = null
	var mech_components: Dictionary = {}
	var inventory: Array = []
	var active_component = null

class MainStub:
	extends Node
	var garage_ui = null

func _ready():
	SaveManager.tutorial_completed = false

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(-1, 0), HexCoord.new(-2, 0)]
	torso.valid_hexes = hexes
	torso._rebuild_valid_hex_set()
	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var l_arm_sink = ComponentLinkTileScript.new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(-2, 0), l_arm_sink)
	var sinks: Array[HexCoord] = [HexCoord.new(-2, 0)]
	torso.fixed_sinks = sinks

	var grid_renderer = GarageGridRendererScript.new()
	add_child(grid_renderer)
	grid_renderer.size = Vector2(400, 400)

	var garage_stub = GarageStub.new()
	add_child(garage_stub)
	garage_stub.grid_renderer = grid_renderer
	garage_stub.mech_components = {HexTile.BodySlot.TORSO: torso}
	garage_stub.inventory = [AmplifierTileScript.new()]
	# active_component deliberately left null at first - readiness gate test.

	var main_stub = MainStub.new()
	add_child(main_stub)
	main_stub.garage_ui = garage_stub

	# Deliberately do NOT rely on TutorialManager._ready()'s own auto-start -
	# it early-returns if user://tutorial_completed.flag already exists on
	# disk, which it does on any machine where the tutorial has actually
	# been played for real. user:// is the REAL save directory, never a
	# sandbox for a throwaway test to poke at - so this drives the exact
	# same setup _ready() would perform (when NOT already completed)
	# directly, without ever touching that file or SaveManager's own state.
	var tm = TutorialManagerScript.new()
	main_stub.add_child(tm)
	await get_tree().process_frame
	tm._load_steps()
	if not tm.root:
		tm._build_ui()
	tm.is_active = true
	tm._goto_step(0)

	_check("steps loaded from the real tutorial.json", not tm.steps.is_empty())

	# Jump straight to the guided_build_torso_run step by id, wherever the
	# real tutorial.json currently places it - don't hardcode an index that
	# would silently go stale if step order changes.
	var target_index = -1
	for i in range(tm.steps.size()):
		if str(tm.steps[i].get("id", "")) == "guided_build_torso_run":
			target_index = i
			break
	_check("tutorial.json actually contains 'guided_build_torso_run'", target_index >= 0)
	if target_index < 0:
		get_tree().quit(1)
		return
	tm._goto_step(target_index)

	# --- Readiness gating: grid_renderer not visible in tree yet ---
	grid_renderer.visible = false
	tm._update_guided_build()
	_check("guided-build does NOT start while grid_renderer isn't visible in tree",
		tm.guided_build_runner == null)

	grid_renderer.visible = true
	# --- Readiness gating: active_component doesn't match the target slot yet ---
	tm._update_guided_build()
	_check("guided-build does NOT start before the player is on the right tab (active_component mismatch)",
		tm.guided_build_runner == null)

	# --- Player switches to the Torso tab ---
	garage_stub.active_component = torso
	grid_renderer.setup(torso.hex_grid, garage_stub, torso.valid_hexes)
	grid_renderer.active_component = torso
	tm._update_guided_build()
	_check("guided-build starts once the correct tab is active", tm.guided_build_runner != null)

	if tm.guided_build_runner == null:
		get_tree().quit(1)
		return

	# --- Drive the plan to completion by actually performing each
	# placement/orientation on the real torso, mirroring what the player
	# would do by hand. ---
	var safety = 0
	while tm.guided_build_runner != null and not tm.guided_build_runner.is_done and safety < 20:
		safety += 1
		var step = tm.guided_build_runner._current_step()
		var hex = step.hex
		var tile = torso.hex_grid.get_tile(hex)
		if tm.guided_build_runner.sub_phase == "placement":
			if not tile:
				# Simulate the player grabbing the exact tile type called for.
				var new_tile = AmplifierTileScript.new()
				new_tile.tile_type = step.tile_type
				torso.hex_grid.add_tile(hex, new_tile)
				tile = new_tile
		if tm.guided_build_runner.sub_phase == "orientation" and tile:
			if step.target_active_faces.size() > 0 and "active_faces" in tile:
				tile.active_faces.clear()
				for f in step.target_active_faces:
					tile.active_faces.append(f)
		tm._update_guided_build()

	_check("the guided-build plan actually completed (didn't get stuck)", tm.guided_build_runner == null or tm.guided_build_runner.is_done)
	_check("completing the plan advanced the OUTER tutorial step_index past guided_build_torso_run",
		tm.step_index > target_index)

	if failures == 0:
		print("PASS: TutorialManager's guided-build wiring gates on readiness and drives the outer step forward on completion")
	get_tree().quit(0 if failures == 0 else 1)
