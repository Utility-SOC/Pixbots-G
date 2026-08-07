extends Node

# Regression harness for get_muzzle_position()'s renderer-cache fix (live
# playtest: "shoot_fired" was the dominant remaining cost after the
# pattern-fanout/AI-throttle fixes - the user's own suggestion, "more
# precalculating and caching rather than on the fly calculation"). Mech.gd
# already caches its own MechRenderer child in _renderer (set once in
# _ready()); get_muzzle_position was ignoring that and doing a fresh
# string-keyed get_node_or_null("MechRenderer") tree lookup on every
# single shot instead.

const MechScript = preload("res://scripts/entities/Mech.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	var mount = WeaponMountTileScript.new()
	mount.body_slot = HexTile.BodySlot.ARM_R

	# --- Real Mech: proves the fix actually USES the cache, not just that
	# it doesn't crash - swap _renderer for a stand-in with a distinctly
	# different arm transform than whatever the real tree-child renderer
	# has, and confirm get_muzzle_position reflects the SWAPPED one. If
	# this were still calling get_node_or_null("MechRenderer") under the
	# hood, it would find the real child instead and this check would fail.
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	await get_tree().process_frame # let _ready() build the real _renderer

	_check("Mech._ready() populated the real _renderer cache", mech._renderer != null)

	# A real MechRenderer instance (not a bare Node2D) - drawn_parts is a
	# declared field on that class, setting it on a plain Node2D would be a
	# silent no-op (Node2D has no such property). Set AFTER add_child(), not
	# before - _ready() -> _rebuild_visuals() clears drawn_parts as its
	# first action, which would wipe a pre-set value.
	var stand_in = load("res://scripts/visuals/MechRenderer.gd").new()
	world.add_child(stand_in)
	await get_tree().process_frame
	var fake_arm = Node2D.new()
	fake_arm.global_position = Vector2(500, 500)
	fake_arm.global_rotation = 0.0
	world.add_child(fake_arm)
	stand_in.drawn_parts = {"Arm_false": fake_arm} # ARM_R maps to "Arm_false" (is_right branch)
	mech._renderer = stand_in

	var pos = mount.get_muzzle_position(mech)
	_check("get_muzzle_position reads the CACHED _renderer (returns near the swapped-in fake arm, not the real one or mech.global_position)",
		pos.distance_to(Vector2(500, 500)) < 50.0)

	# --- PreviewMechContext-style stub: no _renderer field at all - must
	# fall back to the original get_node_or_null path instead of crashing
	# on a nonexistent property access.
	var stub = Node2D.new()
	stub.global_position = Vector2(77, 77)
	world.add_child(stub)
	var stub_pos = mount.get_muzzle_position(stub)
	_check("a duck-typed stub with no _renderer field falls back cleanly (no crash) and returns its own global_position",
		stub_pos == Vector2(77, 77))

	if failures == 0:
		print("PASS: get_muzzle_position uses Mech's cached _renderer for real mechs, falls back safely for the preview-stub case")
	get_tree().quit(0 if failures == 0 else 1)
