class_name GarageMarket
extends RefCounted

const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")

# Black Market popup + sell-all - split out of GarageMenu.gd, see
# SightAndSearch.gd/MagnetSystem.gd for the established composed-RefCounted-
# helper pattern this follows. All state (inventory, _market_sold) and the
# shared SLOT_DISPLAY_NAMES/_slot_display_name/tile_scrap_value utilities
# stay on GarageMenu itself (the latter two are used well outside the Black
# Market - equip popups, tile scrap/upgrade costs) - only the Market-specific
# behavior moved here. Lazily constructed the first time the Market or a
# Sell button is pressed (see GarageMenu's thin wrappers below).
#
# _open_black_market/_on_sell_all keep thin wrappers on GarageMenu (not
# moved) - they're connected directly as Callables
# (market_btn.pressed.connect(_open_black_market),
# sell_c_btn.pressed.connect(_on_sell_all.bind(0)), etc.) in _setup_ui, so
# they have to be reachable as plain GarageMenu-level methods regardless.

const MARKET_CYCLE_SECONDS = 600
const MARKET_FORBIDDABLE = ["Amplifier", "Accumulator", "Splitter", "Catalyst", "Shield Generator"]

var garage: GarageMenu
var _market_sold: Dictionary = {}

func _init(p_garage: GarageMenu):
	garage = p_garage

func open_popup():
	var main = garage.get_parent()
	if not main or main.get("player_scrap") == null:
		return
	if main.has_method("show_dialogue"):
		var dm = load("res://scripts/core/DialogueManager.gd").new()
		dm._ready()
		main.show_dialogue("Shopkeeper", dm.get_black_market_quip(), Color(1.0, 0.5, 0.9), 6.0)
	var cycle = int(Time.get_unix_time_from_system()) / MARKET_CYCLE_SECONDS
	var rng = RandomNumberGenerator.new()
	rng.seed = cycle

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "BLACK MARKET - stock rotates in %d s" % (MARKET_CYCLE_SECONDS - int(Time.get_unix_time_from_system()) % MARKET_CYCLE_SECONDS)
	title.modulate = Color(1.0, 0.5, 0.9)
	vbox.add_child(title)

	var slot_names = garage.SLOT_DISPLAY_NAMES
	var rarity_names = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]
	var prices = [0, 0, 1200, 3200, 8000]

	# Market never rolls Backpack - keep that exclusion even though the
	# shared SLOT_DISPLAY_NAMES dict (used for display everywhere else) does
	# include it.
	var market_slots = [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD]

	for i in range(3):
		var roll = rng.randf()
		var rarity = HexTile.Rarity.RARE
		if roll > 0.85: rarity = HexTile.Rarity.MYTHIC
		elif roll > 0.5: rarity = HexTile.Rarity.LEGENDARY
		var slots = market_slots
		var slot = slots[rng.randi() % slots.size()]
		var extra_hexes = 4 + rarity
		var forb_a = MARKET_FORBIDDABLE[rng.randi() % MARKET_FORBIDDABLE.size()]
		var forb_b = MARKET_FORBIDDABLE[rng.randi() % MARKET_FORBIDDABLE.size()]
		var price = prices[rarity]
		var sold_key = "%d_%d" % [cycle, i]

		var offer_btn = Button.new()
		var forb_txt = forb_a if forb_a == forb_b else forb_a + " & " + forb_b
		offer_btn.text = "%s %s  |  +%d extra hexes  |  FORBIDS: %s  |  %d scrap" % [rarity_names[rarity], slot_names[slot], extra_hexes, forb_txt, price]
		offer_btn.disabled = _market_sold.has(sold_key)
		if offer_btn.disabled:
			offer_btn.text += "  [SOLD]"

		# Capture loop state for the purchase lambda
		var offer = {"rarity": rarity, "slot": slot, "slot_name": slot_names[slot], "extra": extra_hexes, "forbidden": [forb_a, forb_b] if forb_a != forb_b else [forb_a], "price": price, "key": sold_key, "seed": cycle * 100 + i}
		offer_btn.pressed.connect(func():
			if main.player_scrap < offer.price:
				garage._show_scrap_float("Need " + str(offer.price) + " scrap", Color(0.9, 0.4, 0.3))
				return
			# Build FIRST, spend/mark-sold only after a successful build.
			# Previously scrap was deducted and _market_sold was flagged
			# BEFORE _build_component() ran - so if that call ever
			# failed partway through (a bad roll producing something the
			# procedural generator choked on), the price was already paid and
			# the offer permanently flagged [SOLD] on every future reopen of
			# this popup, with nothing ever landing in the spare-parts tray to
			# show for it. That silent-loss ordering is exactly what could
			# make "I bought it and it didn't show up" happen even though
			# nothing else about the purchase flow looked wrong. Now a failed
			# build costs nothing and leaves the offer purchasable again.
			var built = _build_component(offer)
			if built == null:
				garage._show_scrap_float("Purchase failed - no scrap taken, try again", Color(0.9, 0.4, 0.3))
				return
			main.player_scrap -= offer.price
			_market_sold[offer.key] = true
			main.player_component_inventory.append(built)
			garage._refresh_inventory_ui()
			offer_btn.disabled = true
			offer_btn.text += "  [SOLD]"
			garage._show_scrap_float("Deal done. No refunds.", Color(1.0, 0.5, 0.9))
		)
		vbox.add_child(offer_btn)

	var warning = Label.new()
	warning.text = "Experimental hardware. Oversized grids, hard restrictions, no refunds."
	warning.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(warning)

	garage.add_child(popup)
	popup.popup_centered(Vector2(640, 220))
	popup.popup_hide.connect(func(): popup.queue_free())

