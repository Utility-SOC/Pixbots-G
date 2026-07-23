extends Node

# Regression harness for MapGenerator._build_terrain_chunk's Rust-rasterizer
# wiring (see terrain_rasterizer.rs) - confirms map generation still
# completes cleanly and produces real chunk sprites/textures across a few
# map_types that each exercise a different _get_biome_color/
# _get_textured_pixel_color branch (Normal's per-biome match, Tabletop's
# flock texture, FightShovel's dust texture + corn fields). Whether the Rust
# path or the GDScript fallback actually ran depends on whether the built
# extension DLL is loaded (ClassDB.class_exists("TerrainRasterizer")) - this
# check passes either way, since the fallback must keep working regardless.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _generate_and_verify(map_type: String):
	var map = load("res://scripts/core/MapGenerator.gd").new()
	map.map_type = map_type
	add_child(map)
	# _ready() runs generation synchronously (see MapGenerator.gd's own
	# comment on this) - nothing to await.

	_check("%s: terrain grid populated" % map_type, map.terrain.size() > 0)
	_check("%s: main_continent_tiles non-empty" % map_type, map.main_continent_tiles.size() > 0)

	var sprite_count = 0
	var total_pixels_nonzero = false
	for child in map.get_children():
		if child is Sprite2D:
			sprite_count += 1
			if child.texture:
				var img = child.texture.get_image()
				if img and img.get_width() > 0 and img.get_height() > 0:
					# Sample a handful of pixels - real terrain paint should
					# produce fully-opaque, non-black-default pixels almost
					# everywhere (only a truly empty/zeroed buffer would fail
					# this, which is exactly the failure mode a broken
					# rasterize_chunk call - e.g. wrong buffer size, all-zero
					# alpha - would produce).
					var w = img.get_width()
					var h = img.get_height()
					for i in range(5):
						var px = img.get_pixel(min(w - 1, i * 7), min(h - 1, i * 5))
						if px.a > 0.5:
							total_pixels_nonzero = true

	_check("%s: chunk sprites were created" % map_type, sprite_count > 0)
	_check("%s: painted chunk pixels are real (non-transparent) data" % map_type, total_pixels_nonzero)

	map.queue_free()

func _ready():
	print("TerrainRasterizer wired via ClassDB: %s" % ClassDB.class_exists("TerrainRasterizer"))

	_generate_and_verify("Normal")
	await get_tree().process_frame
	_generate_and_verify("Tabletop")
	await get_tree().process_frame
	_generate_and_verify("FightShovel")
	await get_tree().process_frame

	if failures == 0:
		print("PASS: MapGenerator terrain-chunk rasterization (Rust path or GDScript fallback) produces real chunk textures across map_types")
	get_tree().quit(0 if failures == 0 else 1)
