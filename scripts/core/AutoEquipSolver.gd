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

	# 4.5. Core's own fan-out is capped to its rarity (CoreTile.get_max_faces()
	# - a Common core is [1,1,2,6,6]-limited to just 1 face) - per the design
	# ruling right where the Torso's disc shape gets built: "a Common core
	# fires only 1 face... a Splitter in the core hub can fan into all six."
	# The unrestricted BFS above already proved every target IS reachable -
	# don't re-derive reachability under a tighter constraint (that stranded
	# real targets the first time this was tried: restricting which
	# directions the BFS could even LEAVE the Core through assumes any two
	# ring positions are always mutually walkable to each other, which isn't
	# guaranteed once the disc's outer ring is incomplete). Instead, keep
	# the proven-correct tree and simply DEMOTE whichever of the Core's
	# direct children exceed the cap, re-attaching each demoted branch (and
	# whatever hung off it) via the shortest path from ANY hex already in
	# the (still fully connected) tree - a real, geometry-aware reroute, not
	# a guess about which hub happens to be adjacent.
	var start_v = Vector2i(start.q, start.r)
	var core_cap = 6
	if tree_nodes.has(start_v):
		var core_tile_for_cap = grid.get_tile(start)
		if core_tile_for_cap and core_tile_for_cap.has_method("get_max_faces"):
			core_cap = core_tile_for_cap.get_max_faces()
	_demote_excess_children(start_v, core_cap, tree_nodes, parent_map, valid_map, start_v, targets)
	# Core's capacity is now final for the rest of solve() - block it from
	# ever gaining another child via a later hub's reattachment (see
	# locked_v doc on _demote_excess_children).
	var locked_v := {start_v: true}

	# 4.6. Same problem, generalized past the Core: any OTHER hub the tree
	# wants to fan out to more children than a single physical Splitter can
	# support is just as broken - a Common/Uncommon Splitter caps at 2
	# faces, Rare at 3 (SplitterTile's max_faces_by_rarity) - and the
	# previous version of this solver picked whichever Splitter happened to
	# be FIRST in inventory regardless of how many faces the hub actually
	# needed, so a 3-child hub could silently get handed a 2-cap Splitter
	# and end up with 3 active_faces anyway. Real playtest report: "there is
	# only one 3 way in the inventory" - two different hubs were both
	# showing 3-face fan-out even though starter inventory only ever has
	# ONE Splitter whose rarity actually supports 3 faces.
	#
	# Fix: figure out, up front, which cap each hub will actually get by
	# greedily matching the highest-DEMAND hubs against the highest-CAP
	# Splitters still in inventory (a hub that only needs 2 faces shouldn't
	# hog the one Rare Splitter a 3-face hub actually needs). Any hub that
	# still can't be satisfied by anything left over gets demoted exactly
	# like Core above. Step 5 below processes hubs in this same
	# demand-descending order when it actually consumes tiles, so the real
	# placement matches what this planning pass already proved was
	# possible - and doesn't let a single-child node's Splitter/Reflector
	# fallback burn through the pool's biggest Splitters as filler before a
	# real multi-child hub gets a turn.
	var available_splitter_caps: Array = []
	for t in inventory:
		if t.tile_type == "Splitter" and t.has_method("get_max_faces"):
			available_splitter_caps.append(t.get_max_faces())
	available_splitter_caps.sort()

	var fanout_v: Array = []
	for v in tree_nodes.keys():
		if v == start_v:
			continue
		var v_is_target = false
		for t in targets:
			if t.q == v.x and t.r == v.y:
				v_is_target = true
				break
		if v_is_target:
			continue
		if tree_nodes[v].size() > 1:
			fanout_v.append(v)
	fanout_v.sort_custom(func(a, b): return tree_nodes[a].size() > tree_nodes[b].size())

	for v in fanout_v:
		var demand = tree_nodes[v].size()
		# Best fit: smallest available cap that's still >= demand, so bigger
		# caps stay in the pool for hubs that need them more.
		var pick_i = -1
		for i in range(available_splitter_caps.size()):
			if available_splitter_caps[i] >= demand:
				pick_i = i
				break
		if pick_i >= 0:
			available_splitter_caps.remove_at(pick_i)
			locked_v[v] = true # satisfiable as-is, but still finalized - see locked_v doc
			continue # this hub's demand is satisfiable, leave tree_nodes as-is
		# Nothing left can cover this hub's full demand - take the largest
		# remaining cap (if any) and demote the rest, same as Core.
		var fallback_cap = 1
		if available_splitter_caps.size() > 0:
			fallback_cap = available_splitter_caps[available_splitter_caps.size() - 1]
			available_splitter_caps.remove_at(available_splitter_caps.size() - 1)
		_demote_excess_children(v, fallback_cap, tree_nodes, parent_map, valid_map, start_v, targets, locked_v)
		locked_v[v] = true

	# 5. Place tiles - multi-child (Splitter) hubs first, highest demand
	# first, so the cap-aware pick in the num_children > 1 branch below
	# consumes tiles in the exact order 4.6 planned against.
	var iteration_order: Array = []
	if tree_nodes.has(start_v):
		iteration_order.append(start_v)
	var remaining_v: Array = []
	for v in tree_nodes.keys():
		if v != start_v:
			remaining_v.append(v)
	remaining_v.sort_custom(func(a, b):
		var da = tree_nodes[a].size()
		var db = tree_nodes[b].size()
		if da != db:
			return da > db
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	iteration_order.append_array(remaining_v)

	for v in iteration_order:
		var h = HexCoord.new(v.x, v.y)

		# The Core (start) is ALSO always listed in targets/fixed_sinks (the
		# Torso itself is one of its own "sinks" for BFS-reachability
		# purposes), so it must be handled BEFORE the generic is_target skip
		# below, not after - checking is_target first made this branch
		# unreachable dead code, silently leaving the Core's active_faces at
		# whatever it started as (its construction default, [0]/East-only)
		# no matter how many directions the spanning tree actually wanted it
		# to fan out to. Real playtest report: "literally all of the energy
		# goes to the right arm, nothing goes to the backpack or head" - the
		# tree WAS correctly computed (tiles got placed at every branch),
		# the Core itself just never got told to actually use them.
		if h.q == start.q and h.r == start.r:
			var start_tile = grid.get_tile(start)
			if start_tile and "active_faces" in start_tile:
				start_tile.active_faces.clear()
				for child_v in tree_nodes[v]:
					var exit_dir = _get_direction(h, HexCoord.new(child_v.x, child_v.y))
					start_tile.active_faces.append(exit_dir)
			continue

		# Skip (non-Core) targets - they're fixed sinks, not tiles this
		# solver places or reconfigures.
		var is_target = false
		for t in targets:
			if t.q == h.q and t.r == h.r:
				is_target = true
				break

		if is_target:
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
			# Needs a Splitter - cap-aware pick (see 4.6 above), not just the
			# first Splitter in inventory.
			var split_idx = _find_splitter_index_for_faces(inventory, num_children)
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

# Shared by Core's own cap-check (4.5) and the general Splitter-hub cap
# check right after it (4.6). Demotes tree_nodes[v] down to `cap` children
# ONE AT A TIME, actually verifying each demotion finds a legal reroute
# before committing to it - a fixed "always drop the trailing children"
# rule (the original approach) can pick an UNSAFE child to drop even when a
# SAFE one was available on the very same hub: a direct-neighbor sink with
# only one possible parent (e.g. an Arm Link whose sole valid_map neighbor
# is its hub) can NEVER be dropped without going permanently unreachable,
# while a relay hex with other neighbors often can. Worse, which HUB gets
# demoted matters too, not just which child of it: real playtest repro (a
# real starter inventory with exactly one Rare-capable Splitter, two hubs
# both wanting 3 faces) - demoting one specific hub had zero legal reroutes
# for ANY of its children (every neighbor was either a sink or led back
# through the very branch being cut), while demoting the OTHER hub instead
# had a clean reroute available. _try_reattach (below) actually attempts
# and verifies each candidate rather than assuming one will work.
func _demote_excess_children(v: Vector2i, cap: int, tree_nodes: Dictionary, parent_map: Dictionary, valid_map: Dictionary, root_v: Vector2i, targets: Array, locked_v: Dictionary = {}) -> void:
	if not tree_nodes.has(v):
		return
	while tree_nodes[v].size() > cap:
		var direct_children: Array = tree_nodes[v]
		# Try dropping each child in turn - order by valid_map neighbor
		# count descending as a cheap heuristic (more neighbors = more
		# likely to have somewhere else to go), but correctness comes from
		# _try_reattach actually verifying success, not from this ordering.
		var candidates: Array = direct_children.duplicate()
		candidates.sort_custom(func(a, b): return _neighbor_count(a, valid_map) > _neighbor_count(b, valid_map))

		var dropped_one = false
		for candidate in candidates:
			direct_children.erase(candidate)
			var connected = _connected_set(root_v, tree_nodes)
			if connected.has(candidate):
				# Still reachable some other way already (a diamond in the
				# tree, or it was re-swept in by an earlier iteration) -
				# nothing further to do for this one.
				dropped_one = true
				break
			if _try_reattach(candidate, tree_nodes, parent_map, valid_map, targets, connected, v, locked_v):
				dropped_one = true
				break
			# This candidate has no legal reroute - put it back and try the
			# next one instead.
			direct_children.append(candidate)

		if not dropped_one:
			# Every child of v is unsafe to drop in this topology - give up
			# demoting further rather than break reachability. v ends up
			# over its ideal cap (step 5's Splitter selection will fall
			# back to spawning a generic tile matching the component's own
			# rarity for it, same as the pre-existing empty-inventory
			# fallback), but nothing gets orphaned.
			break

# Every hex currently reachable from Core (root_v) by walking tree_nodes
# forward - the "already safely connected" set _try_reattach searches from
# and demotion-safety checks against.
func _connected_set(root_v: Vector2i, tree_nodes: Dictionary) -> Dictionary:
	var connected := {}
	var frontier = [root_v]
	connected[root_v] = true
	while frontier.size() > 0:
		var cur = frontier.pop_front()
		for child in tree_nodes.get(cur, []):
			if not connected.has(child):
				connected[child] = true
				frontier.append(child)
	return connected

# Ordering heuristic only (see _demote_excess_children) - how many
# geometrically valid hexes border v, regardless of tree membership.
func _neighbor_count(v: Vector2i, valid_map: Dictionary) -> int:
	var h = HexCoord.new(v.x, v.y)
	var count = 0
	for d in range(6):
		var n = h.neighbor(d)
		if valid_map.has(Vector2i(n.q, n.r)):
			count += 1
	return count

# Attempts to find a legal new parent for the orphaned node `e` (and
# whatever subtree already hangs off it, untouched) via BFS from every hex
# already in `connected`. On success, splices e (and any newly-discovered
# intermediate hexes) into tree_nodes/parent_map as real tree edges and
# returns true; returns false (no mutation at all) if no legal route
# exists, so a failed attempt is safe to just retry with a different
# candidate.
#
# Three things are blocked from ever being used as a source OR an
# intermediate pass-through hop (not just as a source - if left open as a
# discoverable neighbor during expansion, the BFS could still route
# THROUGH one as a stepping stone and undo the very thing it's blocking):
#   - v itself: e is by definition already 1 hop from v (that's why it's
#     excess) - allowing v back in would just rediscover that same edge.
#   - every hex in locked_v: hubs whose own capacity was ALREADY finalized
#     earlier in this same solve (Core once 4.5 runs, then each fanout hub
#     as 4.6 finishes deciding it). Skipping this let a LATER hub's excess
#     branch land right back on an EARLIER hub that was already capped,
#     silently pushing it back over its own limit (caught via a real
#     playtest repro: Core ended up with active_faces=[0, 3] - 2 faces -
#     despite being a Common core capped to 1).
#   - every fixed-sink target (other than e itself, since e can legally BE
#     one - that's the normal "reattach a Link back to the tree" case):
#     sinks don't relay energy (step 5 skips configuring them entirely), so
#     routing THROUGH one as a pass-through hop would produce a tree edge
#     step 5 can never actually power.
func _try_reattach(e: Vector2i, tree_nodes: Dictionary, parent_map: Dictionary, valid_map: Dictionary, targets: Array, connected: Dictionary, v: Vector2i, locked_v: Dictionary) -> bool:
	var reattach_from = {}
	var reattach_queue = []
	reattach_from[v] = null
	for lv in locked_v.keys():
		reattach_from[lv] = null
	for t in targets:
		var tv = Vector2i(t.q, t.r)
		if tv != e:
			reattach_from[tv] = null
	for c in connected.keys():
		if reattach_from.has(c):
			continue
		reattach_from[c] = null
		reattach_queue.append(c)
	var reached = false
	while reattach_queue.size() > 0 and not reached:
		var cur = reattach_queue.pop_front()
		var cur_h = HexCoord.new(cur.x, cur.y)
		for d in range(6):
			var n = cur_h.neighbor(d)
			var nv = Vector2i(n.q, n.r)
			if valid_map.has(nv) and not reattach_from.has(nv):
				reattach_from[nv] = cur
				if nv == e:
					reached = true
					break
				reattach_queue.append(nv)
	if not reached:
		return false
	var new_path = []
	var walk = e
	while walk != null and not connected.has(walk):
		new_path.insert(0, walk)
		walk = reattach_from.get(walk, null)
	var prev = walk
	for node in new_path:
		if not tree_nodes.has(prev):
			tree_nodes[prev] = []
		if not tree_nodes[prev].has(node):
			tree_nodes[prev].append(node)
		parent_map[node] = prev
		prev = node
	return true

# Cap-aware Splitter lookup for a hex that needs to fan out to num_faces
# children - a plain first-match lookup could hand a Common Splitter
# (get_max_faces() == 2, per SplitterTile's max_faces_by_rarity) a 3-child
# job and silently set 3 active_faces on a tile whose own rarity cap only
# supports 2. Picks the SMALLEST-cap Splitter that's still big enough (best
# fit) so bigger-cap tiles stay available for whichever other hub in this
# same tree actually needs them - paired with the demand-descending
# processing order in step 5 and the cap check/demotion pass in 4.6, which
# already proved a big-enough tile exists in inventory for every node that
# reaches this point undemoted.
func _find_splitter_index_for_faces(inventory: Array, num_faces: int) -> int:
	var best_idx = -1
	var best_cap = -1
	for i in range(inventory.size()):
		var t = inventory[i]
		if t.tile_type != "Splitter":
			continue
		var cap = t.get_max_faces() if t.has_method("get_max_faces") else 6
		if cap < num_faces:
			continue
		if best_idx == -1 or cap < best_cap:
			best_idx = i
			best_cap = cap
	return best_idx

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
