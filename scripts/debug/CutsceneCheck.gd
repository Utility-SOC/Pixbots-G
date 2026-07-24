extends Node

# Regression harness for the pixel-art cutscene framework
# (scripts/cutscene/CutscenePlayer.gd): plays the bundled sample scene
# end-to-end by driving _process manually through every command type,
# verifies say-steps advance, actors enter/exit, finished fires exactly
# once, the tree pause state is restored, and skip() ends a scene
# instantly. Also checks the manifest factory's once-per-session gate.

const CutscenePlayer = preload("res://scripts/cutscene/CutscenePlayer.gd")

const DT := 1.0 / 30.0
const SAMPLE := "res://config/cutscenes/frank_scrap_pitch.json"

var _finished_count := 0

func _on_finished():
	_finished_count += 1

func _drive(player, seconds: float):
	for i in range(int(seconds / DT)):
		if not is_instance_valid(player) or player._done:
			return
		player._process(DT)

func _ready():
	var failures = 0

	# --- 1. Full playthrough of the sample scene -------------------------
	var player = CutscenePlayer.create_from_file(SAMPLE)
	if player == null:
		push_error("FAIL: create_from_file couldn't load the sample scene")
		get_tree().quit(1)
		return
	player.finished.connect(_on_finished)
	add_child(player) # _ready pauses the tree and starts step 0

	if not get_tree().paused:
		push_error("FAIL: cutscene didn't pause the tree")
		failures += 1
	var frank = player._actors.get("frank")
	if frank == null or frank.texture == null:
		push_error("FAIL: actor missing or placeholder texture not generated")
		failures += 1
	else:
		print("1) scene loaded, tree paused, placeholder actor built (%dx%d)" % [frank.texture.get_width(), frank.texture.get_height()])

	# enter (1.1s) finishes, then the scene sits on a say step
	_drive(player, 1.5)
	if str(player._step.get("cmd", "")) != "say" or not frank.visible:
		push_error("FAIL: expected to be on the first say with actor visible, on '%s'" % str(player._step))
		failures += 1
	else:
		print("2) enter completed, first say active")

	# advance() must finish typing first, then a second advance() moves on
	player.advance()
	if player._text_label.text != str(player._step.get("text", "")):
		push_error("FAIL: first advance() didn't complete the typewriter text")
		failures += 1
	var say_step_i = player._step_i
	player.advance()
	if player._step_i != say_step_i + 1:
		push_error("FAIL: second advance() didn't leave the say step")
		failures += 1
	else:
		print("3) advance() finishes typing, then advances")

	# Drive the rest (shake, say w/ auto, flip, exit) to natural completion.
	_drive(player, 12.0)
	if _finished_count != 1:
		push_error("FAIL: finished fired %d times, expected exactly 1" % _finished_count)
		failures += 1
	elif get_tree().paused:
		push_error("FAIL: tree still paused after the scene ended")
		failures += 1
	elif frank.visible:
		push_error("FAIL: exit step didn't hide the actor")
		failures += 1
	else:
		print("4) played to the end: finished once, pause restored, actor exited")

	# --- 2. skip() ends a fresh scene instantly ---------------------------
	_finished_count = 0
	var player2 = CutscenePlayer.create_from_file(SAMPLE)
	add_child(player2)
	player2.finished.connect(_on_finished)
	player2.skip()
	if _finished_count != 1 or get_tree().paused:
		push_error("FAIL: skip() didn't end the scene cleanly (finished=%d paused=%s)" % [_finished_count, get_tree().paused])
		failures += 1
	else:
		print("5) skip() ends the scene instantly, pause restored")

	# --- 3. Manifest factory: mapped wave plays once per session ----------
	CutscenePlayer._seen_this_session.clear()
	var from_manifest = CutscenePlayer.maybe_create_for_wave(2)
	var second_time = CutscenePlayer.maybe_create_for_wave(2)
	var unmapped = CutscenePlayer.maybe_create_for_wave(999)
	if from_manifest == null or second_time != null or unmapped != null:
		push_error("FAIL: manifest gate wrong (first=%s second=%s unmapped=%s)" % [from_manifest, second_time, unmapped])
		failures += 1
	else:
		print("6) manifest: wave 2 maps once per session, unmapped waves are null")
		from_manifest.free()

	# --- 4. Prop actors (shop set-dressing: glass card case, cash register,
	# ...) get a furniture placeholder, not the humanoid character one, and
	# don't need to say/exit - they can just sit in the scene the whole time.
	var prop_scene_data = {
		"background": {"color": "#101018"},
		"actors": {
			"frank": {"placeholder_color": "#4d8bd4"},
			"case": {"kind": "prop", "placeholder_color": "#6a7a8a"},
		},
		"steps": [
			{"cmd": "enter", "actor": "case", "from": [0.7, 0.6], "to": [0.7, 0.6], "duration": 0.01},
			{"cmd": "enter", "actor": "frank", "from": [0.75, 0.9], "to": [0.7, 0.55], "duration": 0.5},
			{"cmd": "say", "actor": "frank", "name": "Frank", "text": "Testing.", "auto": 0.1},
			{"cmd": "exit", "actor": "frank", "to": [1.1, 0.55], "duration": 0.3},
		],
	}
	var player3 = load("res://scripts/cutscene/CutscenePlayer.gd").new()
	player3.cutscene_data = prop_scene_data
	add_child(player3)
	var case_actor = player3._actors.get("case")
	var frank_actor = player3._actors.get("frank")
	if case_actor == null or frank_actor == null:
		push_error("FAIL: prop and character actors should both be built")
		failures += 1
	elif case_actor.texture.get_size() == frank_actor.texture.get_size() and case_actor.texture.get_image().get_data() == frank_actor.texture.get_image().get_data():
		push_error("FAIL: prop placeholder should look different from the character placeholder")
		failures += 1
	else:
		print("7) prop actors get a distinct furniture-silhouette placeholder, not the humanoid one")
	_drive(player3, 3.0)
	if case_actor.visible != true:
		push_error("FAIL: a prop that never gets an 'exit' step should just stay visible for the whole scene")
		failures += 1
	else:
		print("8) a prop with no exit step stays visible for the whole scene")
	player3.skip()

	# --- 5. Shared shop background (per the user: reuse one backdrop across
	# every in-shop cutscene instead of a flat void color / floating props
	# with nothing establishing they're in a room). ---
	var shop_tex = CutscenePlayer._make_shop_background_texture()
	if shop_tex == null or shop_tex.get_width() < 100 or shop_tex.get_height() < 50:
		push_error("FAIL: shop background texture missing or degenerate (%s)" % shop_tex)
		failures += 1
	else:
		var img = shop_tex.get_image()
		var has_opaque_pixel = false
		for i in range(20):
			var px = img.get_pixel(randi() % img.get_width(), randi() % img.get_height())
			if px.a > 0.9:
				has_opaque_pixel = true
				break
		if not has_opaque_pixel:
			push_error("FAIL: shop background sampled as fully transparent - not actually drawing anything")
			failures += 1
		else:
			print("9) shop background texture generates a real, opaque %dx%d image" % [img.get_width(), img.get_height()])

	# register vs case must be genuinely different silhouettes now, not the
	# same shape with a different flat color (the actual bug report).
	var register_tex = CutscenePlayer._make_prop_placeholder_texture(Color.html("#8a8a90"), "register")
	var case_tex = CutscenePlayer._make_prop_placeholder_texture(Color.html("#8a8a90"), "case") # SAME color on purpose
	if register_tex.get_image().get_data() == case_tex.get_image().get_data():
		push_error("FAIL: register and case still render as the exact same shape")
		failures += 1
	else:
		print("10) register and case are genuinely different silhouettes (same color, different shape)")

	# A real scene built with "background": {"scene": "shop"} must actually
	# use the shop texture path, not silently fall back to the flat color.
	var shop_scene_data = {
		"background": {"scene": "shop"},
		"actors": {"frank": {"placeholder_color": "#4d8bd4"}},
		"steps": [{"cmd": "say", "actor": "frank", "name": "Frank", "text": "Testing.", "auto": 0.1}],
	}
	var player4 = load("res://scripts/cutscene/CutscenePlayer.gd").new()
	player4.cutscene_data = shop_scene_data
	add_child(player4)
	var shop_bg_found = false
	for child in player4.get_children():
		if child is TextureRect and child.texture != null and child.texture.get_width() == shop_tex.get_width():
			shop_bg_found = true
			break
	if not shop_bg_found:
		push_error("FAIL: 'background': {'scene': 'shop'} didn't actually add the shop TextureRect")
		failures += 1
	else:
		print("11) 'background': {'scene': 'shop'} wires up the shared backdrop texture")
	player4.skip()

	# The two real in-shop cutscene files should actually use the shared
	# background now, not their old separate flat colors.
	for path in ["res://config/cutscenes/tutorial_welcome.json", "res://config/cutscenes/frank_scrap_pitch.json"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var bg = data.get("background", {}) if data is Dictionary else {}
		if str(bg.get("scene", "")) != "shop":
			push_error("FAIL: %s doesn't use the shared shop background" % path)
			failures += 1
	print("12) both real in-shop cutscenes reference the shared shop background")

	# --- 6. Register sits ON the counter (per the user: "the bottom of the
	# register should be the top of the counter") - geometric check against
	# the real tutorial_welcome.json positions and a fixed reference
	# viewport (the 1152x648 that comment's math assumes and
	# CutscenePlayer._viewport_size()'s own fallback default). ---
	get_tree().root.size = Vector2i(1152, 648)
	var player5 = CutscenePlayer.create_from_file("res://config/cutscenes/tutorial_welcome.json")
	add_child(player5)
	# It's a sequential step machine - case's "enter" is step 0, register's
	# is step 1. _ready() only starts step 0; register's position isn't set
	# until its own step actually runs. Drive past both (each duration 0.01).
	_drive(player5, 0.2)
	var counter_actor = player5._actors.get("case")
	var register_actor2 = player5._actors.get("register")
	if counter_actor == null or register_actor2 == null or counter_actor.texture == null or register_actor2.texture == null:
		push_error("FAIL: tutorial_welcome.json's case/register actors didn't build")
		failures += 1
	else:
		var case_top = counter_actor.position.y - (counter_actor.texture.get_height() * counter_actor.scale.y) / 2.0
		var register_bottom = register_actor2.position.y + (register_actor2.texture.get_height() * register_actor2.scale.y) / 2.0
		var gap = abs(register_bottom - case_top)
		if gap > 3.0:
			push_error("FAIL: register's bottom (%.1f) isn't sitting on the counter's top (%.1f) - gap %.1fpx" % [register_bottom, case_top, gap])
			failures += 1
		else:
			print("13) register's base sits flush on the counter's top edge (gap %.1fpx)" % gap)
	player5.skip()

	if failures == 0:
		print("PASS: cutscene framework - load, act, say, advance, skip, manifest gate, prop actors")
	get_tree().quit(0 if failures == 0 else 1)
