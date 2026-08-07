class_name GarageSponsorPopup
extends RefCounted

# Sponsor selection popup (the user: "a menu that pops up when you enter the
# garage after 125 showing you the options... two columns of banners, each
# with the company name and thematic coloring/and pattern.") Follows the
# same composed-RefCounted-helper pattern as GaragePaintRack.gd - lazily
# constructed, holds a garage: GarageMenu reference. Real logo art deferred
# (see BrandRegistry.gd), so each banner's "art" is its accent color plus a
# small procedural pattern (GarageSponsorPatternDraw.gd).
#
# Two entry points: auto-shown once by GarageMenu._ready() when
# max_wave_reached >= 125 and SaveManager.sponsor_popup_shown is still
# false (see that flag's own comment), and a permanent manual re-open via
# the SPONSOR button in the Garage bottom bar (GarageUIBuilder.gd) so the
# choice stays changeable later, same "free, no penalty" framing the Paint
# Rack already uses.

const GarageSponsorPatternDraw = preload("res://scripts/ui/GarageSponsorPatternDraw.gd")

var garage: GarageMenu

func _init(p_garage: GarageMenu):
	garage = p_garage

func open_popup():
	var main = garage.get_parent()
	if not main or main.get("player_sponsorship") == null:
		return

	# One-shot: whether the player picks, declines, or just closes this,
	# it never auto-pops again (the user: "not hit on every level up if
	# the player declines").
	SaveManager.sponsor_popup_shown = true

	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(640, 0)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "CORPORATE SPONSORSHIP"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.9, 0.8, 0.3)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Pick a sponsor to bias your loot drops toward their gear. Free, no penalty, and you can switch any time from the bottom bar."
	subtitle.modulate = Color(0.75, 0.75, 0.75)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(620, 0)
	vbox.add_child(subtitle)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	var current = str(main.player_sponsorship)
	for brand_id in BrandRegistry.BRAND_IDS:
		grid.add_child(_make_banner(main, brand_id, current == brand_id, popup))

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer2)

	var free_agent_btn = Button.new()
	free_agent_btn.custom_minimum_size = Vector2(0, 44)
	free_agent_btn.text = "FREE AGENT (No Sponsorship)" + ("  [CURRENT]" if current == "" else "")
	free_agent_btn.pressed.connect(func():
		main.player_sponsorship = ""
		garage._show_scrap_float("No sponsorship - free agent", Color(0.8, 0.8, 0.8))
		popup.hide()
	)
	vbox.add_child(free_agent_btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): popup.hide())
	vbox.add_child(close_btn)

	garage.add_child(popup)
	popup.popup_centered(Vector2(680, 560))
	popup.popup_hide.connect(func(): popup.queue_free())

func _make_banner(main: Node, brand_id: String, is_current: bool, popup: PopupPanel) -> Control:
	var accent = BrandRegistry.accent_color(brand_id)

	var banner = Button.new()
	banner.custom_minimum_size = Vector2(300, 110)
	banner.clip_text = true

	var style = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 1.0)
	style.border_width_left = 4 if is_current else 2
	style.border_width_right = 4 if is_current else 2
	style.border_width_top = 4 if is_current else 2
	style.border_width_bottom = 4 if is_current else 2
	style.border_color = Color(0.9, 0.8, 0.3) if is_current else accent
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	banner.add_theme_stylebox_override("normal", style)
	banner.add_theme_stylebox_override("hover", style)
	banner.add_theme_stylebox_override("pressed", style)

	# Pattern backdrop, drawn behind the label overlay below - mouse_filter
	# IGNORE so clicks pass through to the Button underneath it.
	var pattern = GarageSponsorPatternDraw.new()
	pattern.pattern_id = BrandRegistry.pattern_id(brand_id)
	pattern.pattern_color = Color(accent.r, accent.g, accent.b, 0.3)
	pattern.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(pattern)

	var overlay = VBoxContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(overlay)

	var name_lbl = Label.new()
	name_lbl.text = BrandRegistry.display_name(brand_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", accent)
	overlay.add_child(name_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = ("CURRENT SPONSOR" if is_current else "Select")
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.modulate = Color(0.9, 0.8, 0.3) if is_current else Color(0.75, 0.75, 0.75)
	overlay.add_child(sub_lbl)

	banner.pressed.connect(func():
		main.player_sponsorship = brand_id
		garage._show_scrap_float("Sponsored by " + BrandRegistry.display_name(brand_id), accent)
		popup.hide()
	)

	return banner
