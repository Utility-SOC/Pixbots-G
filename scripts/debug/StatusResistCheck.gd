extends Node

# Stun / Shock / Freeze Guard tiles (energy-fed): intake like the Heal Beacon (rarity-scaled), resistance proportional
# to the energy received (linear, capped at max_resist), several Guards adding up, only WORKING tiles counting, the
# status mapping, Mech.apply_status shortening the right status only, the save round trip, and the Rust grid sim
# treating the Guards as store-sinks (and Structural Strut as pass-through) instead of vetoing the whole grid.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const RustGridSimScript = preload("res://scripts/core/RustGridSim.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _guard(kind: String, rarity: int, energy: float = 0.0):
	var t = load("res://scripts/tiles/%sGuardTile.gd" % kind).new()
	t.rarity = rarity
	t.stored_energy = energy
	return t

func _mech_with(guards: Array):
	var m = MechScript.new()
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var coords = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(0, 1), HexCoord.new(-1, 1), HexCoord.new(1, -1), HexCoord.new(-1, 0), HexCoord.new(0, -1),
		HexCoord.new(2, 0), HexCoord.new(2, -1), HexCoord.new(0, 2), HexCoord.new(-1, 2), HexCoord.new(-2, 1)]
	for i in range(guards.size()):
		torso.hex_grid.add_tile(coords[i], guards[i])
	m.components[HexTile.BodySlot.TORSO] = torso
	m._recalculate_grid()
	return m

