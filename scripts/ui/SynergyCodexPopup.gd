class_name SynergyCodexPopup
extends RefCounted

# Player-facing reference for what the 9 elemental synergies actually do -
# previously that knowledge only existed scattered across Projectile.gd's
# per-synergy branches (chain lightning, burning/frozen status, the shield
# counter-wheel, etc.) with zero in-game explanation. Colors are pulled
# straight from EnergyPacket.get_color_for_synergy so the codex always
# matches the actual projectile/tile tinting, and descriptions are a plain-
# language summary of the real mechanics (not aspirational/simplified).
#
# Split out of GarageMenu.gd, see SightAndSearch.gd/MagnetSystem.gd for the
# established composed-RefCounted-helper pattern this follows. Lazily
# constructed the first time the Codex button is pressed (see
# GarageMenu._on_codex_pressed's wrapper, which keeps a thin wrapper on
# GarageMenu since it's connected directly as a Callable via
# codex_btn.pressed.connect(_on_codex_pressed) in _setup_ui).

const SYNERGY_CODEX_ENTRIES = [
	{"id": 0, "name": "RAW", "desc": "The baseline element - no special interactions, no counters. Always the fallback when no synergy dominates a shot."},
	{"id": 1, "name": "FIRE", "desc": "Applies a burning damage-over-time status on hit. Shots run a short lifetime (fast, close-range feel). Deals 2x against Ice shields; takes 2x from Ice shields in return."},
	{"id": 2, "name": "ICE", "desc": "Applies a frozen/slow status on hit, fighting back against Kinetic-heavy builds' mobility. Deals 2x against Fire shields; takes 2x from Fire shields in return."},
	{"id": 3, "name": "LIGHTNING", "desc": "Arcs instantly between nearby enemies (chain lightning) instead of traveling as a single bolt. Always deals 1.5x against ANY shield, on top of the normal counter-wheel bonus vs Kinetic shields."},
	{"id": 4, "name": "VORTEX", "desc": "Pulls in nearby loot and (weakly) enemies/player toward the impact point - a battlefield-control element as much as a damage one. Deals 2x against Kinetic shields."},
	{"id": 5, "name": "POISON", "desc": "Stacks a damage-over-time poison effect that can stack multiple times. Deals 2x against Vampiric shields; takes 2x from Vampiric shields in return."},
	{"id": 6, "name": "EXPLOSION", "desc": "Detonates in an area-of-effect blast on impact instead of a single-target hit - radius scales with the synergy's ratio in the shot and any Amplifier AoE bonus."},
	{"id": 7, "name": "KINETIC", "desc": "Massively extends weapon range (triple at full ratio) and keeps a locked, unwavering straight trajectory - plus knockback-heavy hits, pure mass-behind-the-shot damage. Deals 2x against Lightning shields; takes 2x from Lightning shields in return."},
	{"id": 8, "name": "PIERCE", "desc": "High-velocity, armor-piercing rounds - ignores a flat share of armor/shield mitigation on every hit, and any PIERCE hit that gets past shields has a small flat chance to instantly execute the target outright - regardless of remaining HP. Bosses, Commanders, and Piercing Jammers (plus anyone standing in a Piercing Jammer's aura) are immune to that execution."},
	{"id": 9, "name": "VAMPIRIC", "desc": "Heals the attacker for a share of the damage dealt (lifesteal). Deals 2x against Poison shields; takes 2x from Poison shields in return."},
]

var garage: GarageMenu
var _popup: PopupPanel = null

func _init(p_garage: GarageMenu):
	garage = p_garage

func show_popup():
	if not _popup:
		_popup = _build_popup()
		garage.add_child(_popup)
	_popup.popup_centered(Vector2(460, 520))

func _build_popup() -> PopupPanel:
	var popup = PopupPanel.new()
	popup.title = "Synergy Codex"

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 500)
	popup.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header = Label.new()
	header.text = "How each element behaves - shield bonuses are always mutual (both directions apply)."
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	for entry in SYNERGY_CODEX_ENTRIES:
		var row = HBoxContainer.new()
		vbox.add_child(row)

		var swatch = ColorRect.new()
		swatch.color = EnergyPacket.get_color_for_synergy(entry.id)
		swatch.custom_minimum_size = Vector2(16, 16)
		row.add_child(swatch)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_vbox)

		var name_label = Label.new()
		name_label.text = entry.name
		name_label.add_theme_color_override("font_color", EnergyPacket.get_color_for_synergy(entry.id))
		text_vbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = entry.desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(390, 0)
		text_vbox.add_child(desc_label)

		vbox.add_child(HSeparator.new())

	return popup
