extends Node

# Regression harness for: "Could it force me to do the tutorial every time
# I start a new game unless I click skip? (And clicking skip equips the
# bot well enough - not WELL, but functional)."
#
# Two behaviors under test:
#   1. Gating: TutorialManager._ready() now keys ONLY off the per-save
#      SaveManager.tutorial_completed bit (false on every new game) - the
#      old machine-wide user://tutorial_completed.flag file is ignored, so
#      the tutorial runs on every fresh game even on a machine that
#      finished it before. (This dev machine HAS that legacy flag file
#      from real play, making it a perfect natural fixture - the file is
#      read-only evidence here, never created/deleted: user:// is real
#      player data.)
#   2. Skip: _on_skip() runs the real AutoEquipSolver over the player's
#      equipped components with their actual inventory before finishing,
#      so a skipping player deploys functional (routed energy, armed
#      weapon mounts) instead of bare-grid helpless.

const TutorialManagerScript = preload("res://scripts/ui/TutorialManager.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

class MainStub:
	extends Node
	var player = null
	var player_inventory: Array = []

func _ready():
	var prior_completed = SaveManager.tutorial_completed

	# --- 1. Gating: a fresh new game (per-save bit false) always starts the
	# tutorial, regardless of the legacy machine-wide flag file. ---
	SaveManager.tutorial_completed = false
	var main_stub = MainStub.new()
	add_child(main_stub)
	var tm = TutorialManagerScript.new()
	main_stub.add_child(tm)
	await get_tree().process_frame
	var legacy_flag_present = FileAccess.file_exists(TutorialManagerScript.SAVE_FLAG_PATH)
	_check("new game starts the tutorial (per-save bit false%s)" % (", legacy flag file present and correctly IGNORED" if legacy_flag_present else ""),
		tm.is_active)

	# A save that already completed it stays dormant.
	SaveManager.tutorial_completed = true
	var tm2 = TutorialManagerScript.new()
	main_stub.add_child(tm2)
	await get_tree().process_frame
	_check("a save with the tutorial already completed stays dormant", not tm2.is_active)
	SaveManager.tutorial_completed = false

	# --- 2. Skip auto-equip: real Mech + real solver ---
	var player = MechScript.new()
	player.is_player = true
	main_stub.player = player
	main_stub.add_child(player)
	player.set_physics_process(false)
	main_stub.player_inventory = [
		AmplifierTileScript.new(), AmplifierTileScript.new(),
		SplitterTileScript.new(), SplitterTileScript.new(),
	]
	var inv_before = main_stub.player_inventory.size()
	var torso = player.components[HexTile.BodySlot.TORSO]
	var torso_tiles_before = torso.hex_grid.get_all_tiles().size()

	tm._apply_skip_equip()

	_check("skip-equip placed real tiles into the torso grid (%d -> %d)" % [torso_tiles_before, torso.hex_grid.get_all_tiles().size()],
		torso.hex_grid.get_all_tiles().size() > torso_tiles_before)
	_check("skip-equip consumed from the player's actual inventory (%d -> %d)" % [inv_before, main_stub.player_inventory.size()],
		main_stub.player_inventory.size() < inv_before)
	_check("the skipping player deploys FUNCTIONAL - armed weapon mounts exist after the solve",
		player.precalculated_weapons.size() > 0)

	SaveManager.tutorial_completed = prior_completed
	if failures == 0:
		print("PASS: tutorial runs on every new game, and Skip hands over a functional auto-equipped bot")
	get_tree().quit(0 if failures == 0 else 1)
