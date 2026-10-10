extends Node

# Diagnostic: how strong are generated ENEMY builds, and how many saturate the sim? Spawns N bots per role at a
# rarity through the real build_loadout_for_role path and reports delivered mount energy (per mount, clamped at the
# normal per-packet cap) plus saturation counts. Use to A/B solver changes on enemy power.
#   godot --headless --path . res://scripts/debug/EnemyBuildImpactDiag.tscn
const MechScript = preload("res://scripts/entities/Mech.gd")
const SEED = 20261009
const ROLES = ["brawler", "sniper", "support", "scout", "commander", "ambusher"]

func _ready():
	var N = 6
	for rarity in [HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY]:
		var tot = 0.0
		var sat = 0
		var over = 0
		var bots = 0
		var zero = 0
		for role in ROLES:
			for i in range(N):
				AutoEquipSolver._topology_cache.clear()
				SimRng.seed_all(SEED + i * 7919 + role.hash() % 1000)
				var bot = MechScript.new()
				bot.is_player = false
				bot.combat_role = role
				bot.base_rarity = rarity
				add_child(bot)
				bot._recalculate_grid()
				var per_mount: Dictionary = {}
				for w in bot.precalculated_weapons:
					var id = w["mount"].get_instance_id()
					per_mount[id] = float(per_mount.get(id, 0.0)) + w["packet"].magnitude
				var b = 0.0
				for id in per_mount:
					b += minf(per_mount[id], EnergyPacket.NORMAL_MAGNITUDE_CAP)
				tot += b
				if per_mount.is_empty(): zero += 1
				var s = false
				for c in bot.components.values():
					if c and c.hex_grid:
						if c.hex_grid.sim_saturated: s = true
						over += c.hex_grid.flow_overload.size()
				if s: sat += 1
				bots += 1
				bot.queue_free()
		print("IMPACT rarity=%d bots=%d mean_delivered=%.0f saturated_bots=%d overload_tiles=%d no_weapon_bots=%d" % [rarity, bots, tot / bots, sat, over, zero])
	SimRng.unseed()
	get_tree().quit()
