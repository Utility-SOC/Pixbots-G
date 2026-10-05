extends Node

# Every part that can exist must be wired and routable (see ComponentViability). Regression for:
# dropped torsos had no Accessory Return, missing hub hexes and non-routable limb links.

const ViabilityScript = preload("res://scripts/core/ComponentViability.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures := 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _snapshot(comp) -> String:
	var parts = []
	for t in comp.hex_grid.get_all_tiles():
		parts.append("%s@%d,%d" % [t.tile_type, t.grid_position.q, t.grid_position.r])
	parts.sort()
	return ",".join(parts)

func _ready():
	var mech = Node.new()
	# --- 1. every dropped part, any slot/rarity, is viable ------------------------------------
	var broken = 0
	var torsos = 0
	for n in range(500):
		var pack = LootManager._create_procedural_component(randi() % 5, mech, "Boss")
		if pack.slot_type == HexTile.BodySlot.TORSO:
			torsos += 1
		if not ViabilityScript.problems(pack).is_empty():
			broken += 1
	_check("500 dropped parts (%d torsos): none non-viable (%d broken)" % [torsos, broken], broken == 0 and torsos > 40)

	# --- 2. the player's own starter parts (all rarities) are viable too ------------------
	# (Enemy-role starter torsos keep their legacy placement on purpose: stock builds replay by
	# coordinate, and the solver routes around it - only parts the player can hold must be perfect.)
	var starter_bad = 0
	for role in [""]:
		for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]:
			var parts = [ComponentEquipmentScript.create_starter_torso(role, rarity), ComponentEquipmentScript.create_starter_arm(true, role, rarity),
				ComponentEquipmentScript.create_starter_arm(false, role, rarity), ComponentEquipmentScript.create_starter_leg(true, role, rarity),
				ComponentEquipmentScript.create_starter_leg(false, role, rarity), ComponentEquipmentScript.create_starter_head(role, rarity),
				ComponentEquipmentScript.create_starter_backpack(role, rarity)]
			for p in parts:
				if not ViabilityScript.problems(p).is_empty():
					starter_bad += 1
					print("  starter problem: slot %d role '%s' rarity %d: %s" % [p.slot_type, role, rarity, str(ViabilityScript.problems(p))])
	_check("all starter parts viable (%d bad)" % starter_bad, starter_bad == 0)

	# --- 2b. every enemy-role starter torso (all roles x rarities) is viable, with no tile moved -------
	var roles = ["sniper", "brawler", "scout", "diver", "ambusher", "flamethrower", "jammer", "support", "commander", "anti_missile", "remediation"]
	var enemy_bad = 0
	for role in roles:
		for rarity in range(5):
			var et = ComponentEquipmentScript.create_starter_torso(role, rarity)
			if not ViabilityScript.problems(et).is_empty():
				enemy_bad += 1
				print("  enemy torso problem: %s r%d: %s" % [role, rarity, str(ViabilityScript.problems(et))])
	_check("all %d enemy-role starter torsos are viable (%d bad)" % [roles.size() * 5, enemy_bad], enemy_bad == 0)
	# a tiny footprint with the return beside a sink is fine; a genuinely isolated return is still caught
	_check("a Common sniper's return (beside a mount, tiny footprint) counts as usable", ViabilityScript.problems(ComponentEquipmentScript.create_starter_torso("sniper", 0)).is_empty())
	var iso = ComponentEquipmentScript.create_starter_torso("", HexTile.Rarity.RARE)
	var ret_i = ViabilityScript._first_of_type(iso, "Accessory Return")
	for d in range(6):
		var nb = ret_i.grid_position.neighbor(d)
		iso._valid_hex_set.erase(iso._hex_key(nb.q, nb.r))
	var iso_problems = ViabilityScript.problems(iso)
	var flagged = false
	for pr in iso_problems:
		if "cannot deliver" in pr:
			flagged = true
	_check("a return with nowhere to deliver is still flagged", flagged)

	# --- 3. repair is idempotent: a viable part is never touched ----------------------------
	var t = ComponentEquipmentScript.create_starter_torso("brawler", HexTile.Rarity.RARE)
	var before = _snapshot(t)
	ViabilityScript.ensure(t)
	_check("ensure() leaves an already-viable torso unchanged", before == _snapshot(t))

	# --- 4. repair fixes deliberately broken parts ------------------------------------------------
	var broken_t = ComponentEquipmentScript.create_starter_torso("", HexTile.Rarity.UNCOMMON)
	var ret = ViabilityScript._first_of_type(broken_t, "Accessory Return")
	broken_t.hex_grid.remove_tile(ret.grid_position)
	var arm_link = ViabilityScript._link_for(broken_t, HexTile.BodySlot.ARM_L)
	broken_t._valid_hex_set.erase(broken_t._hex_key(arm_link.grid_position.q - 1, arm_link.grid_position.r))
	var pre = ViabilityScript.problems(broken_t)
	var left = ViabilityScript.ensure(broken_t)
	_check("a torso missing its return (%d problems) is fully repaired (%d left)" % [pre.size(), left.size()], pre.size() > 0 and left.is_empty())

	var no_hub = ComponentEquipmentScript.create_starter_torso("", HexTile.Rarity.COMMON)
	for d in range(6):
		var n = HexCoord.new(0, 0).neighbor(d)
		for i in range(no_hub.valid_hexes.size() - 1, -1, -1):
			if no_hub.valid_hexes[i].q == n.q and no_hub.valid_hexes[i].r == n.r:
				no_hub.valid_hexes.remove_at(i)
		no_hub._valid_hex_set.erase(no_hub._hex_key(n.q, n.r))
	for slot in ViabilityScript.SPOKES:
		var l = ViabilityScript._link_for(no_hub, slot)
		if l:
			no_hub.hex_grid.remove_tile(l.grid_position)
	no_hub.fixed_sinks.clear()
	no_hub.fixed_sinks.append(HexCoord.new(0, 0))
	var left2 = ViabilityScript.ensure(no_hub)
	_check("a torso with no hub and no links is rebuilt (%d problems left)" % left2.size(), left2.is_empty())

	# --- 5. a repaired drop torso is usable by AutoEquip --------------------------------------------
	var drop = null
	while drop == null or drop.slot_type != HexTile.BodySlot.TORSO:
		drop = LootManager._create_procedural_component(HexTile.Rarity.RARE, mech, "Boss")
	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()
	var inv: Array = []
	for i in range(40):
		var c = load("res://scripts/tiles/DirectionalConduitTile.gd").new()
		c.rarity = HexTile.Rarity.RARE
		inv.append(c)
	for i in range(6):
		var sp = load("res://scripts/tiles/SplitterTile.gd").new()
		sp.rarity = HexTile.Rarity.RARE
		inv.append(sp)
	add_child(drop)
	solver.solve(drop, inv)
	var used = drop.hex_grid.get_all_tiles().size()
	_check("AutoEquip builds on a dropped torso (%d tiles placed, was ~7)" % used, used > 9)
	_check("the solved drop torso is still structurally viable", ViabilityScript.problems(drop).is_empty())

	if failures == 0:
		print("PASS: every part is wired and routable; repair is idempotent and fixes broken parts")
	get_tree().quit(0 if failures == 0 else 1)
