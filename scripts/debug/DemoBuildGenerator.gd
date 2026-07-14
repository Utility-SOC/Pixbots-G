extends Node

# DEV TOOL - regenerates config/demo_builds/*.json, the ready-built starter
# pixbots new players can equip from the Garage's Blueprints popup (design
# ruling: "make several demonstration pixbot builds so new players can
# start with readybuilt pixelbots"). Each build is produced by the SAME
# AutoEquipSolver pipeline enemy loadouts use (build_loadout_for_role with
# a themed SolverProfile), so every demo is guaranteed wired-and-firing
# rather than hand-authored and drift-prone. Run headless whenever the
# solver/tile set changes enough to warrant refreshed demos:
#   godot --headless res://scripts/debug/DemoBuildGenerator.tscn

const MechScript = preload("res://scripts/entities/Mech.gd")
const SolverProfileScript = preload("res://scripts/ai/SolverProfile.gd")

# [file slug, display name, role, favored synergy, base rarity]
var demos = [
	["gunner", "Gunner (steady RAW gatling)", "brawler", EnergyPacket.SynergyType.RAW, HexTile.Rarity.UNCOMMON],
	["ranger", "Ranger (long-range kinetic)", "sniper", EnergyPacket.SynergyType.KINETIC, HexTile.Rarity.UNCOMMON],
	["pyro", "Pyro (close-range fire)", "flamethrower", EnergyPacket.SynergyType.FIRE, HexTile.Rarity.UNCOMMON],
	["warden", "Warden (support + heal beacon)", "support", EnergyPacket.SynergyType.ICE, HexTile.Rarity.UNCOMMON],
	["assassin", "Assassin (cloaked pierce ambusher)", "ambusher", EnergyPacket.SynergyType.PIERCE, HexTile.Rarity.UNCOMMON],
]

func _ready():
	DirAccess.make_dir_recursive_absolute("res://config/demo_builds")
	var world = Node2D.new()
	add_child(world)

	for d in demos:
		var mech = MechScript.new()
		mech.is_player = false
		mech.base_rarity = d[4]
		mech.combat_role = d[2]
		mech.spawn_profile = SolverProfileScript.new("Demo " + str(d[1]), d[3])
		world.add_child(mech) # _ready equips default components
		mech.build_loadout_for_role(d[2])
		mech._recalculate_grid()

		var data = {
			"version": SaveManager.SAVE_FORMAT_VERSION,
			"demo_name": d[1],
			"components": {},
		}
		for slot in mech.components.keys():
			data["components"][str(slot)] = SaveManager._serialize_component(mech.components[slot])

		var f = FileAccess.open("res://config/demo_builds/%s.json" % d[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("demo build written: %s (%d weapons armed)" % [d[0], mech.precalculated_weapons.size()])
		mech.queue_free()

	print("PASS: demo builds regenerated")
	get_tree().quit()
