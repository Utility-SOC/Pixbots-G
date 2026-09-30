extends Node

# Screenshot the Garage at the current window size:
#   godot --path . --resolution 1280x720 res://scripts/debug/GarageShot.tscn -- --out=/tmp/garage.png
var _main: Node
var _t := 0.0
var _out := "/tmp/garage.png"
var _f5 := false
var _sent := false

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.split("=")[1]
		elif a == "--f5": _f5 = true
	_main = load("res://main.tscn").instantiate()
	add_child(_main)

func _process(delta):
	_t += delta
	if _f5 and not _sent and _t > 4.0:
		_sent = true
		print("GARAGESHOT garage before F5: ", is_instance_valid(_main.garage_ui))
		var ev = InputEventKey.new()
		ev.keycode = KEY_F5
		ev.pressed = true
		Input.parse_input_event(ev)
	if _t > 5.0:
		if _f5:
			print("GARAGESHOT garage after F5 valid=", is_instance_valid(_main.garage_ui) and not _main.garage_ui.is_queued_for_deletion(), " wave_timer=", _main.garage_timer)
		var img = get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("GARAGESHOT saved ", _out, " ", img.get_size())
		get_tree().quit()
