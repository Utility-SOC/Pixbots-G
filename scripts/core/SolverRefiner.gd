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
	for t in grid.get_all_tiles():
		t.reset_simulation_state()
		if t.has_method("clear_pending"):
			t.clear_pending()
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
	if not RustSim.try_simulate(grid, pkts, true):
		return -1.0
	var total = 0.0
	var delivered = 0.0
	for t in grid.get_all_tiles():
		if t.tile_type.ends_with("Mount") and "pending_packets" in t:
			for item in t.pending_packets:
				total += score_packet(item.packet)
				delivered += item.packet.magnitude
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
		for t in grid.get_all_tiles():
			t.reset_simulation_state()
			if t.has_method("clear_pending"):
				t.clear_pending()
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
	# Leave sim state consistent with the final layout.
	score(component)
	result["after"] = best
	result["evals"] = evals
	result["changes"] = changes
	return result

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
