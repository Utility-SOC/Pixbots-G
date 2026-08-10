extends Node

# Regression check for giving enemies missile access (user request
# 2026-08-10: "I want enemies to get access to missiles"). Confirmed via
# direct code read before this change: no role in Mech.build_loadout_for_
# role's `match role_name:` block ever fed the solver a MissileRackTile -
# enemies had zero access to missiles at all.
#
# First attempt fed a MissileRackTile into build_loadout_for_role's generic
# inventory list (same mechanism Amplifier/Catalyst/Splitter/Conduit use) -
# empirically this NEVER got placed, at any rarity. Root cause: Auto
# EquipSolver._solve_impl only ever routes energy TO fixed_sinks that
# already exist on the starter shape (see its own "Skip (non-Core) targets
# - they're fixed sinks, not tiles this solver places" comment) - it never
# creates a brand-new terminal sink for an OUTPUT-category inventory tile.
# This turned out to be true of the pre-existing commander ShieldTile/
# AccumulatorTile role-tile entries too (out of scope to fix here, but
# worth knowing this check's negative control below isn't unique to
# Missile Rack). The real fix lives in ComponentEquipment.
# create_starter_torso: sniper/commander now get a self-powered Missile
# Rack fixed sink with its own dedicated Microcore, the exact same pattern
# the existing self-powered "ai_mount" torso Weapon Mount already uses.
#
# Because placement is now a deterministic fixed-sink construction (not
# solver-dependent), this checks a single spawn per role rather than
# looping for a probabilistic hit.
#
# SAFETY: no SquadDirector (real or fake) is ever added to the tree, so
# Mech._get_stock_build_evolution() resolves to null and build_loadout_for_
# role always takes the fresh-solve path - see that function's own null
# check. Never touches user:// at all.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _mech_has_missile_rack(mech) -> bool:
	for comp in mech.components.values():
		if not comp or not comp.hex_grid:
			continue
		for coord in comp.hex_grid.grid.keys():
			var tile = comp.hex_grid.grid[coord]
			if tile.tile_type == "Missile Rack":
				return true
	return false

func _spawn_bot(role: String) -> Node:
	var bot = MechScript.new()
	bot.is_player = false
	bot.combat_role = role
	world.add_child(bot)
	return bot

func _ready():
	world = Node.new()
	add_child(world)

	for role in ["sniper", "commander"]:
		var bot = _spawn_bot(role)
		_check("role '%s' gets a self-powered Missile Rack on its torso" % role,
			_mech_has_missile_rack(bot))
		bot.queue_free()

	# Negative control: a role never granted missile access must never get
	# one, deterministically (it's not a probabilistic placement anymore).
	var brawler = _spawn_bot("brawler")
	_check("role 'brawler' (no missile access granted) never gets a Missile Rack",
		not _mech_has_missile_rack(brawler))
	brawler.queue_free()

	# The player build path passes role="" into create_starter_torso
	# (Mech._ready(): `combat_role if not is_player else ""`) - confirm the
	# sniper/commander-gated block can't leak onto a player build via some
	# other role string collision.
	var empty_role_torso = load("res://scripts/core/ComponentEquipment.gd").create_starter_torso("", HexTile.Rarity.COMMON)
	var empty_has_missiles = false
	for coord in empty_role_torso.hex_grid.grid.keys():
		if empty_role_torso.hex_grid.grid[coord].tile_type == "Missile Rack":
			empty_has_missiles = true
	_check("a player-style empty-role torso (role='') never gets a Missile Rack",
		not empty_has_missiles)

	if failures == 0:
		print("PASS: sniper and commander enemies get a self-powered Missile Rack; roles/builds without missile access never do")
	get_tree().quit(0 if failures == 0 else 1)
