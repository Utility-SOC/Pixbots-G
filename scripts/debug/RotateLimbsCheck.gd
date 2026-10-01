extends Node
# Repro for "limbs vanish after the map rotates": snapshot the player's
# renderer parts before and after Main._rotate_campaign_map().
var _main: Node
var _f := 0
func _ready():
	SaveManager.current_game_mode = "campaign"
	_main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(func(): get_tree().current_scene = _main).call_deferred()
func _dump(tag: String):
	var p = _main.player
	if not is_instance_valid(p): print(tag, ": no player"); return
	var r = p._renderer
	print(tag, " player z=", p.z_index, " map z=", _main.map.z_index, " "); print(tag, ": comps=", p.components.keys(), " parts=", r.drawn_parts.keys(), " children=", r.get_child_count())
	for k in r.drawn_parts:
		var n = r.drawn_parts[k]
		print("   ", k, " valid=", is_instance_valid(n), " vis=", n.visible if is_instance_valid(n) else "-", " inTree=", n.is_inside_tree() if is_instance_valid(n) else "-", " scale=", n.scale, " pos=", n.position, " rot=", n.rotation, " z=", n.z_index, " zrel=", n.z_as_relative, " mod=", n.modulate, " kids=", n.get_child_count(), " load=", n.get_meta("grid_load", -1), " mod=", n.modulate)
func _shot(name: String):
	get_viewport().get_texture().get_image().save_png("/tmp/claude-1000/-home-utility/17ccdd67-e069-4906-80aa-acb28869915b/scratchpad/" + name + ".png")
func _process(_d):
	_f += 1
	if is_instance_valid(_main.player):
		_main.player.hp = _main.player.max_hp
	if _f == 60 and is_instance_valid(_main.garage_ui): _main._close_garage()
	if _f == 200:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://config/demo_builds/gunner.json"))
		SaveManager.load_loadout_from_data(d, _main.player) if SaveManager.has_method("load_loadout_from_data") else _apply_demo(d)
	if _f == 220:
		_main.player._recalculate_grid(); _main.player.refresh_visuals(); _dump("demo"); _shot("limbs_demo")
	if _f == 300:
		var arm = _main.player.components[HexTile.BodySlot.ARM_L]
		var id0 = _main.player._renderer.drawn_parts["Arm_true"].get_instance_id()
		var t = arm.hex_grid.get_all_tiles()[arm.hex_grid.get_all_tiles().size() - 1]
		arm.hex_grid.remove_tile(t.grid_position)
		set_meta("id0", id0)
	if _f == 305:
		var id1 = _main.player._renderer.drawn_parts["Arm_true"].get_instance_id()
		print("REDRAW ", "ok" if id1 != get_meta("id0") else "FAIL (no redraw)")
	if _f == 400: _dump("before"); _shot("limbs_before")
	if _f == 401: _main.active_enemies = 0; _main._map_rotation_elapsed = 1e9; print("rotate? ", _main._should_rotate_map()); _main._on_wave_cleared(); print("map type: ", _main.map.map_type)
	if _f == 470: _dump("after"); _shot("limbs_after")
	if _f == 520: get_tree().quit()
func _apply_demo(data):
	var player = _main.player
	for slot in player.components.keys().duplicate():
		var old = player.unequip_component(slot)
		if old: old.queue_free()
	for slot_str in data["components"]:
		var comp = SaveManager._deserialize_component(data["components"][slot_str])
		if comp: player.equip_component(comp)
	player.is_grid_dirty = true
