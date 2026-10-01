extends Node
# Repro: clear wave 1 (which queues the wave-2 cinematic), skip it, and make sure
# the player's limbs are still drawn afterwards.
var _main: Node
var _f := 0
func _ready():
	SaveManager.current_game_mode = "campaign"
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
func _shot(name: String):
	get_viewport().get_texture().get_image().save_png("/tmp/claude-1000/-home-utility/17ccdd67-e069-4906-80aa-acb28869915b/scratchpad/" + name + ".png")
func _dump(tag: String):
	var p = _main.player
	var r = p._renderer
	print(tag, " parts=", r.drawn_parts.keys(), " tree_paused=", get_tree().paused)
	for k in r.drawn_parts:
		var n = r.drawn_parts[k]
		print("   ", k, " vis=", n.visible, " gvis=", n.is_visible_in_tree(), " z=", n.z_index, " mod=", n.modulate, " gpos=", n.global_position)
func _process(_d):
	_f += 1
	if is_instance_valid(_main.player):
		_main.player.hp = _main.player.max_hp
	if _f == 60 and is_instance_valid(_main.garage_ui): _main._close_garage()
	if _f == 300:
		_dump("before"); _shot("cs_before")
		_main.active_enemies = 0
		var CP = load("res://scripts/cutscene/CutscenePlayer.gd")
		CP._seen_this_session.clear()
		_main.current_wave = 1
		print("maybe_create(2) -> ", CP.maybe_create_for_wave(2))
		CP._seen_this_session.clear()
		_main._on_wave_cleared()
	if _f == 360:
		var cs = null
		for c in _main.get_children():
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("CutscenePlayer.gd"): cs = c
		print("cutscene present: ", cs != null)
		_dump("during"); _shot("cs_during")
		if cs: cs.skip()
	if _f == 480:
		_dump("after"); _shot("cs_after")
	if _f == 440: _main.player._renderer.drawn_parts["Arm_true"].visible = false
	if _f == 520: get_tree().quit()
