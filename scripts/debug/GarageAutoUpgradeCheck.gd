extends Node

# Regression harness for the Garage's "Auto-Upgrade" button (user request,
# 2026-08-13: "a button in the garage that automatically upgrades any hex
# tiles with the highest rarity available - starting at the core then
# clockwise for the torso, or the energy intakes and clockwise for all
# other components"). Covers GarageMenu._on_auto_upgrade_pressed and its
# helpers (_auto_upgrade_component/_find_best_upgrade_index/
# _clock_angle_from_origin/_hex_axial_to_screen).
#
# Same safe construction pattern GarageEditFixCheck.gd already established
# for standalone GarageMenu testing: real GarageMenu/ComponentEquipment
# instances, no SquadDirector, no save/load.

const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_amp(rarity: int) -> HexTile:
	var t = AmplifierTileScript.new()
	t.rarity = rarity
	return t

func _ready():
	var world = Node2D.new()
	add_child(world)
	var garage = GarageMenuScript.new()
	world.add_child(garage)

	# --- 1: clock-angle ordering, verified against all 6 hex directions
	# (see this check's own header for the derivation) - the hub (0,0)
	# always sorts first, then NE < E < SE < SW < W < NW clockwise. ------
	var origin = HexCoord.new(0, 0)
	var dir_ne = origin.neighbor(5)
	var dir_e = origin.neighbor(0)
	var dir_se = origin.neighbor(1)
	var dir_sw = origin.neighbor(2)
	var dir_w = origin.neighbor(3)
	var dir_nw = origin.neighbor(4)

	_check("the hub (0,0) sorts before every real direction (angle -1.0)",
		garage._clock_angle_from_origin(origin) < garage._clock_angle_from_origin(dir_ne))
	_check("North-East sorts before East (both in the upper-right quarter, NE closer to 12 o'clock)",
		garage._clock_angle_from_origin(dir_ne) < garage._clock_angle_from_origin(dir_e))
	_check("East sorts before South-East",
		garage._clock_angle_from_origin(dir_e) < garage._clock_angle_from_origin(dir_se))
	_check("South-East sorts before South-West",
		garage._clock_angle_from_origin(dir_se) < garage._clock_angle_from_origin(dir_sw))
	_check("South-West sorts before West",
		garage._clock_angle_from_origin(dir_sw) < garage._clock_angle_from_origin(dir_w))
	_check("West sorts before North-West (closing the clockwise loop back toward 12 o'clock)",
		garage._clock_angle_from_origin(dir_w) < garage._clock_angle_from_origin(dir_nw))

	# --- 2: functional upgrade, greedy-best-available-first, in walk order -
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	world.add_child(torso)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	torso.hex_grid.add_tile(origin, core)

	var amp_ne = _make_amp(HexTile.Rarity.COMMON)
	var amp_e = _make_amp(HexTile.Rarity.COMMON)
	var amp_w = _make_amp(HexTile.Rarity.COMMON)
	torso.hex_grid.add_tile(dir_ne, amp_ne)
	torso.hex_grid.add_tile(dir_e, amp_e)
	torso.hex_grid.add_tile(dir_w, amp_w)

	var spare_mythic = _make_amp(HexTile.Rarity.MYTHIC)
	var spare_rare = _make_amp(HexTile.Rarity.RARE)
	garage.active_component = torso
	garage.mech_components = {HexTile.BodySlot.TORSO: torso}
	garage.grid_renderer.setup(torso.hex_grid, garage, torso.valid_hexes)
	garage.inventory = [spare_mythic, spare_rare]

	garage._on_auto_upgrade_pressed()

	var now_at_ne = torso.hex_grid.get_tile(dir_ne)
	var now_at_e = torso.hex_grid.get_tile(dir_e)
	var now_at_w = torso.hex_grid.get_tile(dir_w)
	_check("the FIRST tile in clockwise walk order (NE) got the single best spare (Mythic)",
		now_at_ne != null and now_at_ne.rarity == HexTile.Rarity.MYTHIC)
	_check("the SECOND tile in walk order (E) got the next-best remaining spare (Rare) once Mythic was already spent",
		now_at_e != null and now_at_e.rarity == HexTile.Rarity.RARE)
	_check("the THIRD tile (W) stayed Common - no spares left by the time the walk reached it",
		now_at_w != null and now_at_w.rarity == HexTile.Rarity.COMMON and now_at_w == amp_w)
	_check("both consumed spares left inventory",
		not garage.inventory.has(spare_mythic) and not garage.inventory.has(spare_rare))
	_check("the two replaced Common tiles came back to inventory",
		garage.inventory.has(amp_ne) and garage.inventory.has(amp_e))
	_check("inventory settled at exactly 2 tiles (2 replaced out, 2 old ones back in - a like-for-like swap, not a net gain/loss)",
		garage.inventory.size() == 2)

	# --- 3: a tile with nothing better available in inventory is left
	# completely untouched, and doesn't consume anything -------------------
	garage.inventory = [_make_amp(HexTile.Rarity.COMMON)] # same rarity as what's equipped - not an upgrade
	var before_w = torso.hex_grid.get_tile(dir_w)
	garage._on_auto_upgrade_pressed()
	var after_w = torso.hex_grid.get_tile(dir_w)
	_check("a tile with no strictly-better spare in inventory is left as the exact same instance",
		after_w == before_w)
	_check("a same-rarity duplicate in inventory is NOT treated as an upgrade and is left untouched",
		garage.inventory.size() == 1)

	# --- 4: routing config (active_faces) survives the swap, same as
	# fill-line placement's own copy_config_from behavior -------------------
	var splitter_slot = origin.neighbor(1) # South-East, currently empty
	var old_splitter = SplitterTileScript.new()
	old_splitter.rarity = HexTile.Rarity.COMMON
	var custom_faces: Array[int] = [0, 3]
	old_splitter.active_faces = custom_faces
	torso.hex_grid.add_tile(splitter_slot, old_splitter)
	var new_splitter = SplitterTileScript.new()
	new_splitter.rarity = HexTile.Rarity.LEGENDARY
	garage.inventory = [new_splitter]
	garage._on_auto_upgrade_pressed()
	var placed_splitter = torso.hex_grid.get_tile(splitter_slot)
	_check("the upgraded replacement inherited the old tile's routing config (active_faces) via copy_config_from",
		placed_splitter != null and placed_splitter.rarity == HexTile.Rarity.LEGENDARY and placed_splitter.active_faces == custom_faces)

	# --- 5: multi-component - Torso is processed before other slots, so a
	# single scarce spare goes to the Torso's own tile first ----------------
	var arm = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.RARE)
	world.add_child(arm)
	arm.generate_shape()
	var arm_amp = _make_amp(HexTile.Rarity.COMMON)
	arm.hex_grid.add_tile(HexCoord.new(1, 0), arm_amp)
	torso.hex_grid.remove_tile(dir_ne) # reset to a clean single-candidate scenario
	var torso_amp = _make_amp(HexTile.Rarity.COMMON)
	torso.hex_grid.add_tile(dir_ne, torso_amp)

	garage.mech_components = {HexTile.BodySlot.TORSO: torso, HexTile.BodySlot.ARM_L: arm}
	garage.inventory = [_make_amp(HexTile.Rarity.MYTHIC)] # exactly one spare for two candidates
	garage._on_auto_upgrade_pressed()

	var torso_tile_now = torso.hex_grid.get_tile(dir_ne)
	var arm_tile_now = arm.hex_grid.get_tile(HexCoord.new(1, 0))
	_check("with only one spare available across the whole mech, the Torso's own tile wins it (Torso processed first)",
		torso_tile_now != null and torso_tile_now.rarity == HexTile.Rarity.MYTHIC)
	_check("the Arm's matching tile stayed at its original rarity - nothing left for it",
		arm_tile_now != null and arm_tile_now.rarity == HexTile.Rarity.COMMON)

	if failures == 0:
		print("PASS: Auto-Upgrade walks every component clockwise from its Core/Energy Intake hub, greedily consumes the best available same-type spare per tile, preserves routing config across the swap, and leaves untouched tiles/inventory alone when nothing better is available")
	get_tree().quit(0 if failures == 0 else 1)
