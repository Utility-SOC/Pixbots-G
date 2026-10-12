extends Node

# Frank's Challenges end to end in the real Main scene: the catalog is well formed, the rule arithmetic does what the
# briefs say, a challenge spawns its scripted enemies with the rule applied, and clearing them wins (scrap, record, Frank).

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var ids := {}
	for c in FrankChallenges.CHALLENGES:
		ids[c["id"]] = true
		_check("%s is well formed" % c["id"], c.has_all(["title", "brief", "map", "wave", "enemies", "rule", "seconds", "reward"]) and MapTypes.has(c["map"]) and not c["enemies"].is_empty())
	_check("ids are unique", ids.size() == FrankChallenges.CHALLENGES.size())
	_check("find works", FrankChallenges.find("the_eye")["title"] == "The Eye" and FrankChallenges.find("nope").is_empty())
	_check("flat reduction flattens small hits and keeps big ones", FrankChallenges.filter_hit(10.0, 60.0, 0.0) == 0.2 and FrankChallenges.filter_hit(100.0, 60.0, 0.0) == 40.0)
	_check("The Eye shrugs off strong hits and favours gentle ones", FrankChallenges.filter_hit(200.0, 0.0, 100.0) == 20.0 and FrankChallenges.filter_hit(50.0, 0.0, 100.0) == 75.0)
	_check("no rule leaves damage alone", FrankChallenges.filter_hit(37.0, 0.0, 0.0) == 37.0)

	SaveManager.current_game_mode = "challenge"
	SaveManager.pending_challenge = "glass_parade"
	SaveManager.save_to_load = ""
	SaveManager.pending_run_card = {"map_type": "Poppy Fields", "layout": "auto", "seed": 5}
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	(func(): get_tree().current_scene = main).call_deferred()
	await get_tree().process_frame
	await get_tree().process_frame
	var waited = 0
	while (main.get("player") == null or not is_instance_valid(main.player)) and waited < 600:
		await get_tree().process_frame
		waited += 1
	await get_tree().create_timer(1.0).timeout
	var scrap0 = main.player_scrap
	main._start_wave()
	await get_tree().process_frame
	var r = main.get("_challenge_runner")
	_check("the runner starts", r != null and r.state == "running")
	_check("24 scripted enemies (%d)" % r.enemies.size(), r.enemies.size() == 24)
	main._start_wave()
	_check("starting again does not restart it", main._challenge_runner == r and r.enemies.size() == 24)
	for e in r.enemies.duplicate():
		if is_instance_valid(e):
			e.hp = 0.0
			e.die()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("clearing them wins (%s)" % r.state, r.state == "won")
	_check("the reward is paid (%d -> %d)" % [scrap0, main.player_scrap], main.player_scrap == scrap0 + int(FrankChallenges.find("glass_parade")["reward"]))
	_check("a record was kept", SaveManager.challenge_record("glass_parade") >= 0.0)
	r._return_timer = -1.0 # do not leave the scene in the test
	print("ChallengeRunnerCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
