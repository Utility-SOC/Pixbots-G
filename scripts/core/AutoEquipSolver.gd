class_name AutoEquipSolver
extends RefCounted

var HexCoord = preload("res://scripts/core/HexCoord.gd")
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")

# `profile` (SolverProfile, optional) is what makes this solver actually
# aim at something instead of always doing the same fixed Amplifier ->
# Catalyst -> Elemental Infuser -> Splitter placement regardless of who
# it's building for. When a profile is given: Elemental Infusers get
# prioritized for placement (previously they were checked LAST, so they
# barely ever got used even when present in inventory), and any Infuser the
# solver places gets its synergy configured toward the profile's favored
# element / pierce priority rather than whatever it happened to be set to
# when created.
func solve(component: Node, inventory: Array, profile: SolverProfile = null) -> Array:
	if not component or not component.hex_grid:
		return inventory
		
	var grid = component.hex_grid
	var targets = component.fixed_sinks
	var start = HexCoord.new(0, 0)
	
	# 1. Clear the board of non-fixed/non-core tiles
	var current_tiles = grid.grid.keys()
	for coord_v in current_tiles:
		var h = HexCoord.new(coord_v.x, coord_v.y)
		var is_target = false
		for t in targets:
			if t.q == h.q and t.r == h.r:
				is_target = true
				break
		if not is_target and (h.q != start.q or h.r != start.r):
			var tile = grid.remove_tile(h)
			if tile:
				inventory.append(tile)
				
	# 2. Build adjacency list of valid hexes
	var valid_map = {}
	for h in component.valid_hexes:
		valid_map[Vector2i(h.q, h.r)] = true
		
	# 3. Global BFS from start to build a shared spanning tree
	var came_from = {}
	var queue = [start]
	came_from[Vector2i(start.q, start.r)] = null
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_v = Vector2i(current.q, current.r)
		for d in range(6):
			var n = current.neighbor(d)
			var nv = Vector2i(n.q, n.r)
			if valid_map.has(nv) and not came_from.has(nv):
				came_from[nv] = current_v
				queue.push_back(n)
				
	var paths = {}
	for target in targets:
		var target_v = Vector2i(target.q, target.r)
		if not came_from.has(target_v):
			continue # Unreachable
		
		var path = []
		var curr = target_v
		while curr != null:
			path.insert(0, curr)
			curr = came_from.get(curr, null)
			
		if targets.size() == 1:
			var max_len = path.size() + inventory.size()
			path = _lengthen_path(path, valid_map, max_len)
			
		paths[target_v] = path
		
	# 4. Combine paths into a Spanning Tree
	# tree_nodes[Vector2i(q,r)] = [list of child Vector2i(q,r)]
	var tree_nodes = {}
	var parent_map = {}
	
	for target in targets:
		var target_v = Vector2i(target.q, target.r)
		if not paths.has(target_v):
			continue
		var path = paths[target_v]
		for i in range(path.size() - 1):
			var p1 = path[i]
			var p2 = path[i+1]
			if not tree_nodes.has(p1):
				tree_nodes[p1] = []
			var children = tree_nodes[p1]
			var found = false
			for c in children:
				if c == p2:
					found = true
			if not found:
				children.append(p2)
				parent_map[p2] = p1
				
	# 5. Place tiles
	for v in tree_nodes.keys():
		var h = HexCoord.new(v.x, v.y)
		
		# Skip start and targets
		var is_target = false
		for t in targets:
			if t.q == h.q and t.r == h.r:
				is_target = true
				break
				
		if is_target:
			continue
			
		if h.q == start.q and h.r == start.r:
			# If it's the start tile AND it's a core (like in the Torso), update faces and skip.
			var start_tile = grid.get_tile(start)
			if start_tile and "active_faces" in start_tile:
				start_tile.active_faces.clear()
				for child_v in tree_nodes[v]:
					var exit_dir = _get_direction(h, HexCoord.new(child_v.x, child_v.y))
					start_tile.active_faces.append(exit_dir)
				continue
			
		var children = tree_nodes[v]
		var num_children = children.size()
		
		var entry_dir = 0
		if h.q == start.q and h.r == start.r:
			var HexTileCls = load("res://scripts/core/HexTile.gd")
			if component.slot_type == HexTileCls.BodySlot.ARM_L: entry_dir = 3
			elif component.slot_type == HexTileCls.BodySlot.ARM_R: entry_dir = 0
			elif component.slot_type == HexTileCls.BodySlot.LEG_L or component.slot_type == HexTileCls.BodySlot.LEG_R: entry_dir = 1
			elif component.slot_type == HexTileCls.BodySlot.HEAD: entry_dir = 5
			elif component.slot_type == HexTileCls.BodySlot.BACKPACK: entry_dir = 4
		else:
			var parent_v = parent_map.get(v, Vector2i(0,0))
			var parent_h = HexCoord.new(parent_v.x, parent_v.y)
			entry_dir = _get_direction(parent_h, h)
		
		var placed_tile = false
		
		if num_children > 1:
			# Needs a Splitter
			var split_idx = _find_tile_index(inventory, "Splitter")
			var splitter
			if split_idx >= 0:
				splitter = inventory[split_idx]
				inventory.remove_at(split_idx)
			else:
				# Spawn a generic splitter to prevent broken routing - matches
				# the component's own rarity so a high-rarity enemy's grid
				# isn't sparsely filled with COMMON-default filler tiles once
				# the inventory the caller handed in runs out.
				splitter = load("res://scripts/tiles/SplitterTile.gd").new()
				splitter.rarity = component.rarity

			splitter.active_faces.clear()
			for child_v in children:
				var child_h = HexCoord.new(child_v.x, child_v.y)
				var exit_dir = _get_direction(h, child_h)
				splitter.active_faces.append(exit_dir)
			grid.add_tile(h, splitter)
			placed_tile = true
				
		elif num_children == 1:
			var child_v = children[0]
			var child_h = HexCoord.new(child_v.x, child_v.y)
			var exit_dir = _get_direction(h, child_h)
			
			if entry_dir == exit_dir:
				# Straight path -> Amplifier, Catalyst, Infuser
				var tile_types = _straight_tile_priority(profile)
				var idx = _find_tile_index_by_priority(inventory, tile_types)

				if idx >= 0:
					var tile = inventory[idx]
					inventory.remove_at(idx)
					if tile.tile_type == "Splitter":
						tile.active_faces.clear()
						tile.active_faces.append(exit_dir)
					elif tile.tile_type == "Elemental Infuser" and profile != null:
						tile.secondary_synergy = _pick_profile_synergy(profile)
					grid.add_tile(h, tile)
					placed_tile = true
			else:
				# Corner -> Reflector or Splitter
				var idx = _find_tile_index(inventory, "Reflector")
				if idx >= 0:
					var refl = inventory[idx]
					inventory.remove_at(idx)
					
					var diff = (exit_dir - entry_dir + 6) % 6
					# entry_face = (entry_dir + 3) % 6
					# exit = (entry_face + 3 + rotation_steps) % 6
					# We want exit = exit_dir.
					# So exit_dir = (entry_dir + rotation_steps) % 6 => rotation_steps = exit_dir - entry_dir
					refl.rotation_steps = diff
					
					grid.add_tile(h, refl)
					placed_tile = true
				else:
					# Fallback to Splitter
					idx = _find_tile_index(inventory, "Splitter")
					var splitter
					if idx >= 0:
						splitter = inventory[idx]
						inventory.remove_at(idx)
					else:
						# Spawn generic splitter to prevent broken routing at
						# corners - see the matching comment above for why this
						# inherits the component's rarity.
						splitter = load("res://scripts/tiles/SplitterTile.gd").new()
						splitter.rarity = component.rarity

					splitter.active_faces.clear()
					splitter.active_faces.append(exit_dir)
					grid.add_tile(h, splitter)
					placed_tile = true
						
		if not placed_tile:
			# Just dump anything that can pass energy
			var tile
			if inventory.size() > 0:
				tile = inventory[0]
				inventory.remove_at(0)
			else:
				# Same rarity-inheritance reasoning as the generic-splitter
				# fallbacks above.
				tile = load("res://scripts/tiles/DirectionalConduitTile.gd").new()
				tile.rarity = component.rarity

			if tile.tile_type == "Elemental Infuser" and profile != null:
				tile.secondary_synergy = _pick_profile_synergy(profile)

			if "rotation_steps" in tile:
				tile.rotation_steps = entry_dir

			grid.add_tile(h, tile)

	return inventory

