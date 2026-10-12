extends Node

# BiomeIdentity: climate scales Freeze/Burn by the ground under the target; an Explosion sets off an idle lava vent.

const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

class FakeMap extends Node2D:
	var biome: int = 0
	func get_biome_at_world_pos(_p: Vector2) -> int:
		return biome

func _ready():
	_check("tundra keeps ice longer and burns shorter", BiomeIdentity.status_mult(4, "frozen") > 1.0 and BiomeIdentity.status_mult(4, "burning") < 1.0)
	_check("desert and volcano melt ice and feed fire", BiomeIdentity.status_mult(2, "frozen") < 1.0 and BiomeIdentity.status_mult(5, "frozen") < BiomeIdentity.status_mult(2, "frozen") and BiomeIdentity.status_mult(5, "burning") > 1.0)
	_check("water douses fire", BiomeIdentity.status_mult(1, "burning") < 0.5 and BiomeIdentity.status_mult(9, "burning") < 0.5)
	_check("grassland, road and dungeon are neutral", BiomeIdentity.status_mult(0, "frozen") == 1.0 and BiomeIdentity.status_mult(7, "burning") == 1.0 and BiomeIdentity.status_mult(6, "burning") == 1.0)
	_check("other statuses are never touched", BiomeIdentity.status_mult(4, "poisoned") == 1.0)

	var map = FakeMap.new()
	map.add_to_group("map_generator")
	add_child(map)
	var m = MechScript.new()
	m.is_player = false
	add_child(m)
	m.set_physics_process(false)
	EntityCache._stamp = -2
	map.biome = 4
	m.apply_status("frozen", 2.0)
	_check("a victim on tundra stays frozen longer (%.2f)" % m.status_effects["frozen"], is_equal_approx(m.status_effects["frozen"], 3.0))
	map.biome = 5
	m.apply_status("frozen", 2.0)
	_check("on volcanic ground the same freeze is short (%.2f)" % m.status_effects["frozen"], is_equal_approx(m.status_effects["frozen"], 1.2))
	map.biome = 1
	m.apply_status("burning", 5.0)
	_check("burning in water is cut (%.2f)" % m.status_effects["burning"], is_equal_approx(m.status_effects["burning"], 2.0))
	m.apply_status("poisoned", 4.0)
	_check("poison is not scaled", is_equal_approx(m.status_effects["poisoned"], 4.0))

	var vent = LavaVent.new()
	vent.radius = 40.0
	add_child(vent)
	_check("an idle vent can be set off", vent.trigger() and vent.is_dangerous())
	_check("a vent already warning cannot be re-triggered", not vent.trigger())
	vent.free()
	m.free()
	map.free()
	print("BiomeIdentityCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
