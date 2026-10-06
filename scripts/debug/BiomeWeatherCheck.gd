extends Node

const W = preload("res://scripts/visuals/BiomeWeather.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("tundra snows, volcano embers, desert dust, forest leaves", W.preset_for_biome(4) == "snow" and W.preset_for_biome(5) == "embers" and W.preset_for_biome(2) == "dust" and W.preset_for_biome(3) == "leaves")
	_check("grass, road, water and dungeon are clear", W.preset_for_biome(0) == "" and W.preset_for_biome(7) == "" and W.preset_for_biome(1) == "" and W.preset_for_biome(6) == "")
	var w = W.new()
	add_child(w)
	w.apply(4)
	_check("applying a preset starts emitting with its count", w.emitting and w.current == "snow" and w.amount == W.PRESETS[4]["amount"])
	w.apply(0)
	_check("clear ground stops the weather", not w.emitting and w.current == "")
	w.apply(5)
	_check("switching preset swaps the material", w.current == "embers" and w.process_material != null and w.emitting)
	print("biome weather check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
