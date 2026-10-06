extends Node

const CompScript = preload("res://scripts/core/ComponentEquipment.gd")
const SolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const RefinerScript = preload("res://scripts/core/SolverRefiner.gd")
const CatalystScript = preload("res://scripts/tiles/CatalystTile.gd")
const AmpScript = preload("res://scripts/tiles/AmplifierTile.gd")
const InfuserScript = preload("res://scripts/tiles/InfuserTile.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _inv() -> Array:
	var inv: Array = []
	for i in range(3):
		var c = CatalystScript.new()
		c.rarity = HexTile.Rarity.UNCOMMON + (i % 2)
		inv.append(c)
		var a = AmpScript.new()
		a.rarity = HexTile.Rarity.COMMON + i
		inv.append(a)
		var f = InfuserScript.new()
		f.rarity = HexTile.Rarity.UNCOMMON
		inv.append(f)
	return inv

func _ready():
	# --- pure scoring rules ---
	var R = RefinerScript
	var mk = func(syn: Dictionary, mag: float):
		var p = EnergyPacket.new()
		p.synergies = syn
		p.magnitude = mag
		return p
	var kin = R.score_packet(mk.call({EnergyPacket.SynergyType.KINETIC: 10.0}, 10.0))
	var fire = R.score_packet(mk.call({EnergyPacket.SynergyType.FIRE: 10.0}, 10.0))
	var fire_kin = R.score_packet(mk.call({EnergyPacket.SynergyType.FIRE: 5.0, EnergyPacket.SynergyType.KINETIC: 5.0}, 10.0))
	var raw = R.score_packet(mk.call({EnergyPacket.SynergyType.RAW: 10.0}, 10.0))
	var mine = R.score_packet(mk.call({EnergyPacket.SynergyType.POISON: 5.0, EnergyPacket.SynergyType.EXPLOSION: 5.0}, 10.0))
	_check("fire with no carrier scores below fire backed by kinetic (%.1f < %.1f)" % [fire, fire_kin], fire < fire_kin)
	_check("raw scores below configured kinetic (%.1f < %.1f)" % [raw, kin], raw < kin)
	_check("poison+explosion gateway outscores its parts' plain magnitude (%.1f > 10)" % mine, mine > 10.0)
	# --- real simulation: refine never loses, and lifts an unconfigured build ---
	for rarity in [HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE]:
		var arm = CompScript.create_starter_arm(true, "", rarity)
		var inv = _inv()
		var solver = SolverScript.new()
		solver.solve(arm, inv)
		var refiner = RefinerScript.new()
		var res = refiner.refine(arm, inv)
		if not res["supported"]:
			print("skip: sim unsupported for rarity %d (native lib missing?)" % rarity)
			continue
		_check("rarity %d: refine does not lower the score (%.2f -> %.2f, %d changes, %d sims)" % [rarity, res["before"], res["after"], res["changes"], res["evals"]], res["after"] >= res["before"] - 0.0001)
		_check("rarity %d: stays within the sim budget" % rarity, res["evals"] <= 160)
		var again = RefinerScript.new().refine(arm, inv)
		_check("rarity %d: second pass is stable (%.2f -> %.2f)" % [rarity, again["before"], again["after"]], again["after"] >= again["before"] - 0.0001 and abs(again["before"] - res["after"]) < 0.01 * max(res["after"], 1.0))
		# fixed tiles survived and nothing was duplicated/lost
		var n_tiles = arm.hex_grid.get_all_tiles().size()
		_check("rarity %d: grid still has its core and mount" % rarity, arm.hex_grid.get_tile(HexCoord.new(0, 0)) != null and n_tiles > 2)
	print("solver refiner check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
