class_name CreditsPanel
extends CanvasLayer

# Third-party licensing disclosures, shown in-game (not just in
# DISCLOSURES.md, which players never see) - the actual attribution point
# for Godot Engine (MIT) and godot-rust/gdext (MPL-2.0), matching
# DISCLOSURES.md's own stated obligations. Everything else in this project
# (art, audio, fonts) is procedurally generated at runtime - no bundled
# third-party asset files exist, so there's nothing else to disclose here.

const CREDITS_TEXT = "PIXBOTS-G

Built with Godot Engine
https://godotengine.org/
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
Licensed under the MIT License.

Uses godot-rust (gdext)
https://github.com/godot-rust/gdext
Licensed under the Mozilla Public License 2.0 (MPL-2.0).
Used unmodified as a compiled dependency (rust_ext/) - the game's own
code is not required to be open-sourced. Source for the unmodified
MPL-2.0-covered files is available at the link above.

All gameplay art, music, and sound effects are generated procedurally
at runtime - no third-party asset files are bundled with this game.

See DISCLOSURES.md in the project repository for the full breakdown."

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150 # same layer as SettingsMenu - above everything but the debug menu
	_setup_ui()

func _setup_ui():
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 460)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	bg.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CREDITS & LICENSES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 340)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body = Label.new()
	body.text = CREDITS_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(460, 0)
	scroll.add_child(body)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(0, 40)
	btn_close.pressed.connect(func(): queue_free())
	vbox.add_child(btn_close)
