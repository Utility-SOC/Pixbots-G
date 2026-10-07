extends Node

# MYTHIC heal beacon "Field Repair": only mythic beacons qualify; charge banks energy over time; each pulse spends
# 3 repair points in priority order (revive a limb, fried tiles, tile HP, limb integrity); nothing-to-fix keeps the
# charge banked instead of wasting it; consecutive pulses respect the cooldown; enemies (non-player) never repair.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const SystemScript = preload("res://scripts/entities/HealBeaconSystem.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _tiles(comp) -> Array:
	return comp.hex_grid.get_all_tiles()

func _ready():
	var b = load("res://scripts/tiles/HealBeaconTile.gd").new()
	b.rarity = HexTile.Rarity.LEGENDARY
	_check("a legendary beacon is not a field-repair beacon", not b.is_field_repair())
	b.rarity = HexTile.Rarity.MYTHIC
	_check("a mythic beacon is", b.is_field_repair())

	var cost: float = TileStatsRegistry.get_stat("HealBeaconTile", "repair_pulse_cost", 240000.0)
	var cooldown: float = TileStatsRegistry.get_stat("HealBeaconTile", "repair_min_interval", 8.0)
	_check("the energy cost is a huge number (%.0f)" % cost, cost >= 10000.0)

	var mech = MechScript.new()
	mech.is_player = true
	mech.has_healer = true
	mech.has_field_repair = true
	mech.repair_energy_flow = cost / 2.0 # one pulse's worth every 2 seconds of feeding
	var leg = ComponentEquipmentScript.new(HexTile.BodySlot.LEG_L, HexTile.Rarity.COMMON)
	leg.is_broken = true
	leg.max_integrity = 100.0
	leg.integrity = 0.0
	mech.components[HexTile.BodySlot.LEG_L] = leg
	var arm = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.COMMON)
	var coords = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(0, 1), HexCoord.new(-1, 1)]
	for i in range(coords.size()):
		var t = load("res://scripts/tiles/WeaponMountTile.gd").new()
		arm.hex_grid.add_tile(coords[i], t)
	var tl = _tiles(arm)
	tl[0].power_lost = true
	tl[0].is_disabled = true
	tl[1].power_lost = true
	tl[1].is_disabled = true
	tl[2].hp = tl[2].max_hp * 0.2
	mech.components[HexTile.BodySlot.ARM_L] = arm
	var arm_r = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_R, HexTile.Rarity.COMMON)
	arm_r.max_integrity = 100.0
	arm_r.integrity = 40.0
	mech.components[HexTile.BodySlot.ARM_R] = arm_r

	var sys = SystemScript.new(mech)
	sys._tick_field_repair(1.0)
	_check("one second of feeding is not enough (charge %.0f of %.0f)" % [mech.repair_charge, cost], leg.is_broken)
	sys._tick_field_repair(1.0)
	_check("pulse 1: the destroyed limb is revived (3 points)", not leg.is_broken)
	_check("pulse 1: revived at half integrity", is_equal_approx(leg.integrity, 50.0))
	_check("pulse 1: fried tiles still fried (no points left)", tl[0].power_lost and tl[1].power_lost)
	_check("pulse 1: spent the energy (charge %.0f)" % mech.repair_charge, mech.repair_charge < cost * 0.01)
	_check("pulse 1: the mech is flagged to rebuild its grid", mech.is_grid_dirty)

	# Cooldown: feed again immediately; no second pulse until the cooldown has passed.
	sys._tick_field_repair(3.0)
	_check("pulse 2 waits for the cooldown", tl[0].power_lost)
	var waited := 3.0
	while waited < cooldown + 1.0:
		sys._tick_field_repair(1.0)
		waited += 1.0
	_check("pulse 2: both fried tiles restored", not tl[0].power_lost and not tl[1].power_lost)
	_check("pulse 2: restored tiles are back at full HP and online", tl[0].hp == tl[0].max_hp and not tl[0].is_disabled)
	_check("pulse 2: the last point topped up the damaged tile's HP", tl[2].hp == tl[2].max_hp)
	_check("pulse 2: limb integrity not yet topped up (points ran out)", is_equal_approx(arm_r.integrity, 40.0))

	for k in range(int(cooldown) + 3):
		sys._tick_field_repair(1.0)
	_check("pulse 3: hurt limb integrity topped up", is_equal_approx(arm_r.integrity, 100.0))
	_check("pulse 3 left the revived limb's integrity alone or healed it (never broken)", not leg.is_broken)

	# Nothing left to fix: the charge banks (capped at one pulse) instead of being spent.
	for k in range(int(cooldown) + 6):
		sys._tick_field_repair(1.0)
	_check("nothing to repair: charge stays banked at one full pulse (%.0f)" % mech.repair_charge, is_equal_approx(mech.repair_charge, cost))
	tl[3].power_lost = true
	tl[3].is_disabled = true
	sys._tick_field_repair(1.0)
	_check("a new fried tile is repaired the moment it happens (banked charge)", not tl[3].power_lost)

	# Enemies never get the repair, even with a mythic beacon.
	var foe = MechScript.new()
	foe.is_player = false
	foe.has_healer = true
	foe.has_field_repair = true
	foe.repair_energy_flow = cost
	var foe_leg = ComponentEquipmentScript.new(HexTile.BodySlot.LEG_L, HexTile.Rarity.COMMON)
	foe_leg.is_broken = true
	foe.components[HexTile.BodySlot.LEG_L] = foe_leg
	var foe_sys = SystemScript.new(foe)
	for k in range(5):
		foe_sys.tick(1.0)
	_check("an enemy's mythic beacon repairs nothing", foe_leg.is_broken and foe.repair_charge == 0.0)
	# Wiring through the real grid recalculation: a beacon's rarity decides has_field_repair, and the beacon's
	# banked energy becomes repair_energy_flow.
	for rarity in [HexTile.Rarity.LEGENDARY, HexTile.Rarity.MYTHIC]:
		var m = MechScript.new()
		m.is_player = true
		var pack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.COMMON)
		var beacon = load("res://scripts/tiles/HealBeaconTile.gd").new()
		beacon.rarity = rarity
		beacon.stored_energy = 5000.0
		pack.hex_grid.add_tile(HexCoord.new(0, 0), beacon)
		m.components[HexTile.BodySlot.BACKPACK] = pack
		m.components[HexTile.BodySlot.TORSO] = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON) # recalculation needs a torso
		m._recalculate_grid()
		var is_mythic: bool = rarity == HexTile.Rarity.MYTHIC
		_check("recalculation: rarity %d beacon -> has_healer" % rarity, m.has_healer)
		_check("recalculation: rarity %d -> has_field_repair == %s" % [rarity, is_mythic], m.has_field_repair == is_mythic)
		_check("recalculation: rarity %d -> repair_energy_flow %s (%.0f)" % [rarity, "5000" if is_mythic else "0", m.repair_energy_flow], is_equal_approx(m.repair_energy_flow, 5000.0 if is_mythic else 0.0))
	print("HealBeaconFieldRepairCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
