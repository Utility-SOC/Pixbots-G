class_name SolverRefiner
extends RefCounted

# Second stage of Auto-Equip. AutoEquipSolver builds a legal, routed layout by topology; this pass
# then runs the REAL grid simulation and hill-climbs the tiles whose position does not matter
# (Amplifier / Catalyst / Elemental Infuser): which element each one is set to, which spare of which
# rarity sits in the slot, and whether a different conditioner type belongs there. Every candidate is
# scored by what the weapon mounts actually receive, so the result is measured, not guessed.
#
# Scoring (see score_packet) is deliberately explicit design, not a black box:
#   magnitude delivered            the base value
#   x element diversity            up to 3 elements >= 15% each, +25% apiece
#   x gateway combos               poison+explosion (mines) and poison+fire (turrets) +25%
#   x reach                        kinetic/pierce >= 15% carries a shot; fire/ice/poison/vortex-heavy
#                                  packets with no carrier stall near the muzzle, x0.6
#   x pure-raw penalty             unconfigured RAW packets carry no element role, x0.5
# plus a small bonus for energy that actually reaches a mount rather than dying in the grid.

const SYN = EnergyPacket.SynergyType
const CONFIG_ELEMENTS = [SYN.KINETIC, SYN.PIERCE, SYN.FIRE, SYN.ICE, SYN.LIGHTNING, SYN.POISON, SYN.EXPLOSION, SYN.VORTEX, SYN.VAMPIRIC]
const CONDITIONERS = ["Amplifier", "Catalyst", "Elemental Infuser"]
const RustSim = preload("res://scripts/core/RustGridSim.gd")
const RAW_FACTOR = 0.5 # an unconfigured packet carries no element role at all
const MIN_GAIN = 0.002 # relative; ignore noise-level improvements

const INPUT_MAGNITUDE = 100.0
var _feed_dir: int = -1
var evals: int = 0
var max_evals: int = 120

static func score_packet(p) -> float:
	var total = 0.0
	for k in p.synergies:
		total += max(float(p.synergies[k]), 0.0)
	if total <= 0.0 or p.magnitude <= 0.0:
		return 0.0
	var r: Dictionary = {}
	for k in p.synergies:
		r[int(k)] = float(p.synergies[k]) / total
	var distinct = 0
	for k in r:
		if k != SYN.RAW and r[k] >= 0.15:
			distinct += 1
	var m = 1.0 + 0.25 * min(distinct - 1, 2) if distinct > 1 else 1.0
	var gateway = r.get(SYN.POISON, 0.0) >= 0.15 and (r.get(SYN.EXPLOSION, 0.0) >= 0.15 or r.get(SYN.FIRE, 0.0) >= 0.15)
	if gateway:
		m *= 1.25 # mines / flame turrets do not need a carrier: they sit where they land
	var carrier = r.get(SYN.KINETIC, 0.0) >= 0.15 or r.get(SYN.PIERCE, 0.0) >= 0.15
	var stally = r.get(SYN.FIRE, 0.0) + r.get(SYN.ICE, 0.0) + r.get(SYN.POISON, 0.0) + r.get(SYN.VORTEX, 0.0)
	if stally >= 0.5 and not carrier and not gateway:
		m *= 0.6
	if r.get(SYN.RAW, 0.0) >= 0.9:
		m *= RAW_FACTOR
	return p.magnitude * m

