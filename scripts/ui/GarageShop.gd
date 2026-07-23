class_name GarageShop
extends RefCounted

const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")

# Scrap Shop (Utility-SOC: "a store where you can use massive amounts of
# scrap to buy prebuilts, components, and kits from the shop") - three
# sections: full prebuilt bots, individual components, and rare/Mythic
# tiles. Deliberately SEPARATE from the Black Market (GarageMarket.gd):
# always the same catalog available (not time-rotated), no forbidden-tile
# drawbacks, and each slot re-rolls a fresh replacement immediately after
# purchase rather than staying permanently [SOLD] until the next rotation.
# Same composed-RefCounted-helper pattern and build-then-pay purchase
# discipline as GarageMarket.gd (construct the item first, only deduct
# scrap on success).
#
# The "full bots" section is the intentional payoff link to the captured-
# enemy-loadout system (SquadDirector.captured_loadouts, see
# _maybe_capture_loadout): it prefers offering an actual captured
# high-fitness enemy build over a generated one, once you've earned it -
# "buy the build that killed you."

# Untyped (not `: GarageMenu`) so a lightweight duck-typed test double can
# stand in for the real (heavy) GarageMenu in headless tests - GarageShop
# only ever calls a handful of methods on it (_show_scrap_float,
# _refresh_inventory_ui, _slot_display_name, .inventory, add_child/
# get_children), same reasoning HexTile._fire_combined_projectile's
# untyped `mech` param already uses.
var garage
var _bot_offers: Array = []
var _component_offers: Array = []
var _tile_offers: Array = []

# Backpack deliberately excluded from the loose component catalog (more
# specialized/utility slot - a future "kit" candidate rather than a base
# offering) but still included when assembling a FULL bot below, since a
# real deployable mech needs one.
const SHOP_COMPONENT_SLOTS = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD]
const BOT_BODY_SLOTS = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]
const BOT_ROLES = ["sniper", "brawler", "flamethrower"]

# Pricing deliberately well above every existing spend site (Black Market's
# Mythic component tops out at 8,000 scrap, rarity tier-up at 10,000) -
# "massive amounts of scrap" per the request.
const COMPONENT_PRICE = 14000
const BOT_PRICE_BY_RARITY = {HexTile.Rarity.LEGENDARY: 45000, HexTile.Rarity.MYTHIC: 75000}
const SPECIAL_TILE_PRICE = 4000
const COMPONENT_RARITY = HexTile.Rarity.LEGENDARY

# Curated - biased toward tiles with a real drop-rate problem rather than
# an arbitrary "one of everything" grab-bag.
const SPECIAL_TILE_SCRIPTS = [
	"res://scripts/tiles/ResonatorTile.gd",
	"res://scripts/tiles/ManeuveringThrusterTile.gd",
	"res://scripts/tiles/DroneBayTile.gd",
	"res://scripts/tiles/JammerModuleTile.gd",
	"res://scripts/tiles/ReverseAccumulatorTile.gd", # new tile, zero drop rate anywhere else yet
]

func _init(p_garage):
	garage = p_garage

func _get_live_director(main):
	if main and "world" in main and main.world:
		return main.world.get_node_or_null("SquadDirector")
	return null

func open_popup():
	var main = garage.get_parent()
	if not main or main.get("player_scrap") == null:
		return

	if _bot_offers.is_empty():
		_generate_bot_offers(main)
	if _component_offers.is_empty():
		_generate_component_offers()
	if _tile_offers.is_empty():
		_generate_tile_offers()

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "SHOP - spend scrap on the good stuff. Always in stock."
	title.modulate = Color(0.4, 0.9, 1.0)
	vbox.add_child(title)

	var bot_header = Label.new()
	bot_header.text = "FULL BOTS"
	bot_header.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(bot_header)
	for i in range(_bot_offers.size()):
		_add_bot_row(vbox, main, i)

	var comp_header = Label.new()
	comp_header.text = "COMPONENTS"
	comp_header.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(comp_header)
	for i in range(_component_offers.size()):
		_add_component_row(vbox, main, i)

	var tile_header = Label.new()
	tile_header.text = "SPECIAL TILES"
	tile_header.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(tile_header)
	for i in range(_tile_offers.size()):
		_add_tile_row(vbox, main, i)

	garage.add_child(popup)
	popup.popup_centered(Vector2(620, 480))
	popup.popup_hide.connect(func(): popup.queue_free())

# --- Full bots ---------------------------------------------------------

