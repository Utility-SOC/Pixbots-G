extends Node

# Dumps a 1px-per-tile overview PNG of each map type to ~/pixbots_map_overviews
# (terrain colour, obstacles drawn dark) so macro structure can be judged.

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const TYPES = ["Normal", "Open Field", "Desert", "Forest", "Tundra", "Volcano", "Dungeon", "Water", "Tabletop", "FightShovel"]

func _ready():
	var dir = OS.get_environment("HOME") + "/pixbots_map_overviews"
	DirAccess.make_dir_recursive_absolute(dir)
	var only = OS.get_environment("MAPTYPE")
	for t in TYPES:
		if only != "" and t != only:
			continue
		var m = MapGen.new()
		m.map_type = t
		add_child(m)
		await get_tree().process_frame
		var img = Image.create(m.width, m.height, false, Image.FORMAT_RGB8)
		for y in range(m.height):
			for x in range(m.width):
				img.set_pixel(x, y, m._get_biome_color(m.terrain[y][x]))
		for k in m.obstacles:
			img.set_pixel(k.x, k.y, Color(0.05, 0.05, 0.05))
		img.save_png("%s/%s.png" % [dir, t.replace(" ", "_")])
		print("%s: layout=%s obstacles=%d" % [t, m.layout_name, m.obstacles.size()])
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