# Simulates the component as it stands and scores every mount's received packets. Returns -1.0 when
# the grid holds a tile the fast simulator does not support (the caller then leaves the build alone).
func score(component) -> float:
	evals += 1
	var grid = component.hex_grid
	grid.clear_sim_residue()
	var generated = 0.0
	var pkts: Array = []
	for t in grid.get_all_tiles():
		if t.has_method("generate_energy"):
			for p in t.generate_energy(grid):
				p.position = t.grid_position
				generated += p.magnitude
				pkts.append(p)
	if pkts.is_empty():
		# Limbs, head, backpack: energy arrives from the torso link. Feed one standard RAW packet in
		# at the intake, from the side that actually carries it to a mount (found once, then reused).
		if _feed_dir < 0:
			# Remembered on the component so repeat passes score on the same footing.
			if component.has_meta("refiner_feed_dir"):
				_feed_dir = int(component.get_meta("refiner_feed_dir"))
			else:
				_feed_dir = _find_feed_dir(component)
				component.set_meta("refiner_feed_dir", _feed_dir)
		pkts.append(_feed_packet(_feed_dir))
		generated = INPUT_MAGNITUDE
	# The sim only ever SETS the saturation/overload flags; clear them so each trial is judged on its own layout.
	grid.reset_flow()
	if not RustSim.try_simulate(grid, pkts, true):
		return -1.0
	var total = 0.0
	var delivered = 0.0
	for t in grid.get_all_tiles():
		if t.tile_type.ends_with("Mount") and "pending_packets" in t:
			var m_total = 0.0
			var m_mag = 0.0
			for item in t.pending_packets:
				m_total += score_packet(item.packet)
				m_mag += item.packet.magnitude
			# A mount can only fire its capped payload; overcharge records beyond that are wasted.
			if m_mag > EnergyPacket.NORMAL_MAGNITUDE_CAP:
				m_total *= EnergyPacket.NORMAL_MAGNITUDE_CAP / m_mag
				m_mag = EnergyPacket.NORMAL_MAGNITUDE_CAP
			total += m_total
			delivered += m_mag
	var reach_bonus = 1.0 + 0.1 * minf(1.0, delivered / generated if generated > 0.0 else 0.0)
	return total * reach_bonus

func _feed_packet(d: int) -> EnergyPacket:
	var p = EnergyPacket.new(INPUT_MAGNITUDE, HexCoord.new(0, 0).neighbor((d + 3) % 6))
	p.direction = d
	p.is_active = true
	return p

# The torso link's packet enters this component moving along `d`; try all six and keep the one whose
# simulation delivers the most to a mount (the real attach side differs per limb).
func _find_feed_dir(component) -> int:
	var best_d = 0
	var best_total = -1.0
	var grid = component.hex_grid
	for d in range(6):
		grid.clear_sim_residue()
		if not RustSim.try_simulate(grid, [_feed_packet(d)], true):
			return 0
		var total = 0.0
		for t in grid.get_all_tiles():
			if t.tile_type.ends_with("Mount") and "pending_packets" in t:
				for item in t.pending_packets:
					total += item.packet.magnitude
		if total > best_total:
			best_total = total
			best_d = d
	return best_d

func _conditioner_coords(component) -> Array:
	var out: Array = []
	for t in component.hex_grid.get_all_tiles():
		if t.tile_type in CONDITIONERS and t.grid_position != null:
			out.append(Vector2i(t.grid_position.q, t.grid_position.r))
	return out

func _set_element(tile, el: int) -> void:
	if tile.tile_type == "Catalyst":
		tile.target_synergy = el
	elif tile.tile_type == "Elemental Infuser":
		tile.secondary_synergy = el

func _get_element(tile) -> int:
	if tile.tile_type == "Catalyst":
		return int(tile.target_synergy)
	if tile.tile_type == "Elemental Infuser":
		return int(tile.secondary_synergy)
	return -1

