extends Node

# Regression harness for: "right now hovering over a weapon mount is
# cripplingly slow." Root cause: GarageMenu._update_mount_preview() called
# Mech._recalculate_grid() - the FULL multi-component energy simulation
# (up to 7 components, each up to a 1000-step packet routing loop) -
# unconditionally on every debounce tick while the mouse just swept across
# an already-configured, unedited grid. Every other _recalculate_grid()
# caller (Mech._shoot(), GarageTestRange._populate_mounts) gates it behind
# is_grid_dirty; this one didn't. Fixed by adding the same gate.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

var failures = 0
var recalc_count = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

# A minimal stand-in for Mech that just counts _recalculate_grid() calls
# and tracks is_grid_dirty exactly like the real thing, without paying for
# an actual energy simulation - what's under test is WHETHER the recalc is
# invoked, not what it computes (that's already covered by the simulation-
# specific checks elsewhere in scripts/debug/).
class FakeMech:
	extends Node
	var is_grid_dirty: bool = true
	var fire_rate: float = 0.25
	var precalculated_weapons: Array = []
	var recalc_calls: int = 0
	func _recalculate_grid():
		recalc_calls += 1
		is_grid_dirty = false

class MainStub:
	extends Node
	var player = null

func _ready():
	var mount = WeaponMountTileScript.new()

	var fake_mech = FakeMech.new()
	add_child(fake_mech)

	# player is left null until AFTER the garage is added/ready - GarageMenu.
	# _ready()/_setup_ui() build the full UI eagerly and would otherwise
	# reach into a bunch of real-Mech-only properties (separate_arm_firing,
	# components, ...) this minimal FakeMech doesn't need for what's under
	# test here.
	var main_stub = MainStub.new()
	add_child(main_stub)

	var garage = GarageMenuScript.new()
	main_stub.add_child(garage)
	main_stub.player = fake_mech

	# First hover: grid starts dirty (a real fresh build always does) -
	# this recalc is expected and necessary.
	garage._update_mount_preview(mount, Vector2.ZERO)
	_check("the first hover, with a dirty grid, DOES recalculate", fake_mech.recalc_calls == 1)
	_check("recalculating clears is_grid_dirty (matches Mech.gd's real behavior)", not fake_mech.is_grid_dirty)

	# Force the debounce window open again (as if enough real time passed)
	# so the ONLY thing preventing a second recalc is the is_grid_dirty gate.
	garage._mount_preview_next_recalc_ms = 0

	# Second hover over an unedited grid: must NOT recalculate again.
	garage._update_mount_preview(mount, Vector2.ONE * 10)
	_check("a second hover on an UNEDITED grid does NOT trigger another full recalculate",
		fake_mech.recalc_calls == 1)

	# Simulate an actual loadout edit, then hover again - NOW it should recalculate.
	fake_mech.is_grid_dirty = true
	garage._mount_preview_next_recalc_ms = 0
	garage._update_mount_preview(mount, Vector2.ONE * 20)
	_check("after a real edit sets is_grid_dirty again, hovering DOES recalculate",
		fake_mech.recalc_calls == 2)

	if failures == 0:
		print("PASS: hovering a Weapon Mount no longer re-runs the full energy simulation on an unedited grid")
	get_tree().quit(0 if failures == 0 else 1)
