extends Node

# Regression harness for two Garage playtest reports from the same
# screenshot:
# 1. "I still need to run the simulation before the energy coming into the
#    component will model accurately" - despite the silent-snapshot
#    feature being wired in correctly. Root cause: is_simulating only ever
#    cleared itself on natural sim completion or a manual "Stop
#    Simulation" press - switching tabs mid-animation (the common case)
#    left it stuck true forever, which run_silent_snapshot()'s own
#    `if garage.is_simulating: return` guard then treated as "a live run
#    already owns this," permanently blocking every future silent
#    recompute for the rest of the session.
# 2. The spare-parts empty-state text rendering vertically, one character
#    per line - a word-wrapped Label with no custom_minimum_size inside an
#    HFlowContainer collapses to its smallest possible width.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const GarageSimulationRunnerScript = preload("res://scripts/ui/GarageSimulationRunner.gd")
const GarageInventoryPanelScript = preload("res://scripts/ui/GarageInventoryPanel.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Stuck is_simulating no longer blocks the silent snapshot ---
	var torso = ComponentEquipmentScript.create_starter_torso()

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso}
	garage.active_component = torso
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	garage.component_tabs = TabBar.new()
	garage.add_child(garage.component_tabs)
	garage.component_tabs.add_tab("Torso")
	garage.component_tabs.set_tab_metadata(0, HexTile.BodySlot.TORSO)

	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(torso.hex_grid, garage, torso.valid_hexes)
	garage.grid_renderer.active_component = torso

	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)

	# Simulate the exact stuck scenario: a live run was left active (as if
	# the player switched tabs mid-animation without pressing Stop).
	garage.is_simulating = true

	garage._on_tab_changed(0)

	_check("_on_tab_changed() force-clears a stuck is_simulating flag", garage.is_simulating == false)
	_check("with is_simulating cleared, the silent snapshot actually ran (total_steps advanced)",
		garage.simulation_runner.total_steps > 0)

	# --- 2. Empty-state spare-parts label gets a real minimum width ---
	# Separate GarageMenu instance parented directly under a fake "main" so
	# refresh_component_list()'s garage.get_parent() lookup resolves - a
	# fresh instance rather than reparenting the one from part 1 above,
	# since add_child() errors on a node that already has a parent.
	var fake_main_script = GDScript.new()
	fake_main_script.source_code = "extends Node\nvar player_component_inventory: Array = []\n"
	fake_main_script.reload()
	var fake_main = Node.new()
	fake_main.set_script(fake_main_script)
	add_child(fake_main)

	var garage2 = GarageMenuScript.new()
	fake_main.add_child(garage2)
	garage2.component_inventory_list = HFlowContainer.new()
	garage2.add_child(garage2.component_inventory_list)
	garage2.component_diagram = null

	var panel = GarageInventoryPanelScript.new(garage2)
	panel.refresh_component_list()

	_check("empty-state spare-parts tray produced exactly one label", garage2.component_inventory_list.get_child_count() == 1)
	if garage2.component_inventory_list.get_child_count() == 1:
		var lbl = garage2.component_inventory_list.get_child(0)
		_check("empty-state label has a real minimum width, not left at the HFlowContainer default (0)",
			lbl.custom_minimum_size.x > 0.0)

	if failures == 0:
		print("PASS: switching tabs mid-animation no longer wedges the silent snapshot, and the empty-state label renders as a real line")
	get_tree().quit(0 if failures == 0 else 1)