# Straight-run tile search order. With no profile, this is the original
# fixed order. With a profile, Elemental Infuser goes first - it's the tile
# that actually lets a loadout build toward a specific element or Pierce,
# so burying it behind Amplifier/Catalyst (as the original fixed order did)
# meant profiles could almost never express themselves even when the
# inventory had the right tiles.
func _straight_tile_priority(profile: SolverProfile) -> Array:
	if profile == null:
		return ["Amplifier", "Catalyst", "Elemental Infuser", "Splitter"]
	return ["Elemental Infuser", "Amplifier", "Catalyst", "Splitter"]

# Rolls between the profile's favored counter-element and Pierce, weighted
# by amplify_priority vs pierce_priority. A profile with no favored_synergy
# set (pure -1) just leans on Pierce/Kinetic as a safe default.
func _pick_profile_synergy(profile: SolverProfile) -> int:
	if profile.favored_synergy < 0:
		return EnergyPacket.SynergyType.PIERCE if randf() < profile.pierce_priority else EnergyPacket.SynergyType.KINETIC

	var total = max(0.01, profile.pierce_priority + profile.amplify_priority)
	if randf() < profile.pierce_priority / total:
		return EnergyPacket.SynergyType.PIERCE
	return profile.favored_synergy

func _get_direction(from: HexCoord, to: HexCoord) -> int:
	for d in range(6):
		var n = from.neighbor(d)
		if n.q == to.q and n.r == to.r:
			return d
	return 0

