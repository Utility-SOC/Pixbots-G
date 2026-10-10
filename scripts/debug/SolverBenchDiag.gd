extends Node

# Mech-level scoreboard for Auto-Equip quality (docs: Status.md, Gameplay item G1). Builds a whole player mech at a
# given rarity, runs the Auto-Equip pipeline on each part (solver, then refiner, as GarageMenu does), simulates the
# real energy flow torso -> peripherals -> head/backpack return, and scores every weapon mount's packet with
# SolverRefiner.score_packet. Higher is better. This is a diagnostic scoreboard, not a pass/fail check: use it to A/B
# a solver change (same seeds, same inventories) and keep the change only if the total goes up.
#   godot --headless --path . res://scripts/debug/SolverBenchDiag.tscn
# Env: BENCH_NOREFINE=1 skips the refiner (topology-only solver quality). Deterministic: SimRng is seeded per case.

const CompScript = preload("res://scripts/core/ComponentEquipment.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const RefinerScript = preload("res://scripts/core/SolverRefiner.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const SEED = 20261009

const TILE_SCRIPTS = {
	"Amplifier": "res://scripts/tiles/AmplifierTile.gd",
	"Catalyst": "res://scripts/tiles/CatalystTile.gd",
	"Infuser": "res://scripts/tiles/InfuserTile.gd",
	"Splitter": "res://scripts/tiles/SplitterTile.gd",
	"Reflector": "res://scripts/tiles/ReflectorTile.gd",
	"Conduit": "res://scripts/tiles/DirectionalConduitTile.gd",
}

# inventory recipes: type -> [count, rarity]
func _recipes() -> Dictionary:
	var C = HexTile.Rarity.COMMON
	var U = HexTile.Rarity.UNCOMMON
	var R = HexTile.Rarity.RARE
	var L = HexTile.Rarity.LEGENDARY
	return {
		"lean": [["Amplifier", 2, C], ["Catalyst", 1, U], ["Infuser", 2, U], ["Splitter", 2, U], ["Reflector", 1, C]],
		"mid": [["Amplifier", 5, U], ["Catalyst", 3, U], ["Infuser", 5, R], ["Splitter", 4, R], ["Reflector", 3, U], ["Conduit", 4, C]],
		"rich": [["Amplifier", 10, R], ["Catalyst", 6, R], ["Infuser", 10, R], ["Splitter", 8, R], ["Reflector", 6, R], ["Conduit", 6, C], ["Amplifier", 3, L], ["Infuser", 3, L]],
		# What enemy bots get (MechLoadoutBuilder): ~25 each of Amplifier/Splitter/Infuser/Catalyst at the bot's rarity.
		"enemy": [["Amplifier", 25, U], ["Splitter", 25, U], ["Infuser", 25, U], ["Catalyst", 25, U], ["Reflector", 2, U]],
	}

func _inventory(recipe: Array) -> Array:
	var inv: Array = []
	for r in recipe:
		for i in range(int(r[1])):
			var t = load(TILE_SCRIPTS[r[0]]).new()
			t.rarity = int(r[2])
			inv.append(t)
	return inv

func _build_mech(rarity: int):
	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)
	var parts = [
		CompScript.create_starter_torso("", rarity),
		CompScript.create_starter_arm(false, "", rarity),
		CompScript.create_starter_arm(true, "", rarity),
		CompScript.create_starter_leg(false, "", rarity),
		CompScript.create_starter_leg(true, "", rarity),
		CompScript.create_starter_head("", rarity),
		CompScript.create_starter_backpack("", rarity),
	]
	for p in parts:
		mech.equip_component(p)
	return mech

func _slot_order() -> Array:
	# BENCH_ORDER=acc_first solves Head and Backpack right after the torso (they condition the energy that returns to
	# the torso, so they should get first pick of conditioners); default is the shipping order.
	if OS.get_environment("BENCH_ORDER") == "acc_first":
		return [HexTile.BodySlot.TORSO, HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK, HexTile.BodySlot.ARM_R, HexTile.BodySlot.ARM_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.LEG_L]
	return [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_R, HexTile.BodySlot.ARM_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]

