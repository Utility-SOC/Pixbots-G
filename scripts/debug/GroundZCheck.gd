extends Node

# Everything that sits on the ground with a negative z_index (craters, scorch decals, shallow tint, oil
# slicks, lava vents, objective rings) must draw ABOVE the baked ground chunks. The ground used to be z=0, so
# all of them were hidden beneath it. Compare real z values.
const MapGen = preload("res://scripts/core/MapGenerator.gd")
const Vent = preload("res://scripts/hazards/LavaVent.gd")
const Obj = preload("res://scripts/hazards/ZoneObjective.gd")
const Scorch = preload("res://scripts/visuals/ScorchDecals.gd")
const Shallow = preload("res://scripts/visuals/ShallowOverlay.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var m = MapGen.new()
	m.map_type = "Open Field"
	add_child(m)
	await get_tree().process_frame
	var ground_z = 0
	var found = false
	for ch in m.get_children():
		if ch is Sprite2D:
			ground_z = ch.z_index
			found = true
			break
	_check("ground chunk sprites exist and sit at GROUND_Z (%d)" % ground_z, found and ground_z == MapGen.GROUND_Z)
	var probes = {"lava vent": Vent.new(), "zone objective": Obj.new(), "scorch decals": Scorch.new(), "shallow overlay": Shallow.new()}
	for k in probes:
		var n = probes[k]
		add_child(n)
		_check("%s draws above the ground (z %d > %d)" % [k, n.z_index, ground_z], n.z_index > ground_z)
		n.queue_free()
	var oil = load("res://scripts/hazards/OilSlickHazard.gd").new()
	add_child(oil)
	_check("oil slick draws above the ground (z %d)" % oil.z_index, oil.z_index > ground_z)
	_check("death craters (z -10) draw above the ground", -10 > ground_z)
	print("ground z check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