func _generate_bot_offers(main):
	var director = _get_live_director(main)
	var chosen_roles: Array = []
	if director and "captured_loadouts" in director:
		var captured_roles = director.captured_loadouts.keys()
		captured_roles.sort_custom(func(a, b): return float(director.captured_loadouts[a].fitness) > float(director.captured_loadouts[b].fitness))
		for r in captured_roles:
			if chosen_roles.size() >= 3:
				break
			chosen_roles.append(r)
	var filler_idx = 0
	while chosen_roles.size() < 3:
		var r = BOT_ROLES[filler_idx % BOT_ROLES.size()]
		filler_idx += 1
		if not chosen_roles.has(r):
			chosen_roles.append(r)

	_bot_offers.clear()
	for role in chosen_roles:
		_bot_offers.append(_make_bot_offer(role, director))

func _make_bot_offer(role: String, director) -> Dictionary:
	if director and "captured_loadouts" in director and director.captured_loadouts.has(role):
		var cap = director.captured_loadouts[role]
		var rarity = int(cap.get("rarity", HexTile.Rarity.LEGENDARY))
		return {
			"role": role, "source": "captured", "fitness": float(cap.get("fitness", 0.0)),
			"rarity": rarity, "components": cap.get("components", {}),
			"price": BOT_PRICE_BY_RARITY.get(rarity, BOT_PRICE_BY_RARITY[HexTile.Rarity.LEGENDARY]),
		}

	var rarity = HexTile.Rarity.LEGENDARY
	var serialized: Dictionary = {}
	for slot in BOT_BODY_SLOTS:
		var comp = _build_generated_component(slot, role, rarity)
		serialized[slot] = SaveManager._serialize_component(comp)
	return {
		"role": role, "source": "generated", "fitness": 0.0,
		"rarity": rarity, "components": serialized,
		"price": BOT_PRICE_BY_RARITY[rarity],
	}

func _add_bot_row(vbox: VBoxContainer, main, i: int):
	var offer = _bot_offers[i]
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var tag = "CAPTURED (fitness %.0f)" % offer.fitness if offer.source == "captured" else "workshop build"
	var btn = Button.new()
	btn.text = "%s %s [%s]  |  %d scrap" % [rarity_names[offer.rarity], str(offer.role).capitalize(), tag, offer.price]
	if offer.source == "captured":
		btn.tooltip_text = "The actual tile-by-tile layout of the best %s enemy you've faced." % offer.role
	btn.pressed.connect(func():
		if purchase_bot(i, main):
			_reopen(main)
	)
	vbox.add_child(btn)

# Returns true on a successful purchase (scrap deducted, components
# delivered, offer re-rolled) - false and no side effects on insufficient
# scrap or a failed build. Split out from _add_bot_row's button closure so
# the purchase flow itself is directly unit-testable without driving a real
# Button click.
func purchase_bot(i: int, main) -> bool:
	var offer = _bot_offers[i]
	if main.player_scrap < offer.price:
		garage._show_scrap_float("Need " + str(offer.price) + " scrap", Color(0.9, 0.4, 0.3))
		return false
	var built: Array = []
	for slot in offer.components:
		var comp = SaveManager._deserialize_component(offer.components[slot])
		if comp:
			built.append(comp)
	if built.is_empty():
		garage._show_scrap_float("Purchase failed - no scrap taken, try again", Color(0.9, 0.4, 0.3))
		return false
	main.player_scrap -= offer.price
	for comp in built:
		main.player_component_inventory.append(comp)
	garage._refresh_inventory_ui()
	garage._show_scrap_float("%d components delivered to spare parts" % built.size(), Color(0.4, 0.9, 1.0))
	_bot_offers[i] = _make_bot_offer(offer.role, _get_live_director(main))
	return true

# --- Components ----------------------------------------------------------

func _generate_component_offers():
	_component_offers.clear()
	for slot in SHOP_COMPONENT_SLOTS:
		_component_offers.append(_make_component_offer(slot))

func _make_component_offer(slot: int) -> Dictionary:
	var role = BOT_ROLES[randi() % BOT_ROLES.size()]
	var comp = _build_generated_component(slot, role, COMPONENT_RARITY)
	return {"slot": slot, "role": role, "rarity": COMPONENT_RARITY, "price": COMPONENT_PRICE, "component": comp}

func _add_component_row(vbox: VBoxContainer, main, i: int):
	var offer = _component_offers[i]
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var btn = Button.new()
	btn.text = "%s %s (%s doctrine)  |  %d scrap" % [rarity_names[offer.rarity], garage._slot_display_name(offer.slot), str(offer.role).capitalize(), offer.price]
	btn.pressed.connect(func():
		if purchase_component(i, main):
			_reopen(main)
	)
	vbox.add_child(btn)

func purchase_component(i: int, main) -> bool:
	var offer = _component_offers[i]
	if main.player_scrap < offer.price:
		garage._show_scrap_float("Need " + str(offer.price) + " scrap", Color(0.9, 0.4, 0.3))
		return false
	main.player_scrap -= offer.price
	main.player_component_inventory.append(offer.component)
	garage._refresh_inventory_ui()
	garage._show_scrap_float("Delivered to spare parts", Color(0.4, 0.9, 1.0))
	_component_offers[i] = _make_component_offer(offer.slot)
	return true

