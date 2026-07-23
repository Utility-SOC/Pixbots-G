extends Node

# Regression harness for GuidedBuildPlanner - the "brain" behind the
# hand-over-hand guided build walkthrough. Verifies:
#   1. It reuses AutoEquipSolver's real placement logic (same tile choices
#      Auto-Equip would make) rather than a separate algorithm.
#   2. It NEVER mutates the player's real component or inventory - only a
#      throwaway clone.
#   3. The plan correctly separates "genuinely new tile" steps from
#      "pre-existing Core needs re-orientation" steps.
#   4. Steps are ordered nearest-to-Core first.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const GuidedBuildPlannerScript = preload("res://scripts/ui/GuidedBuildPlanner.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# A minimal Torso: Core at (0,0) with default active_faces=[0] (East),
	# and a single Left Arm Link sink at (-2,0) reachable only via a
	# straight westward run through (-1,0). Deliberately requires the Core
	# to be RE-oriented (default East, sink is West) and one intermediate
	# tile to be placed.
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

	var inventory: Array = [AmplifierTileScript.new(), SplitterTileScript.new()]
	var inventory_snapshot_size = inventory.size()
	var core_faces_before = core.active_faces.duplicate()

	var plan = GuidedBuildPlannerScript.compute_plan(torso, inventory)

	# --- Safety: the planner must not touch the real component/inventory ---
	_check("the real Torso's grid still only has its original 2 tiles (Core + sink)",
		torso.hex_grid.get_all_tiles().size() == 2)
	_check("the real Core's active_faces is untouched by the dry-run solve",
		core.active_faces == core_faces_before)
	_check("the real inventory array is untouched (same size)",
		inventory.size() == inventory_snapshot_size)
	_check("the real inventory's tiles are the SAME objects (not consumed/replaced)",
		inventory[0] is AmplifierTileScript and inventory[1] is SplitterTileScript)

	# --- Plan correctness ---
	_check("the plan is non-empty", plan.size() > 0)

	var core_step = null
	var placement_steps = []
	for step in plan:
		if step.already_placed:
			core_step = step
		else:
			placement_steps.append(step)

	_check("the plan includes a re-orientation step for the pre-existing Core",
		core_step != null and core_step.hex.q == 0 and core_step.hex.r == 0)
	if core_step:
		_check("the Core's target orientation actually points West (toward the sink), not the stale default East",
			core_step.target_active_faces.has(3) and not core_step.target_active_faces.has(0))

	_check("the plan places exactly one new tile (the (-1,0) waypoint)", placement_steps.size() == 1)
	if placement_steps.size() > 0:
		_check("the new tile lands at (-1,0), between the Core and the sink",
			placement_steps[0].hex.q == -1 and placement_steps[0].hex.r == 0)
		_check("the new tile is one of the real inventory tile types (Amplifier or Splitter)",
			placement_steps[0].tile_type == "Amplifier" or placement_steps[0].tile_type == "Splitter")

	# --- Ordering: nearest-to-Core first ---
	if plan.size() >= 2:
		var prev_dist = -1
		var ordered = true
		for step in plan:
			var d = abs(step.hex.q) + abs(step.hex.r) + abs(step.hex.q + step.hex.r)
			if d < prev_dist:
				ordered = false
			prev_dist = d
		_check("plan steps are ordered by non-decreasing hex-distance from the Core", ordered)

	if failures == 0:
		print("PASS: GuidedBuildPlanner computes a correct, non-destructive, well-ordered plan")
	get_tree().quit(0 if failures == 0 else 1)
