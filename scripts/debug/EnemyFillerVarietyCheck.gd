extends Node

# Regression check for enemy grid filler variety (user request 2026-08-10:
# "the enemy bots need to be able to use splitter/amplifier loops and have
# lots of elemental infusers ... They should try to use less than 20%
# directional conduit").
#
# Root cause (confirmed empirically before this fix, at every rarity
# tested): AutoEquipSolver only ever synthesizes a fresh Directional
# Conduit as a LAST RESORT once its `inventory` argument genuinely runs
# dry (see AutoEquipSolver.gd's FILLER_TILE_PRIORITY / _straight_tile_
# priority - Amplifier/Catalyst/Elemental Infuser/Splitter are ALL already
# prioritized ahead of Directional Conduit for every cell type it can fill).
# The previous role-tile inventory Mech.build_loadout_for_role fed it was
# far too small (a handful of tiles) against real grid sizes (a Mythic
# Torso alone has 70+ open cells), so almost every open cell fell through
# to synthesized wire. The fix scales a real Amplifier/Splitter/Elemental
# Infuser pool to the bot's actual open-hex budget instead.
#
# Verifies, across COMMON and MYTHIC rarity and three different roles:
#   1. Directional Conduit share of the final grid stays under 20%.
#   2. Elemental Infuser and Amplifier both appear in real quantity (not
#      just theoretically available - actually placed on the grid).
#
# SAFETY: no SquadDirector (real or fake) is ever added to the tree - see
# EnemyMissileAccessCheck.gd's matching comment for why that's safe here
# too (Mech._get_stock_build_evolution() resolves to null, fresh-solve
# path only, never touches user://).

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _tile_counts(mech) -> Dictionary:
	var counts = {}
	for comp in mech.components.values():
		if not comp or not comp.hex_grid:
			continue
		for coord in comp.hex_grid.grid.keys():
			var t = comp.hex_grid.grid[coord].tile_type
			counts[t] = counts.get(t, 0) + 1
	return counts

func _ready():
	world = Node.new()
	add_child(world)

	for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.MYTHIC]:
		for role in ["sniper", "commander", "brawler"]:
			var bot = MechScript.new()
			bot.is_player = false
			bot.combat_role = role
			bot.base_rarity = rarity
			bot.spawn_template_name = "TestSquad" # required gate - see build_loadout_for_role's filler-pool comment
			world.add_child(bot)

			var counts = _tile_counts(bot)
			var total = 0
			for k in counts:
				total += counts[k]
			var dc_share = float(counts.get("Directional Conduit", 0)) / float(max(1, total))

			_check("%s rarity=%d: Directional Conduit stays under 20%% of the grid (got %.1f%%)" % [role, rarity, dc_share * 100.0],
				dc_share < 0.20)
			_check("%s rarity=%d: real Amplifier tiles got placed" % [role, rarity],
				counts.get("Amplifier", 0) > 0)

			bot.queue_free()

	# Elemental Infuser specifically needs a spawn_profile to get prioritized
	# ahead of Amplifier on straight paths (see AutoEquipSolver._straight_
	# tile_priority) - real squad spawns always have one (SquadDirector.
	# _spawn_bot_for_role sets it unconditionally), so verify that path too.
	var SolverProfileScript = load("res://scripts/ai/SolverProfile.gd")
	var profiled_bot = MechScript.new()
	profiled_bot.is_player = false
	profiled_bot.combat_role = "brawler"
	profiled_bot.base_rarity = HexTile.Rarity.MYTHIC
	profiled_bot.spawn_template_name = "TestSquad"
	profiled_bot.spawn_profile = SolverProfileScript.new("Reactive", EnergyPacket.SynergyType.FIRE)
	world.add_child(profiled_bot)
	var profiled_counts = _tile_counts(profiled_bot)
	_check("a bot with a real spawn_profile gets lots of Elemental Infusers placed",
		profiled_counts.get("Elemental Infuser", 0) > 10)
	profiled_bot.queue_free()

	if failures == 0:
		print("PASS: enemy grids stay under 20% Directional Conduit and get real Amplifier/Elemental Infuser variety instead")
	get_tree().quit(0 if failures == 0 else 1)
