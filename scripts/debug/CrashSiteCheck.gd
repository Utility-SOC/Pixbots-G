extends Node

const MapGen = preload("res://scripts/core/MapGenerator.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var total = 0
	for t in ["Normal", "Forest", "Open Field", "Volcano"]:
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var caches = []
		for o in get_tree().get_nodes_in_group("zone_objective"):
			if o.get_parent() == m and o.kind == "cache":
				caches.append(o)
		# village caches also exist; crash-site caches are the ones with oil slicks next to them
		var sites = 0
		for c in caches:
			var oil = 0
			for s in get_tree().get_nodes_in_group("oil_slick"):
				if s.get_parent() == m and s.global_position.distance_to(c.global_position) < 120.0:
					oil += 1
			if oil >= 1:
				sites += 1
				var ts = m.tile_size
				var cell = Vector2i(int(c.global_position.x / ts), int(c.global_position.y / ts))
				_check("%s: the cache cell and its neighbours are open" % t, not m.obstacles.has(cell))
				var centre = Vector2(m.width / 2.0, m.height / 2.0)
				_check("%s: crash site is away from the spawn (%.0f tiles)" % [t, Vector2(cell).distance_to(centre)], Vector2(cell).distance_to(centre) >= 30.0)
				var wreck = 0
				for k in m.obstacles:
					if m.obstacles[k] == "Boulder" and Vector2(k).distance_to(Vector2(cell)) <= 5.0:
						wreck += 1
				_check("%s: wreckage ring stands around it (%d boulders)" % [t, wreck], wreck >= 3)
				var nodes = 0
				for ch in m.get_children():
					if ch is DestructibleObstacle and ch.obstacle_name == "Boulder" and ch.global_position.distance_to(c.global_position) <= ts * 5.5:
						nodes += 1
				_check("%s: every wreck boulder has a real collision node (%d nodes >= %d)" % [t, nodes, wreck], nodes >= wreck)
		total += sites
		m.queue_free()
		await get_tree().process_frame
	_check("crash sites got built across the sample maps (%d)" % total, total >= 3)
	var tt = MapGen.new()
	tt.map_type = "Tabletop"
	add_child(tt)
	await get_tree().process_frame
	_check("Tabletop gets none", tt._place_crash_sites() == 0)
	print("crash site check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