# Returns {"before", "after", "evals", "changes"}; "supported": false when the sim could not run.
func refine(component, inventory: Array, budget: int = 120) -> Dictionary:
	max_evals = budget
	evals = 0
	var base = score(component)
	var result = {"before": base, "after": base, "evals": evals, "changes": 0, "supported": base >= 0.0}
	if base < 0.0:
		return result
	var best = base
	var changes = 0
	# Seed: a Catalyst downstream of an Infuser (default target RAW) converts everything back to RAW,
	# so single-tile changes can never show a gain from a blank layout. Try every element on ALL the
	# configurable tiles at once, keep the best uniform setting, then refine tile by tile.
	var cfg: Array = []
	for v in _conditioner_coords(component):
		var t0 = component.hex_grid.get_tile(HexCoord.new(v.x, v.y))
		if t0 != null and t0.tile_type != "Amplifier":
			cfg.append(t0)
	if not cfg.is_empty():
		var orig_els: Array = []
		for t0 in cfg:
			orig_els.append(_get_element(t0))
		var seed_el = -1
		for el in CONFIG_ELEMENTS:
			for t0 in cfg:
				_set_element(t0, el)
			var s0 = score(component)
			if s0 > best * (1.0 + MIN_GAIN):
				best = s0
				seed_el = el
		for i in range(cfg.size()):
			_set_element(cfg[i], seed_el if seed_el >= 0 else orig_els[i])
		if seed_el >= 0:
			changes += 1
	var improved = true
	var rounds = 0
	while improved and rounds < 3 and evals < max_evals:
		improved = false
		rounds += 1
		for v in _conditioner_coords(component):
			if evals >= max_evals:
				break
			var tile = component.hex_grid.get_tile(HexCoord.new(v.x, v.y))
			if tile == null:
				continue
			# 1. element choice for this tile
			if tile.tile_type != "Amplifier":
				var cur = _get_element(tile)
				var best_el = cur
				for el in CONFIG_ELEMENTS:
					if el == cur or evals >= max_evals:
						continue
					_set_element(tile, el)
					var s = score(component)
					if s > best * (1.0 + MIN_GAIN):
						best = s
						best_el = el
				_set_element(tile, best_el)
				if best_el != cur:
					improved = true
					changes += 1
			# 2. swap in a spare of the same or another conditioner type / better rarity
			var swap = _try_swaps(component, inventory, v, best)
			if swap > best:
				best = swap
				improved = true
				changes += 1
	# Deliberate loops: ping-pong pockets (see _loop_pass). Own budget so element tuning is never starved.
	if enable_loops:
		var loop_res = _loop_pass(component, inventory, best)
		best = loop_res["score"]
		changes += loop_res["added"]
		result["loops"] = loop_res["added"]
	# Leave sim state consistent with the final layout (flow for the Garage overlay), but with no packets still queued
	# on tiles: the next real recalculation must start clean.
	score(component)
	component.hex_grid.clear_sim_residue()
	result["after"] = best
	result["evals"] = evals
	result["changes"] = changes
	return result

# ---- Deliberate loops -------------------------------------------------------------------------------------------
# A packet sent into an EMPTY dead-end corridor travels to the edge of the valid hexes, bounces and returns with 5%
# loss per hex, so a Splitter with a side corridor is a loop with no wiring at all. Splitters divide energy, so a
# lap's gain is (share sent into the corridor) x (Amplifier gain, applied on the way out AND back) x 0.95^(2 x hexes);
# below 1 the packet settles and the mount sees the geometric series (a stable boost), above 1 it runs away to the cap.
# The sim is the judge: a candidate is kept only if the score rises and the grid does not saturate or overload.
const LOOP_MAX_ADDED = 3
const LOOP_EVAL_BUDGET = 400
const LOOP_REPLACEABLE = ["Directional Conduit", "Amplifier", "Catalyst", "Elemental Infuser"]
var enable_loops: bool = true
# Bounded overcharge (SaveManager.overcharge_loops, default on): a loop may exceed gain 1 and run to the step cap, because
# each mount's payload is clamped to NORMAL_MAGNITUDE_CAP and the step cap makes the sim deterministic. Candidates are
# only kept if the capped sim score rises, and LOOP_MAX_ADDED still limits the count, so the runaway stays local.
# Off = stable (gain < 1) loops only.
var allow_overcharge: bool = true

func _free_corridor(component, grid, x: Vector2i, d: int) -> Array:
	var offsets = HexCoord.get_direction_offsets()
	var valid := {}
	for h in component.valid_hexes:
		valid[Vector2i(h.q, h.r)] = true
	var cells: Array = []
	var cur = x + offsets[d]
	while valid.has(cur) and grid.get_tile(HexCoord.new(cur.x, cur.y)) == null:
		cells.append(cur)
		cur += offsets[d]
	# Must end at the edge of the valid area (so the packet bounces back), not at another tile.
	if valid.has(cur):
		return []
	return cells

func _flow_distance(grid) -> Dictionary:
	var dist := {Vector2i(0, 0): 0}
	var frontier = [Vector2i(0, 0)]
	var offsets = HexCoord.get_direction_offsets()
	while frontier.size() > 0:
		var cur = frontier.pop_front()
		for d in range(6):
			var nv = cur + offsets[d]
			if not dist.has(nv) and grid.flow.has(nv):
				dist[nv] = dist[cur] + 1
				frontier.append(nv)
	return dist

