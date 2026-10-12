extends Node

# The codex's terrain and combination sections: built from the real constants, one entry per combo, and the popup still builds.

const TerrainEffectsScript = preload("res://scripts/core/TerrainEffects.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var t = SynergyCodexPopup.terrain_entries()
	var text = ""
	for e in t:
		text += e["name"] + " " + e["desc"] + "\n"
	_check("terrain section covers road, shallows, ice, ash, forest, oil", "ROAD" in text and "SHALLOWS" in text and "TUNDRA ICE" in text and "VOLCANIC ASH" in text and "FOREST" in text and "OIL" in text)
	_check("road speed text comes from TerrainEffects (%s)" % SynergyCodexPopup._pct(TerrainEffectsScript.ROAD_SPEED), SynergyCodexPopup._pct(TerrainEffectsScript.ROAD_SPEED) in text and "+25%" in text)
	_check("shallows speed text is the real -40%", "-40%" in text)
	_check("ice traction text is the real 18%", "18%" in text)
	var c = SynergyCodexPopup.combo_entries()
	var names = []
	for e in c:
		names.append(e["name"])
	for combo_name in ElementCombos.COMBOS:
		_check("combo %s is documented" % combo_name, combo_name.to_upper() in names)
	_check("every entry has a description", t.all(func(e): return e["desc"] != "") and c.all(func(e): return e["desc"] != ""))
	_check("the pair names are real element names", "Kinetic + Ice" in str(c) and "Poison + Vortex" in str(c))
	_check("_pct formats a boost and a penalty", SynergyCodexPopup._pct(1.25) == "+25%" and SynergyCodexPopup._pct(0.6) == "-40%")
	var codex = SynergyCodexPopup.new(null)
	var popup = codex._build_popup()
	add_child(popup)
	var labels = 0
	var stack = [popup]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Label and ("TERRAIN" in n.text or "COMBINATIONS" in n.text or "SHATTER" in n.text):
			labels += 1
		stack.append_array(n.get_children())
	_check("the popup builds and shows both new section headers and the Shatter entry (%d)" % labels, labels >= 3)
	popup.queue_free()
	print("SynergyCodexSectionsCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