func _ready():
	var R = HexTile.Rarity
	var full: float = TileStatsRegistry.get_stat("StunGuardTile", "energy_for_max", 1500.0)
	var cap: float = TileStatsRegistry.get_stat("StunGuardTile", "max_resist", 0.9)

	# 1) The mapping and the cost.
	var ok := true
	for p in [["Stun", "concussed"], ["Shock", "paralyzed"], ["Freeze", "frozen"]]:
		ok = ok and _guard(p[0], 0).resisted_status == p[1]
	_check("Stun->concussed, Shock->paralyzed, Freeze->frozen", ok)
	_check("a Guard weighs far more than a Strut (mass is part of the cost)", _guard("Stun", 0).get_weight() >= 5.0 * load("res://scripts/tiles/StructuralStrutTile.gd").new().get_weight())

	# 2) Intake: absorbs the packet, rarity makes it a better converter.
	var g = _guard("Stun", R.COMMON)
	var pkt = EnergyPacket.new(100.0)
	pkt.is_active = true
	var out = g.process_energy(pkt, 0)
	_check("a Guard is a sink: nothing continues past it", out.is_empty() and not pkt.is_active)
	_check("common intake = magnitude (100)", is_equal_approx(g.stored_energy, 100.0))
	var gm = _guard("Stun", R.MYTHIC)
	var pkt2 = EnergyPacket.new(100.0)
	pkt2.is_active = true
	gm.process_energy(pkt2, 0)
	_check("mythic intake = magnitude x 3 (rarity coefficient 0.5 per tier)", is_equal_approx(gm.stored_energy, 300.0))
	_check("get_guard_energy reads and resets", is_equal_approx(gm.get_guard_energy(), 300.0) and gm.stored_energy == 0.0)

	# 3) Resistance proportional to energy, linear, capped.
	_check("no energy, no protection", is_equal_approx(g.resist_for_energy(0.0), 0.0))
	_check("half the full-protection energy gives half the cap (%.2f)" % g.resist_for_energy(full * 0.5), is_equal_approx(g.resist_for_energy(full * 0.5), cap * 0.5))
	_check("a quarter gives a quarter of the cap", is_equal_approx(g.resist_for_energy(full * 0.25), cap * 0.25))
	_check("full energy gives the cap", is_equal_approx(g.resist_for_energy(full), cap))
	_check("more energy than that never exceeds the cap", is_equal_approx(g.resist_for_energy(full * 50.0), cap))

	# 4) Wiring through the real recalculation: fed Guards count, kinds are independent, Guards of one kind add up.
	var m = _mech_with([_guard("Stun", R.RARE, full * 0.5), _guard("Stun", R.RARE, full * 0.25), _guard("Freeze", R.RARE, full * 0.5)])
	_check("two fed Stun Guards add: 0.45 + 0.225 resistance -> 32.5%% passes (got %.4f)" % m.status_duration_mult.get("concussed", 1.0), is_equal_approx(m.status_duration_mult.get("concussed", 1.0), 1.0 - (cap * 0.5 + cap * 0.25)))
	_check("one half-fed Freeze Guard -> 55% passes", is_equal_approx(m.status_duration_mult.get("frozen", 1.0), 1.0 - cap * 0.5))
	_check("no Shock Guard -> paralyzed untouched", not m.status_duration_mult.has("paralyzed"))
	m.apply_status("concussed", 1.0)
	m.apply_status("paralyzed", 1.0)
	m.apply_status("frozen", 2.0)
	_check("apply_status shortens concussed", is_equal_approx(m.status_effects.get("concussed", -1.0), 1.0 - (cap * 0.75)))
	_check("apply_status leaves paralyzed at a full 1.0 s", is_equal_approx(m.status_effects.get("paralyzed", -1.0), 1.0))
	_check("apply_status shortens frozen 2.0 s to 1.1 s", is_equal_approx(m.status_effects.get("frozen", -1.0), 2.0 * (1.0 - cap * 0.5)))

	# 5) An unfed Guard does nothing; offline / fried Guards give nothing.
	var unfed = _mech_with([_guard("Shock", R.MYTHIC, 0.0)])
	_check("an unfed Guard gives no protection (it just costs a cell)", is_equal_approx(unfed.status_duration_mult.get("paralyzed", 1.0), 1.0))
	var a = _guard("Shock", R.MYTHIC, full)
	var b = _guard("Shock", R.MYTHIC, full)
	var m2 = _mech_with([a, b])
	_check("two fully fed Guards hit the cap, not beyond (passes %.2f)" % m2.status_duration_mult.get("paralyzed", 1.0), is_equal_approx(m2.status_duration_mult.get("paralyzed", 1.0), 1.0 - cap))
	var c = _guard("Shock", R.MYTHIC, full)
	c.is_disabled = true
	var m3 = _mech_with([c])
	_check("a knocked-out Guard protects nothing", not m3.status_duration_mult.has("paralyzed") or is_equal_approx(m3.status_duration_mult["paralyzed"], 1.0))
	var d = _guard("Shock", R.MYTHIC, full)
	d.power_lost = true
	var m4 = _mech_with([d])
	_check("a fried Guard protects nothing", not m4.status_duration_mult.has("paralyzed") or is_equal_approx(m4.status_duration_mult["paralyzed"], 1.0))

	# 6) Shrug-off and the unprotected case.
	m2.apply_status("paralyzed", 0.2)
	_check("a short shock is shrugged off entirely at the cap (0.2 s x 10%% < 0.03 s)", not m2.status_effects.has("paralyzed"))
	m2.apply_status("paralyzed", 3.0)
	_check("a full 3 s shock still lands, at 0.3 s", is_equal_approx(m2.status_effects.get("paralyzed", -1.0), 0.3))
	var bare = _mech_with([])
	bare.apply_status("frozen", 3.0)
	_check("without Guards durations are unchanged", is_equal_approx(bare.status_effects.get("frozen", -1.0), 3.0))

	# 7) Saves.
	for kind in ["Stun", "Shock", "Freeze"]:
		_check("%s Guard script is on the save allow-list" % kind, SaveManager.is_allowed_tile_script("res://scripts/tiles/%sGuardTile.gd" % kind))
	var src = _guard("Shock", R.MYTHIC)
	var back = SaveManager._deserialize_tile(SaveManager._serialize_tile(src))
	_check("a mythic Shock Guard survives a save round trip", back != null and back.tile_type == "Shock Guard" and back.rarity == R.MYTHIC and back.resisted_status == "paralyzed")

	# 8) Rust grid sim: describe the Guards as store sinks, and Structural Strut as pass-through.
	if RustGridSimScript.is_available():
		for kind in ["Stun", "Shock", "Freeze"]:
			var t = _guard(kind, R.RARE)
			t.grid_position = HexCoord.new(0, 0)
			var desc = RustGridSimScript._describe_tile(t)
			_check("Rust sim describes the %s Guard as a store sink with the Heal Beacon's intake" % kind, not desc.is_empty() and desc["kind"] == RustGridSimScript.KIND_STORE_SINK and is_equal_approx(desc["store_coef"], 2.0))
		var strut = load("res://scripts/tiles/StructuralStrutTile.gd").new()
		strut.grid_position = HexCoord.new(0, 0)
		var sd = RustGridSimScript._describe_tile(strut)
		_check("Rust sim now describes a Structural Strut as pass-through", not sd.is_empty() and sd["kind"] == RustGridSimScript.KIND_PASS)
	else:
		print("SKIP: Rust grid sim not available in this run")
	# 6) Remediation Matrix: Mythic catch-all, 6x the energy per fraction, lower cap, one fed cell covers every status.
	var mx = load("res://scripts/tiles/RemediationMatrixTile.gd").new()
	mx.rarity = R.MYTHIC
	var mfull: float = TileStatsRegistry.get_stat("RemediationMatrixTile", "energy_for_max", 9000.0)
	var mcap: float = TileStatsRegistry.get_stat("RemediationMatrixTile", "max_resist", 0.7)
	_check("Matrix needs 6x a single Guard's energy for full protection", is_equal_approx(mfull, 6.0 * full))
	_check("Matrix cap is lower than a Guard's (less focused)", mcap < cap)
	_check("Matrix covers frozen, paralyzed, concussed, burning, poisoned, vortexed", mx.get_resisted_statuses().size() == 6 and "burning" in mx.get_resisted_statuses())
	_check("same energy gives a Matrix 1/6 the resistance of a Guard", is_equal_approx(mx.resist_for_energy(full * 0.5) / (cap * 0.5), mcap / cap / 6.0))
	mx.stored_energy = mfull * 0.5
	var mm = _mech_with([mx])
	_check("one fed Matrix shortens frozen (got %.3f)" % mm.status_duration_mult.get("frozen", 1.0), is_equal_approx(mm.status_duration_mult.get("frozen", 1.0), 1.0 - mcap * 0.5))
	_check("...and burning", is_equal_approx(mm.status_duration_mult.get("burning", 1.0), 1.0 - mcap * 0.5))
	_check("...and paralyzed", is_equal_approx(mm.status_duration_mult.get("paralyzed", 1.0), 1.0 - mcap * 0.5))
	if RustGridSimScript.is_available():
		var md = RustGridSimScript._describe_tile(load("res://scripts/tiles/RemediationMatrixTile.gd").new())
		_check("Rust sim treats the Matrix as a store sink", md.get("kind", -1) == RustGridSimScript.KIND_STORE_SINK)

	print("StatusResistCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