func _spare_indices(inventory: Array, tile_type: String) -> Array:
	var idx: Array = []
	for i in range(inventory.size()):
		if inventory[i].tile_type == tile_type:
			idx.append(i)
	# best rarity first
	idx.sort_custom(func(a, b): return inventory[a].rarity > inventory[b].rarity)
	return idx

func _loop_pass(component, inventory: Array, start_score: float) -> Dictionary:
	var grid = component.hex_grid
	var out = {"score": start_score, "added": 0}
	var spent = 0
	var current = start_score
	while out["added"] < LOOP_MAX_ADDED and spent < LOOP_EVAL_BUDGET:
		if _spare_indices(inventory, "Splitter").is_empty():
			break
		score(component) # fresh flow for the current layout
		var dist = _flow_distance(grid)
		var best_move = null
		var best_score = current
		var offsets = HexCoord.get_direction_offsets()
		for t in grid.get_all_tiles():
			if spent >= LOOP_EVAL_BUDGET:
				break
			if not (t.tile_type in LOOP_REPLACEABLE) or t.grid_position == null:
				continue
			var xv = Vector2i(t.grid_position.q, t.grid_position.r)
			if not dist.has(xv):
				continue
			# Downstream neighbour: the occupied flow neighbour one step further from the intake.
			var forward = -1
			for d in range(6):
				var nv = xv + offsets[d]
				if dist.has(nv) and dist[nv] == dist[xv] + 1:
					forward = d
					break
			if forward < 0:
				continue
			for d in range(6):
				if d == forward or spent >= LOOP_EVAL_BUDGET:
					continue
				var corridor = _free_corridor(component, grid, xv, d)
				if corridor.size() < 1:
					continue
				for variant in _amp_variants(inventory, corridor.size()):
					if spent >= LOOP_EVAL_BUDGET:
						break
					var s = _try_loop_move(component, inventory, xv, forward, d, corridor, variant)
					spent += 1
					if s > best_score * (1.0 + MIN_GAIN):
						best_score = s
						best_move = [xv, forward, d, corridor, variant]
		if best_move == null:
			break
		# Apply the winner for real (the trial above always reverted).
		_apply_loop_move(component, inventory, best_move[0], best_move[1], best_move[2], best_move[3], best_move[4], false)
		current = score(component)
		out["added"] += 1
		out["score"] = current
	return out

# Amplifier placements to try in a corridor of `length` cells: none; one amp (each distinct spare rarity) at each cell;
# two best spares at the first two cells. Tile references, not inventory indices (the Splitter swap shifts those).
func _amp_variants(inventory: Array, length: int) -> Array:
	var variants: Array = [[]]
	var by_rarity: Dictionary = {}
	for t in inventory:
		if t.tile_type == "Amplifier" and not by_rarity.has(t.rarity):
			by_rarity[t.rarity] = t
	for r in by_rarity:
		for pos in range(length):
			variants.append([[by_rarity[r], pos]])
	var spares = _spare_indices(inventory, "Amplifier")
	if spares.size() >= 2 and length >= 2:
		variants.append([[inventory[spares[0]], 0], [inventory[spares[1]], 1]])
	return variants

# Returns the score with the loop applied (or -1.0 when it saturates/overloads/cannot run), then reverts.
func _try_loop_move(component, inventory: Array, xv: Vector2i, forward: int, d: int, corridor: Array, variant: Array) -> float:
	var undo = _apply_loop_move(component, inventory, xv, forward, d, corridor, variant, true)
	if undo == null:
		return -1.0
	var s = score(component)
	var grid = component.hex_grid
	if (grid.sim_saturated or not grid.flow_overload.is_empty()) and not allow_overcharge:
		s = -1.0
	_revert_loop_move(component, inventory, undo)
	return s

