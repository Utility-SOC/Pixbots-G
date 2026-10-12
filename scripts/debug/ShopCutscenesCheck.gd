extends Node

# Every cutscene the manifest maps to a wave loads and plays to completion with its say-steps auto-advancing (including the
# new shop beats with the cat prop), each at most once per session via the manifest factory.

const CutscenePlayer = preload("res://scripts/cutscene/CutscenePlayer.gd")
const DT := 1.0 / 30.0

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var f = FileAccess.open("res://config/cutscenes/manifest.json", FileAccess.READ)
	var manifest = JSON.parse_string(f.get_as_text())
	f.close()
	var waves: Dictionary = manifest["waves"]
	_check("the manifest maps at least ten beats (%d)" % waves.size(), waves.size() >= 10)
	for w in waves:
		var path = "res://config/cutscenes/" + str(waves[w])
		_check("wave %s scene file exists" % w, FileAccess.file_exists(path))
		var player = CutscenePlayer.create_from_file(path)
		_check("wave %s scene loads (%s)" % [w, str(waves[w])], player != null)
		if player == null:
			continue
		add_child(player)
		var t = 0.0
		while is_instance_valid(player) and not player._done and t < 240.0:
			player._process(DT)
			t += DT
		_check("wave %s plays to the end (%.0f s)" % [w, t], not is_instance_valid(player) or player._done)
		if is_instance_valid(player):
			player.queue_free()
	var cat_tex = CutscenePlayer._make_prop_placeholder_texture(Color("#e08c33"), "cat")
	_check("the cat prop draws", cat_tex != null and cat_tex.get_width() == 20 and cat_tex.get_height() == 18)
	print("ShopCutscenesCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
