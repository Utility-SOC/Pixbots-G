extends Node

# Regression harness for GuidedBuildRunner - simulates a player actually
# performing each placement/orientation on a real component, one micro-step
# at a time, and confirms the runner only advances when the live grid
# state genuinely matches the plan (never early, never stuck).

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const GuidedBuildRunnerScript = preload("res://scripts/ui/GuidedBuildRunner.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Same layout as GuidedBuildPlannerCheck: Core@(0,0) defaults East, sink
	# at (-2,0), one waypoint hex at (-1,0) in between - requires both a
	# Core re-orientation AND one real placement.
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

	var inventory: Array = [AmplifierTileScript.new()]

	var runner = GuidedBuildRunnerScript.new()
	runner.start(torso, inventory)

	_check("runner is not done immediately after starting (real work remains)", not runner.is_done)

	# The plan is Core-distance-ordered, so the Core's own re-orientation
	# (distance 0) should be first.
	var first_hex = runner.current_hex()
	_check("the first micro-step targets the Core's own hex (0,0)",
		first_hex.q == 0 and first_hex.r == 0)
	_check("the first micro-step is an orientation step (Core already exists)",
		runner.sub_phase == "orientation")

	# Checking before the player has done anything must NOT advance.
	_check("check_and_advance() does nothing before the player acts",
		not runner.check_and_advance() and runner.sub_phase == "orientation")

	# Player performs the WRONG orientation - must still not advance.
	core.active_faces.clear()
	core.active_faces.append(1) # wrong direction
	_check("a wrong orientation does not satisfy the step",
		not runner.check_and_advance() and runner.plan_index == 0)

	# Player performs the CORRECT orientation.
	core.active_faces.clear()
	core.active_faces.append(3) # West, toward the sink
	runner.check_and_advance()
	_check("the correct Core orientation advances to the next micro-step", runner.plan_index == 1)
	_check("the next step is a placement step (the (-1,0) waypoint)", runner.sub_phase == "placement")

	var second_hex = runner.current_hex()
	_check("the second micro-step targets (-1,0)", second_hex.q == -1 and second_hex.r == 0)

	# Player places the tile.
	var placed = AmplifierTileScript.new()
	torso.hex_grid.add_tile(HexCoord.new(-1, 0), placed)
	var finished = runner.check_and_advance()
	_check("placing the last planned tile finishes the whole plan", finished and runner.is_done)

	if failures == 0:
		print("PASS: GuidedBuildRunner only advances when the live grid genuinely matches the plan")
	get_tree().quit(0 if failures == 0 else 1)