# Swaps a spare Splitter in at xv (faces: forward + d) and puts `amps` spare Amplifiers into the corridor.
# With record=true returns an undo record; the caller reverts. Returns null when it cannot be applied.
func _apply_loop_move(component, inventory: Array, xv: Vector2i, forward: int, d: int, corridor: Array, variant: Array, record: bool):
	var grid = component.hex_grid
	var xh = HexCoord.new(xv.x, xv.y)
	var split_idx = _spare_indices(inventory, "Splitter")
	if split_idx.is_empty():
		return null
	var splitter = inventory[split_idx[0]]
	if splitter.has_method("get_max_faces") and splitter.get_max_faces() < 2:
		return null
	var original = grid.get_tile(xh)
	if original == null:
		return null
	inventory.erase(splitter)
	grid.remove_tile(xh)
	splitter.active_faces.clear()
	splitter.active_faces.append(forward)
	splitter.active_faces.append(d)
	grid.add_tile(xh, splitter)
	inventory.append(original)
	var placed: Array = []
	for av in variant:
		placed.append([av[0], corridor[av[1]]])
	for pr in placed:
		inventory.erase(pr[0])
		grid.add_tile(HexCoord.new(pr[1].x, pr[1].y), pr[0])
	return {"xh": xh, "splitter": splitter, "original": original, "placed": placed}

func _revert_loop_move(component, inventory: Array, undo: Dictionary) -> void:
	var grid = component.hex_grid
	for pr in undo["placed"]:
		grid.remove_tile(HexCoord.new(pr[1].x, pr[1].y))
		inventory.append(pr[0])
	grid.remove_tile(undo["xh"])
	inventory.erase(undo["original"])
	grid.add_tile(undo["xh"], undo["original"])
	inventory.append(undo["splitter"])

# Tries each distinct (type, rarity) spare in `inventory` in place of the tile at v; keeps the best
# improvement (returns its score) or restores the original (returns the unchanged best).
func _try_swaps(component, inventory: Array, v: Vector2i, best: float) -> float:
	var grid = component.hex_grid
	var h = HexCoord.new(v.x, v.y)
	var original = grid.get_tile(h)
	if original == null:
		return best
	var rot = original.rotation_steps if "rotation_steps" in original else 0
	var seen: Dictionary = {}
	var best_idx = -1
	var best_score = best
	for i in range(inventory.size()):
		if evals >= max_evals:
			break
		var cand = inventory[i]
		if not (cand.tile_type in CONDITIONERS):
			continue
		var sig = "%s|%d|%d" % [cand.tile_type, cand.rarity, _get_element(cand)]
		if seen.has(sig):
			continue
		seen[sig] = true
		if cand.tile_type == original.tile_type and cand.rarity <= original.rarity and _get_element(cand) == _get_element(original):
			continue
		grid.remove_tile(h)
		if "rotation_steps" in cand:
			cand.rotation_steps = rot
		grid.add_tile(h, cand)
		var s = score(component)
		# a swapped-in configurable tile should also get its best element, not its stale one
		if cand.tile_type != "Amplifier":
			var cur_el = _get_element(cand)
			for el in CONFIG_ELEMENTS:
				if el == cur_el or evals >= max_evals:
					continue
				_set_element(cand, el)
				var s2 = score(component)
				if s2 > s:
					s = s2
					cur_el = el
			_set_element(cand, cur_el)
		grid.remove_tile(h)
		grid.add_tile(h, original)
		if s > best_score * (1.0 + MIN_GAIN):
			best_score = s
			best_idx = i
	if best_idx < 0:
		score(component) # restore sim state for the original
		return best
	# Commit the winner: original goes back to inventory.
	var winner = inventory[best_idx]
	grid.remove_tile(h)
	inventory.remove_at(best_idx)
	if "rotation_steps" in winner:
		winner.rotation_steps = rot
	grid.add_tile(h, winner)
	inventory.append(original)
	# winner's element must be re-optimised (the loop above left it on its best for the LAST tried state)
	var final_s = score(component)
	if winner.tile_type != "Amplifier":
		var cur = _get_element(winner)
		var be = cur
		for el in CONFIG_ELEMENTS:
			if el == cur or evals >= max_evals + 20:
				continue
			_set_element(winner, el)
			var s3 = score(component)
			if s3 > final_s:
				final_s = s3
				be = el
		_set_element(winner, be)
		score(component)
	return maxf(final_s, best)
