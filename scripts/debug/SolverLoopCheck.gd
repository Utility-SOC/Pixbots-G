extends "res://scripts/debug/SolverBenchDiag.gd"

# Regression check for the refiner's deliberate-loop pass (SolverRefiner._loop_pass): on the same seeded arm and
# inventory, enabling loops must never lower the simulated score, an accepted loop must leave the grid unsaturated and
# without overloaded tiles, and on a spare-rich inventory at least one loop should actually be found.

var failures = 0

func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _arm_case(rarity: int, recipe: String, loops: bool) -> Dictionary:
	SimRng.seed_all(SEED)
	SolverScript._topology_cache.clear()
	var mech = _build_mech(rarity)
	var inv = _inventory(_recipes()[recipe])
	var solver = SolverScript.new()
	inv = solver.solve(mech.components[HexTile.BodySlot.TORSO], inv)
	var arm = mech.components[HexTile.BodySlot.ARM_R]
	inv = solver.solve(arm, inv)
	var rf = RefinerScript.new()
	rf.enable_loops = loops
	var res = rf.refine(arm, inv)
	var out = {"after": res["after"], "loops": int(res.get("loops", 0)), "sat": arm.hex_grid.sim_saturated, "over": arm.hex_grid.flow_overload.size()}
	mech.queue_free()
	return out

func _ready():
	var total_loops = 0
	for spec in [[HexTile.Rarity.UNCOMMON, "enemy"], [HexTile.Rarity.RARE, "enemy"], [HexTile.Rarity.UNCOMMON, "mid"], [HexTile.Rarity.RARE, "rich"]]:
		var off = _arm_case(spec[0], spec[1], false)
		var on = _arm_case(spec[0], spec[1], true)
		var tag = "r%d/%s" % [spec[0], spec[1]]
		_check("%s: loops never lower the score (%.1f -> %.1f, %d loops)" % [tag, off["after"], on["after"], on["loops"]], on["after"] >= off["after"] - 0.0001)
		if on["loops"] > 0:
			_check("%s: an accepted loop leaves the arm unsaturated with no overloaded tile" % tag, not on["sat"] and on["over"] == 0)
			_check("%s: an accepted loop strictly raises the score" % tag, on["after"] > off["after"])
		total_loops += on["loops"]
	_check("at least one deliberate loop was found across the cases (%d)" % total_loops, total_loops >= 1)
	SimRng.unseed()
	print("solver loop check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
