extends Node

# Covers the two jammer-wiring paths JammerWiringCheck.gd didn't: BossBrain's
# jam_burst spawning a stationary field, and SquadDirector.broadcast_jammer_alert
# actually reaching a squad member's last_known_player_pos. Safe to delete
# once validated.

const MechScript = preload("res://scripts/entities/Mech.gd")
const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")
const SquadScript = preload("res://scripts/ai/Squad.gd")
const SquadTemplateScript = preload("res://scripts/ai/SquadTemplate.gd")

var world: Node2D

func _ready():
	world = Node2D.new()
	add_child(world)

	# --- Boss jam_burst ---
	var boss = MechScript.new()
	boss.is_player = false
	boss.is_boss = true
	boss.combat_role = "jammer"
	world.add_child(boss)

	var player = MechScript.new()
	player.is_player = true
	player.global_position = Vector2(50, 0)
	world.add_child(player)
	boss.target = player

	if not boss.boss_brain:
		boss.boss_brain = boss.BossBrain.new(boss)
	boss.boss_brain._do_jam_burst()

	var fields = get_tree().get_nodes_in_group("jammer_field")
	print("Fields after jam_burst: ", fields.size())
	if fields.size() > 0:
		var f = fields[0]
		print("  owner_is_player: ", f.owner_is_player, " lifetime: ", f.lifetime, " base_radius: ", f.base_radius)

	# --- SquadDirector broadcast ---
	var director = SquadDirectorScript.new()
	world.add_child(director)

	var template = SquadTemplateScript.new("TestSquad", {"brawler": 1})
	var squad = SquadScript.new()
	squad.setup(template)
	var member = MechScript.new()
	member.is_player = false
	member.combat_role = "brawler"
	member.has_sight_of_player = false
	world.add_child(member)
	squad.add_member(member)
	director.active_squads.append(squad)

	var alert_pos = Vector2(999, 111)
	director.broadcast_jammer_alert(alert_pos)
	print("member.last_known_player_pos after broadcast: ", member.last_known_player_pos, " (expect ", alert_pos, ")")

	# Member already in real combat shouldn't get overridden by a stale broadcast.
	member.has_sight_of_player = true
	member.last_known_player_pos = Vector2(1, 1)
	director.broadcast_jammer_alert(Vector2(-500, -500))
	print("member.last_known_player_pos when has_sight_of_player=true: ", member.last_known_player_pos, " (expect (1, 1), unchanged)")

	get_tree().quit()
