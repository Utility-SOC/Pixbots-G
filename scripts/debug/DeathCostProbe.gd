extends Node
# How much does killing a wave-40 bot cost (loot roll + death effects)? Builds N bots from the pool
# machinery, times LootManager.generate_loot_for_mech and Mech.die separately.
func _ready():
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	(func(): get_tree().current_scene = main).call_deferred()
	for i in range(30):
		await get_tree().process_frame
	main.player_lives_remaining = 99
	main.current_wave = 40
	var d = main._ensure_squad_director()
	d.begin_rebuild(40)
	d.draft_pool(30)
	while d.fill_pool_step():
		await get_tree().process_frame
	var squads = []
	for k in range(4):
		var s = await d.spawn_squad([])
		if s: squads.append(s)
	var bots = []
	for s in squads:
		for m in s.members:
			if is_instance_valid(m): bots.append(m)
	var tiles = 0
	for b in bots:
		for c in b.components.values():
			tiles += c.hex_grid.get_all_tiles().size()
	print("PROBE bots=%d avg_tiles_per_bot=%.0f" % [bots.size(), float(tiles) / max(1, bots.size())])
	var t_loot = 0
	var n_loot = 0
	for b in bots:
		var t0 = Time.get_ticks_usec()
		LootManager.generate_loot_for_mech(b)
		t_loot += Time.get_ticks_usec() - t0
		n_loot += 1
	await get_tree().process_frame
	var drops = get_tree().get_nodes_in_group("loot").size()
	print("PROBE loot roll: %.2f ms per bot (%d bots) -> %d pickups nodes" % [t_loot / 1000.0 / max(1, n_loot), n_loot, drops])
	var t_die = 0
	for b in bots:
		var t0 = Time.get_ticks_usec()
		if b.has_method("die"):
			b.die()
		t_die += Time.get_ticks_usec() - t0
	print("PROBE die(): %.2f ms per bot" % [t_die / 1000.0 / max(1, bots.size())])
	for i in range(3):
		await get_tree().process_frame
	get_tree().quit()
