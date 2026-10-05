extends Node

# Pre-built bot pool: draft -> park -> activate, plus the frozen-rarity and uncapped
# energy-scale rules that go with the garage-return rebuild. Runs against the real Main
# scene (needs a real director/world), headless.

var failures := 0
var _main: Node

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
	for i in range(30):
		await get_tree().process_frame
	_main.player_lives_remaining = 99
	var d = _main._ensure_squad_director()
	SaveManager.difficulty = 1 # expected_base_rarity ignores the wave on difficulty 0

	# --- rebuild + draft + fill -----------------------------------------------------
	_main.current_wave = 20
	d.begin_rebuild(20)
	d.draft_pool(24)
	var quota_total = 0
	for k in d._pool_quota:
		quota_total += int(d._pool_quota[k])
	var guard = 0
	while d.fill_pool_step() and guard < 200:
		guard += 1
		await get_tree().process_frame
	_check("pool filled to the drafted quota (stock %d / quota %d)" % [d.pool_stock(), quota_total], d.pool_stock() == quota_total and quota_total >= 24)
	_check("a draft queue exists for the wave (%d squads)" % d._draft_queue.size(), d._draft_queue.size() > 0)

	# --- parked bots are inert -----------------------------------------------------
	var parked_ok = true
	var parked_count = 0
	for k in d._pool:
		for b in d._pool[k]:
			parked_count += 1
			if b.is_in_group("enemy") or b.visible or b.collision_layer != 0 or b.process_mode != Node.PROCESS_MODE_DISABLED:
				parked_ok = false
	_check("%d parked bots: hidden, not in the enemy group, no collision, processing disabled" % parked_count, parked_ok and parked_count > 0)
	var enemies_before = get_tree().get_nodes_in_group("enemy").size()
	_check("parked bots are not counted as enemies", enemies_before == 0)

	# --- the wave consumes the draft: every member comes out of the pool --------------
	var hits0 = d.pool_hits
	var misses0 = d.pool_misses
	var stock0 = d.pool_stock()
	var squad = await d.spawn_squad([])
	_check("squad assembled from the draft", squad != null and squad.members.size() > 0)
	var n = squad.members.size() if squad else 0
	_check("every squad member was a pool hit (hits +%d, members %d, misses +%d)" % [d.pool_hits - hits0, n, d.pool_misses - misses0], d.pool_hits - hits0 == n and d.pool_misses == misses0)
	_check("pool stock dropped by the members taken", d.pool_stock() == stock0 - n)
	var active_ok = true
	for m in squad.members:
		if not is_instance_valid(m) or not m.is_in_group("enemy") or not m.visible or m.collision_layer != 4 or m.process_mode != Node.PROCESS_MODE_INHERIT:
			active_ok = false
	_check("activated bots are live enemies (group, visible, layer 4, processing on)", active_ok)

	# --- uncapped energy scale ----------------------------------------------------------
	_main.current_wave = 20
	_check("energy scale is 1.0 at the rebuild wave", is_equal_approx(d.energy_scale_for_wave(), 1.0))
	_main.current_wave = 30
	_check("+2%% per wave since rebuild (%.2f at +10)" % d.energy_scale_for_wave(), is_equal_approx(d.energy_scale_for_wave(), 1.2))
	_main.current_wave = 220
	_check("no cap (%.2f at +200 waves)" % d.energy_scale_for_wave(), is_equal_approx(d.energy_scale_for_wave(), 5.0))
	_main.current_wave = 30
	var squad2 = await d.spawn_squad([])
	var scaled = squad2 != null and squad2.members.size() > 0
	if scaled:
		for m in squad2.members:
			if is_instance_valid(m) and not is_equal_approx(m.energy_scale, 1.2):
				scaled = false
	_check("bots activated at +10 waves carry energy_scale 1.2", scaled)
	# HP is re-scaled to the CURRENT wave at activation, not frozen at build time.
	if squad2 != null and squad2.members.size() > 0 and is_instance_valid(squad2.members[0]):
		var m0 = squad2.members[0]
		var expect = float(m0.get_meta("pool_base_hp")) * d._wave_multiplier()
		_check("activation re-scales HP to the current wave (%.0f)" % m0.max_hp, is_equal_approx(m0.max_hp, expect))

	# --- rarity frozen between garage visits ---------------------------------------------
	_main.current_wave = 130
	var frozen = d.expected_base_rarity(0, "sniper")
	d.rebuild_wave = -1
	var unfrozen = d.expected_base_rarity(0, "sniper")
	d.rebuild_wave = 20
	_check("tier is frozen at the rebuild wave's tier (%d) not wave 130's (%d)" % [frozen, unfrozen], frozen < unfrozen)

	# --- a new rebuild throws the old pool away -------------------------------------------
	d.begin_rebuild(130)
	_check("begin_rebuild clears the pool and the draft", d.pool_stock() == 0 and d._draft_queue.is_empty() and d.rebuild_wave == 130)

	if failures == 0:
		print("PASS: bot pool draft/park/activate, frozen rarity, uncapped energy scale")
	get_tree().quit(0 if failures == 0 else 1)
