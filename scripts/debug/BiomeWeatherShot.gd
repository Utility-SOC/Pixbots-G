extends Node
# Screenshot of each weather preset.  godot --path . res://scripts/debug/BiomeWeatherShot.tscn -- --out=/path.png
func _ready():
	var out = "/tmp/weather.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var cols = [[4, Color(0.8, 0.9, 0.9)], [5, Color(0.3, 0.1, 0.1)], [2, Color(0.9, 0.8, 0.5)], [3, Color(0.1, 0.5, 0.2)]]
	var sub_viewports = []
	for i in range(4):
		var vp = SubViewport.new(); vp.size = Vector2i(420, 300); vp.transparent_bg = false
		var holder = SubViewportContainer.new(); holder.position = Vector2((i % 2) * 430, (i / 2) * 310); holder.add_child(vp); add_child(holder)
		var bg = ColorRect.new(); bg.color = cols[i][1]; bg.size = Vector2(420, 300); vp.add_child(bg)
		var w = load("res://scripts/visuals/BiomeWeather.gd").new(); w.position = Vector2(210, 150); vp.add_child(w)
		w.apply(cols[i][0])
		w.visibility_rect = Rect2(-600, -400, 1200, 800)
	for f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
