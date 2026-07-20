extends Node

# Regression harness for "the tutorial completely broke gameplay": doubled/
# ghosted inventory, a black garage screen, and a dead "Deploy to
# Battlefield" button.
#
# Root cause: Main._open_garage() created + add_child'd a fresh GarageMenu
# unconditionally. It has several callers (new-game start, the tutorial's
# _ensure_in_garage, DebugMenu Teleport, extraction return); once the
# tutorial started running on EVERY new game it could force the Garage open
# a frame before the start sequence also opened it, leaving TWO GarageMenu
# nodes parented at once - the doubled inventory, and a stale orphaned copy
# whose Deploy button pointed at a garage that was no longer live.
#
# The fix makes _open_garage idempotent. This verifies a second call while a
# garage is already open is a no-op (still exactly one GarageMenu child, and
# the SAME instance).

const MainScript = preload("res://scripts/core/Main.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _count_garages(main) -> int:
	var n = 0
	for c in main.get_children():
		if c.get_script() == GarageMenuScript:
			n += 1
	return n

func _ready():
	# Static guarantee first (cheap, no full Main boot): the source actually
	# guards against re-entry.
	var src = FileAccess.get_file_as_string("res://scripts/core/Main.gd")
	_check("_open_garage() guards on an already-open garage before creating one",
		src.find("func _open_garage():") != -1
		and src.find("if garage_ui and is_instance_valid(garage_ui):") != -1)

	# Behavioural: boot a real Main, open the garage twice, expect ONE.
	var main = MainScript.new()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	if not ("garage_ui" in main) or not main.has_method("_open_garage"):
		push_error("FAIL: Main missing garage_ui/_open_garage - harness assumption broke")
		failures += 1
	else:
		# Main may already have opened one during boot. Force-close to a known
		# state, then drive the open path directly.
		if main.garage_ui and is_instance_valid(main.garage_ui):
			main.garage_ui.queue_free()
			main.garage_ui = null
			await get_tree().process_frame
		main._open_garage()
		await get_tree().process_frame
		var after_first = _count_garages(main)
		var first_instance = main.garage_ui
		main._open_garage() # second call while one is already open
		main._open_garage() # and a third, for good measure
		await get_tree().process_frame
		var after_repeats = _count_garages(main)
		_check("one garage after the first open (got %d)" % after_first, after_first == 1)
		_check("still exactly one garage after repeated _open_garage calls (got %d)" % after_repeats, after_repeats == 1)
		_check("garage_ui still points at the SAME live instance (never orphaned/replaced)",
			main.garage_ui == first_instance and is_instance_valid(first_instance))

	main.queue_free()
	await get_tree().process_frame

	if failures == 0:
		print("PASS: _open_garage is idempotent - never stacks a second garage, Deploy stays wired to the live one")
	get_tree().quit(0 if failures == 0 else 1)
