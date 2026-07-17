extends Node

# Regression harness for the "energy intake is directional in a way that
# prevents it from being used" playtest report: every Energy Intake tile
# (arms/legs/head/backpacks) used to spawn at hex (0,0) riding
# ComponentLinkTile's class-level default active_faces = [0] (hex direction
# East), never adjusted for the shape it actually landed in. On any
# generated shape that doesn't extend East from center, the intake had
# nowhere to route power - ComponentEquipment._orient_intake_to_shape() now
# points it at whichever directions the shape actually touches.
#
# 1. Across every starter arm/leg/head and every backpack variant, the
#    intake's active_faces must be non-empty and every listed direction must
#    point at a hex that's actually part of the component's shape.
# 2. Direct unit test of _orient_intake_to_shape() on a synthetic shape that
#    deliberately excludes direction 0 (East) - proves the old "always [0]"
#    default would have failed this and the fix picks the real direction(s).

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")

var failures = 0

func _fail(msg: String):
	push_error("FAIL: " + msg)
	failures += 1

func _check_intake(component: ComponentEquipment, label: String):
	var intake = component.hex_grid.get_tile(HexCoord.new(0, 0))
	if not intake or intake.tile_type != "Energy Intake":
		_fail("%s: no Energy Intake tile found at (0,0)" % label)
		return
	if intake.active_faces.is_empty():
		_fail("%s: intake.active_faces is empty - it can never route power out" % label)
		return
	for d in intake.active_faces:
		var n = HexCoord.new(0, 0).neighbor(d)
		var found = false
		for h in component.valid_hexes:
			if h.equals(n):
				found = true
				break
		if not found:
			_fail("%s: active_face direction %d points off the shape (no valid hex there)" % [label, d])
			return
	print("ok: %s intake active_faces=%s all point at real shape hexes" % [label, str(intake.active_faces)])

func _ready():
	_check_intake(ComponentEquipmentScript.create_starter_arm(true), "L. Arm")
	_check_intake(ComponentEquipmentScript.create_starter_arm(false), "R. Arm")
	_check_intake(ComponentEquipmentScript.create_starter_leg(true), "L. Leg")
	_check_intake(ComponentEquipmentScript.create_starter_leg(false), "R. Leg")
	_check_intake(ComponentEquipmentScript.create_starter_head(), "Head")
	_check_intake(ComponentEquipmentScript.create_shield_backpack(), "Shield Backpack")
	_check_intake(ComponentEquipmentScript.create_jetpack_backpack(), "Jetpack Backpack")
	_check_intake(ComponentEquipmentScript.create_drone_backpack(), "Drone Backpack")
	_check_intake(ComponentEquipmentScript.create_missile_backpack(), "Missile Backpack")
	_check_intake(ComponentEquipmentScript.create_cloak_backpack(), "Cloak Backpack")
	_check_intake(ComponentEquipmentScript.create_jammer_backpack(), "Jammer Backpack")
	_check_intake(ComponentEquipmentScript.create_dual_utility_backpack(), "Dual Utility Backpack")
	_check_intake(ComponentEquipmentScript.create_support_backpack(), "Support Backpack")
	_check_intake(ComponentEquipmentScript.create_command_backpack(), "Command Backpack")

	# --- Direct unit test: shape deliberately excludes direction 0 (East) ---
	var synthetic = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.COMMON)
	var synth_hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(0, 1), HexCoord.new(0, -1)] # South-East(1) + North-West(4) only
	synthetic.valid_hexes = synth_hexes
	synthetic._rebuild_valid_hex_set()
	var synth_intake = ComponentLinkTileScript.new(HexTile.BodySlot.NONE, true)
	ComponentEquipmentScript._orient_intake_to_shape(synthetic, synth_intake)
	if synth_intake.active_faces.has(0):
		_fail("synthetic shape has no East neighbor, but active_faces still contains direction 0")
	elif synth_intake.active_faces == [0]:
		_fail("synthetic shape: active_faces unchanged from the old broken default")
	elif not (synth_intake.active_faces.has(1) and synth_intake.active_faces.has(4)):
		_fail("synthetic shape: expected directions 1 (SE) and 4 (NW), got %s" % str(synth_intake.active_faces))
	else:
		print("ok: synthetic East-less shape orients intake to real directions %s, not the old [0] default" % str(synth_intake.active_faces))

	if failures == 0:
		print("PASS: Energy Intake tiles orient to their actual shape on every starter component")
	get_tree().quit(0 if failures == 0 else 1)