# --- Special tiles ---------------------------------------------------------

func _generate_tile_offers():
	_tile_offers.clear()
	for script_path in SPECIAL_TILE_SCRIPTS:
		_tile_offers.append(_make_tile_offer(script_path))

func _make_tile_offer(script_path: String) -> Dictionary:
	var tile = load(script_path).new()
	tile.rarity = HexTile.Rarity.MYTHIC
	return {"script_path": script_path, "tile": tile, "price": SPECIAL_TILE_PRICE}

func _add_tile_row(vbox: VBoxContainer, main, i: int):
	var offer = _tile_offers[i]
	var btn = Button.new()
	btn.text = "Mythic %s  |  %d scrap" % [offer.tile.tile_type, offer.price]
	btn.pressed.connect(func():
		if purchase_tile(i, main):
			_reopen(main)
	)
	vbox.add_child(btn)

func purchase_tile(i: int, main) -> bool:
	var offer = _tile_offers[i]
	if main.player_scrap < offer.price:
		garage._show_scrap_float("Need " + str(offer.price) + " scrap", Color(0.9, 0.4, 0.3))
		return false
	main.player_scrap -= offer.price
	garage.inventory.append(offer.tile)
	TileDiscoveryPopup.announce_if_new(offer.tile)
	garage._refresh_inventory_ui()
	garage._show_scrap_float("Delivered to tile inventory", Color(0.4, 0.9, 1.0))
	_tile_offers[i] = _make_tile_offer(offer.script_path)
	return true

# --- Shared component-building helper --------------------------------------

# Simpler than the real enemy-spawn pipeline (SquadDirector/Mech.build_
# loadout_for_role, which assumes a live combat mech) - reuses
# ComponentEquipment.generate_procedural_shape() the same way GarageMarket's
# Black Market components already do, then drops in a small role-flavored
# tile set. Good enough for "generated filler when no captured loadout
# exists yet" - the captured-loadout path is the one meant to carry real
# weight long-term.
func _build_generated_component(slot: int, role: String, rarity: int) -> ComponentEquipment:
	var comp = ComponentEquipment.new(slot, rarity)
	comp.generate_procedural_shape()

	if slot == HexTile.BodySlot.TORSO:
		comp.hex_grid.add_tile(HexCoord.new(0, 0), load("res://scripts/tiles/CoreTile.gd").new())
	elif slot == HexTile.BodySlot.BACKPACK:
		return ComponentEquipment.create_starter_backpack(role, rarity)
	else:
		var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
		intake.tile_type = "Energy Intake"
		intake.body_slot = slot
		comp.hex_grid.add_tile(HexCoord.new(0, 0), intake)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
		ComponentEquipment._orient_intake_to_shape(comp, intake)

	for spec in _role_tile_specs(role, slot):
		var free_hex = _first_free_hex(comp)
		if free_hex == null:
			break
		var tile = load(spec.path).new()
		tile.rarity = rarity
		if spec.has("synergy") and "secondary_synergy" in tile:
			tile.secondary_synergy = spec.synergy
		comp.hex_grid.add_tile(free_hex, tile)
	return comp

func _first_free_hex(comp) -> HexCoord:
	for h in comp.valid_hexes:
		if not comp.hex_grid.has_tile(h):
			return h
	return null

func _role_tile_specs(role: String, slot: int) -> Array:
	if slot == HexTile.BodySlot.ARM_L or slot == HexTile.BodySlot.ARM_R:
		match role:
			"sniper":
				return [{"path": "res://scripts/tiles/AmplifierTile.gd"}, {"path": "res://scripts/tiles/WeaponMountTile.gd"}]
			"flamethrower":
				return [{"path": "res://scripts/tiles/InfuserTile.gd", "synergy": EnergyPacket.SynergyType.FIRE}, {"path": "res://scripts/tiles/WeaponMountTile.gd"}]
			_:
				return [{"path": "res://scripts/tiles/SplitterTile.gd"}, {"path": "res://scripts/tiles/WeaponMountTile.gd"}]
	elif slot == HexTile.BodySlot.LEG_L or slot == HexTile.BodySlot.LEG_R:
		return [{"path": "res://scripts/tiles/JumpjetTile.gd"}]
	elif slot == HexTile.BodySlot.HEAD:
		return [{"path": "res://scripts/tiles/DirectionalConduitTile.gd"}]
	return [] # TORSO just gets the Core

func _reopen(main):
	# Simplest way to reflect a re-rolled offer in the UI - close and rebuild
	# the popup fresh rather than patching individual button labels in place.
	for c in garage.get_children():
		if c is PopupPanel and c.visible:
			c.hide()
	open_popup()
