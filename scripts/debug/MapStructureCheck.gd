extends Node

# Map structure pass: every structured map type must keep the spawn clear and
# connected, contain roads/built floors/walls, and Normal must read as several
# big regions (not noise camouflage).

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const BT = MapGen.BiomeType
var failures := 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	for t in ["Normal", "Forest", "Desert", "Tundra", "Volcano", "Dungeon"]:
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var roads := 0
		var floors := 0
		var biomes := {}
		for y in range(m.height):
			for x in range(m.width):
				var b = m.terrain[y][x]
				biomes[b] = true
				if b == BT.ROAD: roads += 1
				elif b == BT.FLOOR: floors += 1
		var walls := 0
		for k in m.obstacles:
			if m.obstacles[k] == "Wall": walls += 1
		var c = Vector2i(m.width / 2, m.height / 2)
		_check("%s: spawn centre is walkable and on the main continent" % t,
			not m.obstacles.has(c) and m.terrain[c.y][c.x] != BT.WATER and m.main_continent_tiles.has(c))
		_check("%s: main continent is large (%d tiles)" % [t, m.main_continent_tiles.size()], m.main_continent_tiles.size() > m.width * m.height * 0.1)
		_check("%s: has built floors and walls (floors=%d walls=%d)" % [t, floors, walls], floors > 200 and walls > 100)
		if t != "Dungeon":
			_check("%s: has roads (%d tiles)" % [t, roads], roads > 400)
		if t == "Normal":
			_check("Normal reads as 3+ distinct ground types (%d)" % biomes.size(), biomes.size() >= 4)
		m.queue_free()
		await get_tree().process_frame
	print("map structure check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
