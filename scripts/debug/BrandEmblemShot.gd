extends Node2D
# Screenshot of the seven brand emblems at tile size and banner size.
#   godot --path . res://scripts/debug/BrandEmblemShot.tscn -- --out=/path.png
const Emblem = preload("res://scripts/ui/BrandEmblem.gd")
const Registry = preload("res://scripts/core/BrandRegistry.gd")
func _ready():
	var out = "/tmp/emblems.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	await get_tree().process_frame
	queue_redraw()
	for f in range(6):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
func _draw():
	draw_rect(Rect2(0, 0, 1200, 300), Color(0.1, 0.1, 0.13))
	var i = 0
	for id in Registry.BRAND_IDS:
		var col = Registry.accent_color(id)
		var x = 70 + i * 160
		Emblem.draw(self, id, Vector2(x, 90), 56.0, col)
		Emblem.draw(self, id, Vector2(x - 40, 220), 9.0, col)
		# on a hex tile, as in the Garage
		var hex = PackedVector2Array()
		for k in range(6):
			hex.append(Vector2(x + 20, 220) + Vector2.from_angle(PI / 6.0 + k * PI / 3.0) * 30.0)
		draw_colored_polygon(hex, Color(0.15, 0.15, 0.15))
		draw_polyline(hex + PackedVector2Array([hex[0]]), Color(0.4, 1.0, 0.4), 2.0)
		Emblem.draw(self, id, Vector2(x + 20, 220), 11.0, col)
		i += 1
