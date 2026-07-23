class_name GuidedBuildPlanner
extends RefCounted

# Computes a step-by-step "hand over hand" build plan for a component, per
# the user: "it needs to show where, and how the hexes will work by
# walking the user through a good/optimized (for what they have) build,
# and work the player through it step by step, fully hand over hand."
#
# Deliberately does NOT invent a new "what's optimal" algorithm - it reuses
# AutoEquipSolver (the exact logic behind the "Auto-Equip" button) against
# a THROWAWAY CLONE of the component + a cloned copy of the player's real
# inventory, built via SaveManager's serialize/deserialize round trip (the
# same mechanism this session's save/load fidelity work already proved
# correct - see ResimStatefulDriftCheck.gd/the round-trip diagnostics). The
# clone is solved and discarded; the player's real component/inventory are
# never touched by this planner. The resulting plan is then diffed against
# the clone's BEFORE state to produce an ordered list of individual
# placement/orientation steps - what GuidedBuildRunner.gd walks the player
# through performing themselves, by hand, on their own real grid.

const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")

class PlanStep:
	var hex: HexCoord
	var tile_type: String = ""
	# True if, after placement, the tile also needs its output configured to
	# match the plan (Core/Splitter face toggles, an Elemental Infuser's
	# element, a Reflector's rotation) - a bare placement isn't enough for
	# these, matching the exact class of mistake "tile_config" already
	# warns about.
	var needs_orientation: bool = false
	var target_active_faces: Array = [] # Core Reactor / Microcore / Splitter
	var target_synergy: int = -1 # Elemental Infuser (RAW-excluded - see below)
	var target_rotation_steps: int = -1 # Reflector
	# True for a tile that already existed before the plan (the Torso's own
	# Core Reactor) and only needs RE-orientation, never placement - the
	# walkthrough skips straight to the orientation micro-step for these.
	var already_placed: bool = false

	func _to_string() -> String:
		return "PlanStep(%s @ (%d,%d) orient=%s)" % [tile_type, hex.q, hex.r, needs_orientation]

# Orientable-tile fingerprint used both to decide whether a plan step needs
# an orientation micro-step and to snapshot/compare before/after state.
static func _orientation_signature(tile) -> Dictionary:
	if tile == null:
		return {}
	if tile.tile_type == "Core Reactor" or tile.tile_type == "Microcore" or tile.tile_type == "Splitter":
		if "active_faces" in tile:
			return {"active_faces": tile.active_faces.duplicate()}
	elif tile.tile_type == "Elemental Infuser":
		if "secondary_synergy" in tile:
			return {"secondary_synergy": tile.secondary_synergy}
	elif "rotation_steps" in tile:
		return {"rotation_steps": tile.rotation_steps}
	return {}

static func _apply_signature(step: PlanStep, sig: Dictionary) -> void:
	if sig.has("active_faces"):
		step.needs_orientation = true
		step.target_active_faces = sig["active_faces"]
	elif sig.has("secondary_synergy") and sig["secondary_synergy"] != EnergyPacket.SynergyType.RAW:
		step.needs_orientation = true
		step.target_synergy = sig["secondary_synergy"]
	elif sig.has("rotation_steps"):
		step.needs_orientation = true
		step.target_rotation_steps = sig["rotation_steps"]

# component: the player's REAL ComponentEquipment (read-only as far as this
# function is concerned - only a clone of it is ever mutated).
# player_inventory: the player's REAL inventory Array of HexTile (also only
# cloned, never mutated or consumed).
static func compute_plan(component, player_inventory: Array) -> Array:
	if not component or not component.hex_grid:
		return []

	var sm = SaveManagerScript.new()
	var clone = sm._deserialize_component(sm._serialize_component(component))

	var inventory_clone: Array = []
	for tile in player_inventory:
		var cloned_tile = sm._deserialize_tile(sm._serialize_tile(tile))
		if cloned_tile:
			inventory_clone.append(cloned_tile)

	# Snapshot every pre-existing tile's identity + orientation BEFORE
	# solving - needed to tell "this is a genuinely new placement" apart
	# from "this tile (the Core) already existed but the solver changed how
	# it's configured."
	var before_sig = {} # Vector2i -> Dictionary (orientation signature)
	var before_keys = {}
	for key in clone.hex_grid.grid.keys():
		before_keys[key] = true
		var t = clone.hex_grid.grid[key]
		if t.grid_position and t.grid_position.q == key.x and t.grid_position.r == key.y:
			before_sig[key] = _orientation_signature(t)

	var solver = AutoEquipSolverScript.new()
	solver.solve(clone, inventory_clone, null)

	var plan: Array = []
	for key in clone.hex_grid.grid.keys():
		var tile = clone.hex_grid.grid[key]
		# Only the tile's own anchor cell - skip footprint-offset duplicate
		# keys (multi-cell tiles), same convention HexGridComponent.
		# get_all_tiles() already uses.
		if not (tile.grid_position and tile.grid_position.q == key.x and tile.grid_position.r == key.y):
			continue

		var is_new = not before_keys.has(key)
		var after_sig = _orientation_signature(tile)

		if is_new:
			var step = PlanStep.new()
			step.hex = HexCoord.new(key.x, key.y)
			step.tile_type = tile.tile_type
			_apply_signature(step, after_sig)
			plan.append(step)
		else:
			# Pre-existing tile (the Core) - only relevant if the solver
			# actually changed its orientation from what it was before.
			var prior = before_sig.get(key, {})
			if not after_sig.is_empty() and after_sig != prior:
				var step = PlanStep.new()
				step.hex = HexCoord.new(key.x, key.y)
				step.tile_type = tile.tile_type
				step.already_placed = true
				_apply_signature(step, after_sig)
				plan.append(step)

	# Build outward from the Core: nearest hex-distance first, stable
	# left-to-right tie-break so the sequence never jumps around visually.
	plan.sort_custom(func(a, b):
		var da = abs(a.hex.q) + abs(a.hex.r) + abs(a.hex.q + a.hex.r)
		var db = abs(b.hex.q) + abs(b.hex.r) + abs(b.hex.q + b.hex.r)
		if da != db:
			return da < db
		return a.hex.q < b.hex.q
	)

	return plan
