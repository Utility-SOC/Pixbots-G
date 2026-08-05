class_name GaragePaintRack
extends RefCounted

# Paint Rack popup - lets the player pick their hero mech's color from the
# curated Main.PLAYER_PAINT_PALETTE (see Main._setup_player()'s header
# comment: that same list is what a new game/old save rolls a random entry
# from; this popup is what turns "rolled for you" into "your own choice").
# Follows the same composed-RefCounted-helper pattern as GarageMarket.gd/
# GarageShop.gd - lazily constructed the first time the button is pressed,
# see GarageMenu's thin wrapper below.

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func open_popup():
	var main = garage.get_parent()
	# Object.get() only reflects declared vars, not consts - PLAYER_PAINT_PALETTE
	# is a const, so it can't be checked this way (would always read null and
	# make this a permanent no-op). "player" is a real var, so checking that is
	# enough to confirm main is genuinely Main before touching the const below.
	if not main or main.get("player") == null:
		return
	var player = main.player

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "PAINT RACK"
	title.modulate = Color(0.9, 0.8, 0.3)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Pick your mech's color. Free, and you can change it any time."
	subtitle.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(subtitle)

	var grid = GridContainer.new()
	grid.columns = 5
	vbox.add_child(grid)

	for color in main.PLAYER_PAINT_PALETTE:
		var swatch = Button.new()
		swatch.custom_minimum_size = Vector2(56, 56)
		swatch.tooltip_text = color.to_html(false).to_upper()

		var style = StyleBoxFlat.new()
		style.bg_color = color
		var is_current = player.paint_color.a > 0.0 and player.paint_color.is_equal_approx(color)
		# Gold border on whichever swatch matches the mech's current paint -
		# same "which one is active" signal the rarity-bordered inventory
		# cards elsewhere in the Garage already use (GarageInventoryPanel.gd).
		style.border_width_left = 4 if is_current else 1
		style.border_width_right = 4 if is_current else 1
		style.border_width_top = 4 if is_current else 1
		style.border_width_bottom = 4 if is_current else 1
		style.border_color = Color(0.9, 0.8, 0.3) if is_current else Color(0, 0, 0, 0.6)
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.add_theme_stylebox_override("pressed", style)

		swatch.pressed.connect(func():
			main.player_paint_color = color.to_html(false)
			player.paint_color = color
			player.refresh_visuals()
			garage._show_scrap_float("Paint applied!", color)
			popup.hide()
			garage._open_paint_rack()
		)
		grid.add_child(swatch)

	garage.add_child(popup)
	popup.popup_centered(Vector2(360, 200))
	popup.popup_hide.connect(func(): popup.queue_free())