# Score per MOUNT, not per record: a mount's packets are merged and clamped at the normal per-packet cap, so energy that
# only exists because a loop is saturating (the Garage warns about those) cannot buy score. Saturation is reported
# separately (sat = parts whose sim hit its step limit, over = parts with an overloaded tile).
func _score_mech(mech) -> Array:
	mech._recalculate_grid() # warm-up: drops any residue a trial sim left queued on tiles, so the score is steady-state
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
	var elems: Dictionary = {}
	for id in order:
		var m = merged[id]
		var cap = minf(1.0, EnergyPacket.NORMAL_MAGNITUDE_CAP / maxf(m["mag"], 1.0))
		var pk = EnergyPacket.new(m["mag"] * cap)
		pk.synergies = {}
		for k in m["syn"]:
			pk.synergies[k] = float(m["syn"][k]) * cap
			if float(m["syn"][k]) > 0.0 and int(k) != EnergyPacket.SynergyType.RAW:
				elems[int(k)] = true
		total += SolverRefiner.score_packet(pk)
	var sat = 0
	var over = 0
	var loops = 0
	for c in mech.components.values():
		if c and c.hex_grid:
			sat += 1 if c.hex_grid.sim_saturated else 0
			over += c.hex_grid.flow_overload.size()
			loops += c.hex_grid.flow_loops.size()
	# Reactor output, so results compare across rarities: gain = score / generated.
	var generated = 0.0
	var torso = mech.components.get(HexTile.BodySlot.TORSO)
	if torso:
		for t in torso.hex_grid.get_all_tiles():
			if t.has_method("generate_energy"):
				for pk in t.generate_energy(torso.hex_grid):
					generated += pk.magnitude
	return [total, order.size(), elems.size(), sat, over, loops, generated]

func _run_case(rarity: int, recipe_name: String, refine: bool) -> Array:
	SimRng.seed_all(SEED)
	SolverScript._topology_cache.clear()
	var mech = _build_mech(rarity)
	var inv = _inventory(_recipes()[recipe_name])
	var solver = SolverScript.new()
	for slot in _slot_order():
		if not mech.components.has(slot):
			continue
		var comp = mech.components[slot]
		inv = solver.solve(comp, inv)
		if refine:
			RefinerScript.new().refine(comp, inv)
	if refine and OS.get_environment("BENCH_MECHREFINE") == "1":
		var mr_res = MechRefiner.new().refine_accessories(mech)
		print("MECHREFINE r=%d %s before=%.1f after=%.1f evals=%d changes=%d" % [rarity, recipe_name, mr_res["before"], mr_res["after"], mr_res["evals"], mr_res["changes"]])
	var res = _score_mech(mech)
	mech.queue_free()
	return res

func _ready():
	var refine = OS.get_environment("BENCH_NOREFINE") != "1"
	var grand = 0.0
	var gain_sum = 0.0
	var log_sum = 0.0
	var n_cases = 0
	print("rarity  recipe   score        gain   mounts elems sat over loops  (refine=%s)" % str(refine))
	for rarity in [HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY]:
		for recipe_name in ["lean", "mid", "rich", "enemy"]:
			var t0 = Time.get_ticks_msec()
			var r = _run_case(rarity, recipe_name, refine)
			grand += r[0]
			var gain = r[0] / maxf(r[6], 1.0)
			gain_sum += gain
			log_sum += log(maxf(gain, 0.05))
			n_cases += 1
			print("BENCH r=%d %-5s %12.1f %9.3f %4d %4d %4d %4d %4d   %d ms" % [rarity, recipe_name, r[0], gain, r[1], r[2], r[3], r[4], r[5], Time.get_ticks_msec() - t0])
	SimRng.unseed()
	print("BENCH_TOTAL %.1f   GAIN_SUM %.3f   GAIN_GEOMEAN %.3f" % [grand, gain_sum, exp(log_sum / maxf(n_cases, 1))])
	get_tree().quit()