func _build_component(offer: Dictionary):
	var comp = ComponentEquipment.new(offer.slot, offer.rarity)
	# Was "Black Market " + str(offer.slot) - since offer.slot is a raw enum
	# int, that literally showed up as e.g. "Black Market 3" in the spare-parts
	# list and Swap Component popup, making a purchased part unrecognizable
	# (this looked exactly like "the Black Market isn't working" even though
	# the purchase itself succeeded and was equip-compatible).
	comp.component_name = "Black Market " + offer.get("slot_name", garage._slot_display_name(offer.slot))
	comp.forbidden_tile_types = offer.forbidden.duplicate()
	comp.generate_procedural_shape()

	# Oversized: bolt on the extra hexes procedurally (deterministic per offer)
	var rng = RandomNumberGenerator.new()
	rng.seed = offer.seed
	var added = 0
	var guard = 0
	while added < offer.extra and guard < 200:
		guard += 1
		if comp.valid_hexes.is_empty():
			break
		var base = comp.valid_hexes[rng.randi() % comp.valid_hexes.size()]
		var n = HexCoord.new(base.q, base.r).neighbor(rng.randi() % 6)
		if comp.add_expansion_hex(n):
			added += 1

	# Standard entry point so energy can actually route in
	if comp.slot_type != HexTile.BodySlot.TORSO and not comp.hex_grid.has_tile(HexCoord.new(0, 0)):
		var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
		intake.tile_type = "Energy Intake"
		intake.body_slot = comp.slot_type
		comp.hex_grid.add_tile(HexCoord.new(0, 0), intake)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
	return comp

func sell_all(max_rarity: int):
	var main = garage.get_parent()
	if not main or main.get("player_scrap") == null: return
	var to_remove = []
	var total_scrap = 0
	for tile in garage.inventory:
		if tile.rarity <= max_rarity:
			to_remove.append(tile)
			total_scrap += garage.tile_scrap_value(tile)

	for tile in to_remove:
		garage.inventory.erase(tile)

	if total_scrap > 0:
		main.player_scrap += total_scrap
		garage._refresh_inventory_ui()
		var float_lbl = Label.new()
		float_lbl.text = "+" + str(total_scrap) + " Scrap"
		float_lbl.modulate = Color(1.0, 0.8, 0.2)
		float_lbl.global_position = garage.get_viewport().get_mouse_position() - Vector2(20, 20)
		garage.add_child(float_lbl)
		var tw = garage.create_tween()
		tw.tween_property(float_lbl, "global_position:y", float_lbl.global_position.y - 50, 1.0)
		tw.parallel().tween_property(float_lbl, "modulate:a", 0.0, 1.0)
		tw.tween_callback(float_lbl.queue_free)