func _find_tile_index(inventory: Array, type_name: String) -> int:
	for i in range(inventory.size()):
		if inventory[i].tile_type == type_name:
			return i
	return -1

# Same result as calling _find_tile_index once per entry in type_priority and
# taking the first hit (highest-priority type wins, first array occurrence of
# that type breaks ties) - but one pass over inventory instead of up to
# type_priority.size() separate passes. Only worth doing where a call site
# actually loops _find_tile_index over a priority list (see the straight-path
# tile search in solve()); single fixed-name lookups elsewhere in this file
# stay as plain _find_tile_index calls, inventory here is small enough that
# rewriting those too wouldn't pay for the extra bookkeeping risk.
func _find_tile_index_by_priority(inventory: Array, type_priority: Array) -> int:
	var best_idx = -1
	var best_rank = type_priority.size()
	for i in range(inventory.size()):
		var rank = type_priority.find(inventory[i].tile_type)
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best_idx = i
			if best_rank == 0:
				break
	return best_idx

func _lengthen_path(path: Array, valid_map: Dictionary, max_length: int) -> Array:
	var current_path = path.duplicate()
	var improved = true
	while improved and current_path.size() < max_length:
		improved = false
		for i in range(current_path.size() - 1):
			var p1 = current_path[i]
			var p2 = current_path[i+1]
			var h1 = HexCoord.new(p1.x, p1.y)
			var h2 = HexCoord.new(p2.x, p2.y)
			
			# Find a common neighbor that is valid and not already in path
			var candidates = []
			for d1 in range(6):
				var n1 = h1.neighbor(d1)
				var nv = Vector2i(n1.q, n1.r)
				if valid_map.has(nv) and not current_path.has(nv):
					# Check if it's also a neighbor of h2
					var is_neighbor_of_h2 = false
					for d2 in range(6):
						var n2 = h2.neighbor(d2)
						if n2.q == nv.x and n2.r == nv.y:
							is_neighbor_of_h2 = true
							break
					if is_neighbor_of_h2:
						candidates.append(nv)
						
			if candidates.size() > 0:
				var chosen = candidates[randi() % candidates.size()]
				current_path.insert(i + 1, chosen)
				improved = true
				break # Restart loop because indices changed
	return current_path
