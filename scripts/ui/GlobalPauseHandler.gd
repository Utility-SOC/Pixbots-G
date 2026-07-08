extends Node

# Single, always-processing home for "Esc opens the Pause Menu" - added once
# in Main._ready() alongside WarRoomMenu/MinimapOverlay/TutorialManager.
#
# Why this exists instead of Main._unhandled_input handling it directly:
# Main itself does NOT run with PROCESS_MODE_ALWAYS (it can't - its
# _process/_physics_process drive the actual game world, and those need to
# freeze on pause). That means once get_tree().paused = true (which
# GarageMenu keeps set for the entire time the Garage is open, including
# the death-triggered auto-reopen), Main's own _unhandled_input goes
# completely inert - it simply never runs again until unpaused. That's the
# actual reason a previous fix had to bolt a duplicate ui_cancel handler
# onto GarageMenu.gd's _input() (which DOES set PROCESS_MODE_ALWAYS) - and
# relying on two different nodes, in two different input phases
# (_input on GarageMenu vs _unhandled_input on Main), to coordinate via a
# shared group check was fragile and apparently still didn't reliably work
# ("when dead still cannot esc").
#
# This node sidesteps all of that: it's always-processing regardless of
# pause state, so a single _unhandled_input here reliably catches Escape
# whether the tree is paused (Garage open) or not (live gameplay, or the
# death-explosion window before the Garage reopens).
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event):
	if not event.is_action_pressed("ui_cancel"):
		return
	if get_tree().get_first_node_in_group("pause_menu"):
		return # already open - its own _input handles resume/close

	var main = get_tree().current_scene
	if not main:
		return

	get_tree().paused = true
	var pause_menu = load("res://scripts/ui/PauseMenu.gd").new()
	if "garage_ui" in main:
		pause_menu.opened_from_garage = (main.garage_ui != null)
	main.add_child(pause_menu)
