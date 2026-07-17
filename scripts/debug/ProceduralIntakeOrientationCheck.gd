extends Node

# Regression harness for the Energy Intake orientation fix's missed spots:
# EnergyIntakeOrientationCheck.gd already proved ComponentEquipment's own 12
# create_starter_*/create_*_backpack call sites orient correctly, but 3 more
# Energy Intake creation sites existed outside that file - loot drops
# (LootManager._create_procedural_component), Black Market purchases
# (GarageMarket._build_component), and shop-generated filler components
# (GarageShop._build_generated_component) - none of which ever got the fix.
# Procedural shapes (generate_procedural_shape() + random expansion hexes)
# are irregular enough that direction 0 (East) missing from the shape is
# common, not a corner case - these were live, player-facing instances of
# the exact "energy won't route" bug, likely on any loot-dropped or
# purchased limb, not just starter parts.

const LootManagerScript = preload("res://scripts/core/LootManager.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageMarketScript = preload("res://scripts/ui/GarageMarket.gd")
const GarageShopScript = preload("res://scripts/ui/GarageShop.gd")

var failures = 0

func _fail(msg: String):
	push_error("FAIL: " + msg)
	failures += 1

func _check_intake(component, label: String):
	if not component:
		_fail("%s: no component returned" % label)
		return
	var intake = component.hex_grid.get_tile(HexCoord.new(0, 0))
	if not intake or intake.tile_type != "Energy Intake":
		_fail("%s: no Energy Intake tile found at (0,0)" % label)
		return
	if intake.active_faces.is_empty():
		_fail("%s: intake.active_faces is empty" % label)
		return
	for d in intake.active_faces:
		var n = HexCoord.new(0, 0).neighbor(d)
		var found = false
		for h in component.valid_hexes:
			if h.equals(n):
				found = true
				break
		if not found:
			_fail("%s: active_face direction %d points off the shape" % [label, d])
			return
	print("ok: %s intake active_faces=%s all point at real shape hexes" % [label, str(intake.active_faces)])

func _ready():
	# --- LootManager: procedural loot-drop components, several trials since
	# generate_procedural_shape() is randomized each call. ---
	var loot_mgr = LootManagerScript.new()
	add_child(loot_mgr)
	var fake_mech = Node.new()
	fake_mech.set("combat_role", "brawler")
	add_child(fake_mech)
	for i in range(8):
		var pack = loot_mgr._create_procedural_component(HexTile.Rarity.RARE, fake_mech, "Salvage")
		if pack.slot_type != HexTile.BodySlot.TORSO: # Torso gets a Core, not an intake
			_check_intake(pack, "LootManager drop #%d (slot %d)" % [i, pack.slot_type])

	# --- GarageMarket: Black Market oversized component ---
	var garage = GarageMenuScript.new()
	add_child(garage)
	var market = GarageMarketScript.new(garage)
	var offer = {
		"slot": HexTile.BodySlot.ARM_L,
		"slot_name": "Left Arm",
		"rarity": HexTile.Rarity.RARE,
		"forbidden": [],
		"extra": 6,
		"seed": 12345,
	}
	var market_comp = market._build_component(offer)
	_check_intake(market_comp, "GarageMarket Black Market L. Arm")

	# --- GarageShop: generated filler component ---
	var shop = GarageShopScript.new(garage)
	var shop_comp = shop._build_generated_component(HexTile.BodySlot.LEG_R, "sniper", HexTile.Rarity.UNCOMMON)
	_check_intake(shop_comp, "GarageShop generated R. Leg")

	if failures == 0:
		print("PASS: procedural/purchased components orient their Energy Intake correctly")
	get_tree().quit(0 if failures == 0 else 1)
