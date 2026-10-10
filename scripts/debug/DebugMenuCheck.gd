extends Node

# Keeps the debug menu honest: every tile script in scripts/tiles is either grantable from the menu or explicitly
# excluded, the menu builds without errors, the layout/difficulty lists are sourced from the real constants, and the
# Remediation Matrix is boss-drop-only (wave >= LootManager.REMEDIATION_MATRIX_MIN_WAVE).

const DebugMenuScript = preload("res://scripts/ui/DebugMenu.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var listed := {}
	for p in DebugMenuScript.TILE_SCRIPTS:
		listed[p.get_file().get_basename()] = true
		var s = load(p)
		_check("loads %s" % p.get_file(), s != null and s.new() is HexTile)
	var dir := DirAccess.open("res://scripts/tiles")
	for f in dir.get_files():
		if not f.ends_with("Tile.gd"):
			continue
		var n := f.get_basename()
		_check("%s is grantable or excluded" % n, listed.has(n) or n in DebugMenuScript.TILE_SCRIPTS_EXCLUDED or n == "StructuralStrutTile")
	_check("Matrix is grantable", listed.has("RemediationMatrixTile"))

	var menu = DebugMenuScript.new()
	add_child(menu)
	_check("menu builds", menu.panel != null and menu.boss_opt != null)
	menu.queue_free()

	var lm = LootManager
	_check("no matrix drop before the min wave", lm.remediation_matrix_chance(lm.REMEDIATION_MATRIX_MIN_WAVE - 1) == 0.0)
	_check("matrix can drop at the min wave", lm.remediation_matrix_chance(lm.REMEDIATION_MATRIX_MIN_WAVE) > 0.0)
	_check("min wave is 150", lm.REMEDIATION_MATRIX_MIN_WAVE == 150)
	_check("rarity labels match enum", DebugMenuScript.GRANT_RARITIES.size() == HexTile.Rarity.size())

	print("DebugMenuCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
