extends Node

# The three shop backdrops draw (right size, not flat, deterministic, distinct from each other), the cutscene player picks them by scene
# name, and the menu frame builds and sits behind its menu.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _distinct_colors(img: Image) -> int:
	var seen := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			seen[img.get_pixel(x, y).to_html()] = true
	return seen.size()

func _ready():
	var sums := {}
	for k in ShopBackdrop.KINDS:
		var img = ShopBackdrop.make(k).get_image()
		_check("%s is %dx%d" % [k, ShopBackdrop.W, ShopBackdrop.H], img.get_width() == ShopBackdrop.W and img.get_height() == ShopBackdrop.H)
		_check("%s is richly coloured (%d colours)" % [k, _distinct_colors(img)], _distinct_colors(img) > 40)
		var again = ShopBackdrop.make(k).get_image()
		_check("%s is deterministic" % k, img.get_data() == again.get_data())
		sums[k] = hash(img.get_data())
	_check("the three scenes differ", sums["register"] != sums["tables"] and sums["tables"] != sums["back"] and sums["register"] != sums["back"])
	for scene_name in ["shop", "shop_tables", "shop_back"]:
		var data = {"background": {"scene": scene_name}, "actors": {}, "steps": [{"cmd": "wait", "duration": 0.1}]}
		var path = "user://shop_bd_check_%s.json" % scene_name
		var f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		var player = CutscenePlayer.create_from_file(path)
		_check("a cutscene on '%s' loads" % scene_name, player != null)
		if player != null:
			add_child(player)
			var has_tex = false
			for c in player.get_children():
				if c is TextureRect and c.texture != null:
					has_tex = true
			_check("'%s' puts a backdrop texture in the scene" % scene_name, has_tex)
			player.queue_free()
	var fr = ShopBackdrop.frame("register")
	add_child(fr)
	_check("the menu frame is a full-screen texture plus a dimmer", fr.get_child_count() == 2 and fr.get_child(0) is TextureRect and fr.get_child(1) is ColorRect and fr.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	print("ShopBackdropCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
