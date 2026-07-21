extends Node

# Regression harness for task #9 ("War Room accessible from Garage"):
# previously WarRoomMenu was only reachable from the Main Menu (before a run
# starts) or the in-run TAB shortcut - a player deep in a Garage build
# session between waves had no way to check enemy doctrine analysis without
# leaving. GarageMenu._on_war_room_pressed() mirrors MainMenu's own
# reuse-a-single-instance toggle pattern exactly.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var garage = GarageMenuScript.new()
	world.add_child(garage)

	# 1. First press creates the instance, already open.
	garage._on_war_room_pressed()
	var wr = garage.get_node_or_null("WarRoomInstance")
	if not wr:
		push_error("FAIL: War Room button didn't create a WarRoomInstance under the Garage")
		failures += 1
		get_tree().quit(1)
		return
	if not wr.is_open or not wr.root_panel.visible:
		push_error("FAIL: War Room should be open immediately after the first press")
		failures += 1
	else:
		print("1) War Room button (Garage) creates and opens WarRoomInstance")

	# 2. Second press reuses the SAME instance and toggles it closed (no
	# stacked duplicates).
	garage._on_war_room_pressed()
	var wr_count = 0
	for c in garage.get_children():
		if c.name == "WarRoomInstance":
			wr_count += 1
	if wr_count != 1:
		push_error("FAIL: repeat presses should reuse one instance, found %d" % wr_count)
		failures += 1
	elif wr.is_open or wr.root_panel.visible:
		push_error("FAIL: second press should toggle the War Room closed")
		failures += 1
	else:
		print("2) second press reuses the same instance and toggles it closed")

	# 3. Third press re-opens the same instance again.
	garage._on_war_room_pressed()
	if not wr.is_open or not wr.root_panel.visible:
		push_error("FAIL: third press should re-open the same War Room instance")
		failures += 1
	else:
		print("3) third press re-opens the same instance")

	if failures == 0:
		print("PASS: War Room is reachable from the Garage, same toggle/reuse pattern as the Main Menu")
	get_tree().quit(0 if failures == 0 else 1)
