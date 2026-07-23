class_name GuidedBuildRunner
extends RefCounted

# Drives one guided-build walkthrough (see GuidedBuildPlanner.gd for how the
# plan itself is computed) - the player performs every placement/
# orientation themselves; this only WATCHES the real component's live grid
# state each frame and advances once the current micro-step's target is
# actually met. No new notify()/event plumbing needed through
# GarageInventoryPanel's drag-drop or GarageTileConfigPopup's face-toggle
# callbacks - TutorialManager already re-checks every frame during
# _process, so polling the real tile state directly is simpler and can't
# drift out of sync with whatever UI path the player used to make the
# change.

const GuidedBuildPlannerScript = preload("res://scripts/ui/GuidedBuildPlanner.gd")

var component = null
var plan: Array = []
var plan_index: int = -1
var sub_phase: String = "" # "placement" or "orientation"
var is_done: bool = false

func start(p_component, inventory: Array) -> void:
	component = p_component
	plan = GuidedBuildPlannerScript.compute_plan(p_component, inventory)
	plan_index = -1
	is_done = false
	_advance_to_next_actionable()

func _current_step():
	if plan_index < 0 or plan_index >= plan.size():
		return null
	return plan[plan_index]

func _advance_to_next_actionable() -> void:
	plan_index += 1
	if plan_index >= plan.size():
		is_done = true
		sub_phase = ""
		return
	var step = _current_step()
	# A pre-existing tile (the Core) never needs placing, only reconfiguring.
	sub_phase = "orientation" if step.already_placed else "placement"

func current_hex() -> HexCoord:
	var step = _current_step()
	return step.hex if step else null

func current_tile_type() -> String:
	var step = _current_step()
	return step.tile_type if step else ""

func current_instruction() -> String:
	var step = _current_step()
	if not step:
		return ""
	if sub_phase == "placement":
		return "Grab a %s from your inventory and drop it on the highlighted hex." % step.tile_type
	return "Click that %s and set its routing to match the highlighted direction(s)." % step.tile_type

# Called every frame (see TutorialManager._process) - checks the LIVE grid
# state against the current micro-step's target and advances in place when
# satisfied. Returns true once the WHOLE plan is complete.
func check_and_advance() -> bool:
	if is_done:
		return true
	var step = _current_step()
	if not step or not component or not component.hex_grid:
		return is_done

	var tile = component.hex_grid.get_tile(step.hex)

	if sub_phase == "placement":
		if tile and tile.tile_type == step.tile_type:
			if step.needs_orientation:
				sub_phase = "orientation"
			else:
				_advance_to_next_actionable()
		return is_done

	# sub_phase == "orientation"
	if tile and _matches_target(tile, step):
		_advance_to_next_actionable()
	return is_done

static func _matches_target(tile, step) -> bool:
	if step.target_active_faces.size() > 0:
		if not ("active_faces" in tile):
			return false
		var a: Array = tile.active_faces.duplicate()
		var b: Array = step.target_active_faces.duplicate()
		a.sort()
		b.sort()
		return a == b
	if step.target_synergy >= 0:
		return "secondary_synergy" in tile and tile.secondary_synergy == step.target_synergy
	if step.target_rotation_steps >= 0:
		return "rotation_steps" in tile and tile.rotation_steps == step.target_rotation_steps
	return true
