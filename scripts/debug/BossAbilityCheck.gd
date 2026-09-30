extends Node

const MechScript = preload("res://scripts/entities/Mech.gd")
const BrainScript = preload("res://scripts/entities/BossBrain.gd")
const ProfileScript = preload("res://scripts/ai/BossProfile.gd")

class FakePlayer extends Node2D:
	var hp_lost: float = 0.0
	var external_force: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var hp: float = 1000.0
	var max_hp: float = 1000.0
	func apply_damage(amount, _element = "RAW", _src = null, _refl = false, _lbl = ""):
		hp_lost += amount

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _setup(ability: String):
	var world = Node2D.new()
	add_child(world)
	var player = FakePlayer.new()
	player.add_to_group("player")
	world.add_child(player)
	player.global_position = Vector2(400, 0)
	var boss = MechScript.new()
	boss.is_player = false
	boss.is_boss = true
	world.add_child(boss)
	boss.set_physics_process(false)
	boss.max_hp = 1000.0
	boss.hp = 1000.0
	boss.global_position = Vector2.ZERO
	boss.target = player
	var bp = ProfileScript.new("T", "brawler")
	bp.ability_pool = [ability]
	boss.boss_profile = bp
	var brain = BrainScript.new(boss)
	return {"world": world, "player": player, "boss": boss, "brain": brain}

func _resolve(brain) -> void:
	var guard = 0
	while brain.boss_ability_state != "" and guard < 200:
		brain.continue_ability(0.1)
		guard += 1

func _ready():
	# Profile data and sanitizer
	var bp = ProfileScript.new("X".repeat(200), "brawler")
	bp.ability_pool = ["shockwave", "evil", "meteor_rain", "charge", "railgun", "rally"]
	bp.enrage_style = "rm -rf"
	bp.position_style = "nope"
	bp.hp_mult = 1e9
	_check("sanitize accepts partial pool", bp.sanitize())
	_check("sanitize filters ids and caps pool (%s)" % str(bp.ability_pool), bp.ability_pool == ["shockwave", "meteor_rain", "charge"])
	_check("sanitize resets styles and clamps hp", bp.enrage_style == "berserker" and bp.position_style == "aggressive" and bp.hp_mult <= 4.0 and bp.profile_name.length() <= 60)
	var bad = ProfileScript.new("Y", "hacker")
	bad.ability_pool = ["shockwave"]
	_check("sanitize rejects unknown role", not bad.sanitize())
	var empty = ProfileScript.new("Z", "brawler")
	empty.ability_pool = ["evil"]
	_check("sanitize rejects no valid abilities", not empty.sanitize())

	# Charge: lunges along the lane and hurts a player standing in it
	var c = _setup("charge")
	c.brain._start_ability()
	_check("charge enters windup", c.brain.boss_ability_state == "charge")
	_resolve(c.brain)
	_check("charge hurt the player in the lane", c.player.hp_lost > 0.0)
	await get_tree().create_timer(0.4).timeout
	_check("charge moved the boss forward (%.0f)" % c.boss.global_position.x, c.boss.global_position.x > 300.0)
	c.world.free()

	# Charge misses a player off to the side
	var c2 = _setup("charge")
	c2.brain._start_ability()
	c2.player.global_position = Vector2(400, 0)
	c2.brain._boss_railgun_aim = Vector2(400, 0)
	c2.player.global_position = Vector2(300, 250)
	_resolve(c2.brain)
	_check("charge misses a player outside the lane", c2.player.hp_lost == 0.0)
	c2.world.free()

	# Triple rail: centre beam hits, but a player in a gap between beams is safe
	var t = _setup("triple_rail")
	t.brain._start_ability()
	_resolve(t.brain)
	_check("triple rail hits the locked centre line", t.player.hp_lost > 0.0)
	t.world.free()
	var t2 = _setup("triple_rail")
	t2.brain._start_ability()
	t2.player.global_position = Vector2(400, 400 * tan(0.19))
	_resolve(t2.brain)
	_check("triple rail leaves safe lanes between beams", t2.player.hp_lost == 0.0)
	t2.world.free()

	# Gravity well pulls the player in
	var g = _setup("gravity_well")
	g.brain._start_ability()
	_resolve(g.brain)
	await get_tree().create_timer(1.6).timeout
	_check("gravity well pulled the player toward the boss", g.player.external_force.x < -100.0)
	g.world.free()

	# Meteor rain punishes standing still
	var m = _setup("meteor_rain")
	m.brain._start_ability()
	await get_tree().create_timer(2.5).timeout
	_check("meteor rain damaged a stationary player (%.1f)" % m.player.hp_lost, m.player.hp_lost > 0.0)
	m.world.free()

	# Minefield: the centre of the ring is safe
	var f = _setup("minefield")
	f.brain._start_ability()
	await get_tree().create_timer(1.8).timeout
	_check("minefield centre is safe", f.player.hp_lost == 0.0)
	f.world.free()

	# Enrage styles
	var e = _setup("shockwave")
	e.boss.boss_profile.enrage_style = "relentless"
	e.brain.enrage_stage = 0
	var cd0 = e.brain.cooldown_scale
	e.brain._apply_enrage_style("relentless")
	_check("relentless shortens ability cooldowns", e.brain.cooldown_scale < cd0)
	e.brain._apply_enrage_style("phase_shift")
	_check("phase_shift queues the next ability soon", e.brain.boss_ability_cooldown <= 0.6)
	e.world.free()

	# New seeds are registered and every ability/style is known to the brain
	var seen = {}
	for a in ProfileScript.ALL_ABILITIES:
		seen[a] = true
	_check("11 abilities available", seen.size() == 11)
	print("boss ability check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
