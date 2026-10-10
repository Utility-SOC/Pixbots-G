class_name MechRefiner
extends RefCounted

# Mech-level companion to SolverRefiner (docs: Status.md, Gameplay item G1). SolverRefiner tunes one part against its own
# mounts, so the Head and Backpack, which have NO mounts and only condition the energy returning to the torso, were never
# tuned at all. This scores the WHOLE mech (real energy flow torso -> peripherals -> return -> mounts) and hill-climbs the
# elements of the Head/Backpack conditioners against that. Each evaluation is a full mech recalculation, so the budget is
# small and callers opt in (player Auto-Equip; not the per-spawn enemy path).

const SYN = EnergyPacket.SynergyType
const ACCESSORY_SLOTS = [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]
const MIN_GAIN = 0.002
var evals: int = 0

# Sum over mounts of SolverRefiner.score_packet, each mount's packets merged and clamped at the normal per-packet cap
# so energy that only exists because something is running away cannot buy score.
static func score_mech(mech) -> float:
	mech._recalculate_grid()
	var merged: Dictionary = {}
	var order: Array = []
	for w in mech.precalculated_weapons:
		var id = w["mount"].get_instance_id()
		if not merged.has(id):
			merged[id] = {"mag": 0.0, "syn": {}}
			order.append(id)
		var pk = w["packet"]
		merged[id]["mag"] += pk.magnitude
		for k in pk.synergies:
			merged[id]["syn"][k] = float(merged[id]["syn"].get(k, 0.0)) + float(pk.synergies[k])
	var total = 0.0
	for id in order:
		var m = merged[id]
		var cap = minf(1.0, EnergyPacket.NORMAL_MAGNITUDE_CAP / maxf(m["mag"], 1.0))
		var pk = EnergyPacket.new(m["mag"] * cap)
		pk.synergies = {}
		for k in m["syn"]:
			pk.synergies[k] = float(m["syn"][k]) * cap
		total += SolverRefiner.score_packet(pk)
	return total

func _configurable(comp) -> Array:
	var out: Array = []
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == "Catalyst" or t.tile_type == "Elemental Infuser":
			out.append(t)
	return out

func _get_el(t) -> int:
	return int(t.target_synergy) if t.tile_type == "Catalyst" else int(t.secondary_synergy)

func _set_el(t, el: int) -> void:
	if t.tile_type == "Catalyst":
		t.target_synergy = el
	else:
		t.secondary_synergy = el

# Returns {"before", "after", "evals", "changes"}.
func refine_accessories(mech, budget: int = 60) -> Dictionary:
	evals = 0
	var base = score_mech(mech)
	evals += 1
	var best = base
	var changes = 0
	for pass_i in range(2):
		var improved = false
		for slot in ACCESSORY_SLOTS:
			var comp = mech.components.get(slot)
			if comp == null or comp.hex_grid == null or comp.is_broken:
				continue
			for t in _configurable(comp):
				var cur = _get_el(t)
				var best_el = cur
				for el in SolverRefiner.CONFIG_ELEMENTS:
					if el == cur or evals >= budget:
						continue
					_set_el(t, el)
					var s = score_mech(mech)
					evals += 1
					if s > best * (1.0 + MIN_GAIN):
						best = s
						best_el = el
				_set_el(t, best_el)
				if best_el != cur:
					improved = true
					changes += 1
		if not improved or evals >= budget:
			break
	score_mech(mech) # leave the sim state consistent with the final layout
	return {"before": base, "after": best, "evals": evals, "changes": changes}
