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

# Each entry: impact/counter identity in `desc`, and the shot's IN-FLIGHT
# behavior in `movement` (the "movement identity" - synergies blend
# proportionally, so a 70/30 mix flies like 70% of one and 30% of the
# other). Movement text mirrors Projectile.gd/projectile_flight.rs - if
# the flight math changes, update this table in the same commit.
const SYNERGY_CODEX_ENTRIES = [
	{"id": 0, "name": "RAW", "desc": "The baseline element - no special interactions, no counters. Always the fallback when no synergy dominates a shot.",
		"movement": "Flies dead straight at base speed. The blank canvas every other element bends."},
	{"id": 1, "name": "FIRE", "desc": "Applies a burning damage-over-time status on hit. Deals 2x against Ice shields; takes 2x from Ice shields in return.",
		"movement": "The Plume: heavy air drag - shots decelerate hard and burn out on a very short lifetime. A close-range burst weapon. Kinetic fights the drag; Pierce cancels it outright."},
	{"id": 2, "name": "ICE", "desc": "Applies a frozen/slow status on hit, fighting back against Kinetic-heavy builds' mobility. Deals 2x against Fire shields; takes 2x from Fire shields in return.",
		"movement": "Heavy crystalline mass: slower shots that RESIST steering - homing, swirl, and course changes all fight its inertia."},
	{"id": 3, "name": "LIGHTNING", "desc": "Always deals 1.5x against ANY shield, on top of the normal counter-wheel bonus vs Kinetic shields. Every victim of every hop takes the shot's FULL on-hit effects.",
		"movement": "Instantaneous travel: the shot BLINK-TELEPORTS toward the nearest target several times a second, covering its lightning-ratio of the distance per hop - full lightning arrives instantly, partial lightning visibly hops closer. On impact it re-targets instead of dying (up to 5 victims at full ratio), and every new leg gets its full range budget back."},
	{"id": 4, "name": "VORTEX", "desc": "Pulls in nearby loot and (weakly) enemies/player toward the impact point - a battlefield-control element as much as a damage one. Deals 2x against Kinetic shields.",
		"movement": "The Swirler: flies in a wide oscillating spiral, dragging a gravity well along its path that tugs nearby units out of formation. Kinetic punches the spiral straighter."},
	{"id": 5, "name": "POISON", "desc": "Stacks a damage-over-time poison effect that can stack multiple times. Deals 2x against Vampiric shields; takes 2x from Vampiric shields in return.",
		"movement": "The Mortar-lob: gravity grabs the shot and it arcs downward, accelerating - fire it upfield like artillery. Kinetic flattens the arc. At heavy poison ratios the shot becomes a MINE: it sits (or crawls, with kinetic) where fired and detonates on contact or expiry."},
	{"id": 6, "name": "EXPLOSION", "desc": "Detonates in an area-of-effect blast on impact instead of a single-target hit - radius scales with the synergy's ratio in the shot and any Amplifier AoE bonus.",
		"movement": "No flight identity of its own - a pure payload element that flies however the rest of the mix flies, then makes the landing everyone's problem."},
	{"id": 7, "name": "KINETIC", "desc": "Knockback-heavy hits, pure mass-behind-the-shot damage. Deals 2x against Lightning shields; takes 2x from Lightning shields in return.",
		"movement": "The Straightener: massively extends range (5x at full ratio, with the flight time to actually use it) on a locked, unwavering straight line - and it imposes that discipline on the whole mix, damping Vortex's spiral, flattening Poison's lob, and pushing through Fire's drag. Paired with Vampiric homing it grants pierce-through on contact."},
	{"id": 8, "name": "PIERCE", "desc": "Armor-piercing rounds - ignores a flat share of armor/shield mitigation on every hit, and any PIERCE hit that gets past shields has a small flat chance to instantly execute the target outright - regardless of remaining HP. Bosses, Commanders, and Piercing Jammers (plus anyone standing in a Piercing Jammer's aura) are immune to that execution.",
		"movement": "THE velocity element: a huge flat speed bonus, and the round's 'infinite mass' ignores Fire drag completely. If you want shots to arrive fast, this is who you ask - not Kinetic (that's range)."},
	{"id": 9, "name": "VAMPIRIC", "desc": "Heals the attacker for a share of the damage dealt (lifesteal). Deals 2x against Poison shields; takes 2x from Poison shields in return.",
		"movement": "The Hunter: actively curves mid-flight to seek enemies, turn rate scaling with its ratio. Ice's inertia resists the curve; Kinetic+Vampiric together grant pierce so the hunt continues through the first victim."},
]

const TerrainEffectsScript = preload("res://scripts/core/TerrainEffects.gd") # no class_name on that script

# --- Terrain and combinations (P lane: "Synergy Codex for biome interactions") ---------------------------------------------
# Numbers come from the real constants (TerrainEffects, ElementCombos) so the text cannot drift from the rules; the two shot
# interactions below mirror ProjectileBatchPool._apply_biome_triggers (water+Lightning: 400px burst at 2x damage, forest+Fire:
# 200px burst at 1.5x damage that sets targets burning) - update here if those change.
static func _pct(mult: float) -> String:
	return "%+d%%" % int(round((mult - 1.0) * 100.0))

static func terrain_entries() -> Array:
	return [
		{"name": "ROAD", "desc": "Walking speed %s. Roads reward routes." % _pct(TerrainEffectsScript.ROAD_SPEED)},
		{"name": "SHALLOWS", "desc": "Walking speed %s and looser steering. Lightning shots arc through the water: a 400 px burst for 2x damage." % _pct(TerrainEffectsScript.SHALLOW_SPEED)},
		{"name": "WATER", "desc": "Mechs without a jumpjet or amphibious legs can drown. Lightning shots arc through it: a 400 px burst for 2x damage."},
		{"name": "TUNDRA ICE", "desc": "Very low traction (%d%% of normal): you keep sliding the way you were going and steering takes a moment to bite." % int(round(TerrainEffectsScript.ICE_TRACTION * 100.0))},
		{"name": "VOLCANIC ASH", "desc": "Walking speed %s." % _pct(TerrainEffectsScript.ASH_SPEED)},
		{"name": "FOREST", "desc": "Undergrowth slows walking (%s). Fire shots set it off: a 200 px burst for 1.5x damage that leaves targets burning." % _pct(TerrainEffectsScript.UNDERGROWTH_SPEED)},
		{"name": "CLIMATE", "desc": "Freeze and Burn last longer or shorter by the ground under the target. Tundra: Freeze %s, Burn %s. Desert: Freeze %s, Burn %s. Volcano: Freeze %s, Burn %s. Forest: Burn %s. Water and shallows: Burn %s (doused)." % [
			_pct(BiomeIdentity.status_mult(BiomeIdentity.TUNDRA, "frozen")), _pct(BiomeIdentity.status_mult(BiomeIdentity.TUNDRA, "burning")),
			_pct(BiomeIdentity.status_mult(BiomeIdentity.DESERT, "frozen")), _pct(BiomeIdentity.status_mult(BiomeIdentity.DESERT, "burning")),
			_pct(BiomeIdentity.status_mult(BiomeIdentity.VOLCANO, "frozen")), _pct(BiomeIdentity.status_mult(BiomeIdentity.VOLCANO, "burning")),
			_pct(BiomeIdentity.status_mult(BiomeIdentity.FOREST, "burning")), _pct(BiomeIdentity.status_mult(BiomeIdentity.WATER, "burning"))]},
		{"name": "LAVA VENTS", "desc": "Volcano vents erupt on a timer for 30 Fire damage and a burn, to anyone in range. An Explosion near an idle vent sets it off early. Some enemies step away from a vent about to blow."},
		{"name": "OIL SLICKS", "desc": "Any Fire shot ignites an oil slick it passes through."},
		{"name": "JUMPJETS / AMPHIBIOUS", "desc": "Mechs that are not touching the ground ignore every ground effect above."},
	]

static func combo_entries() -> Array:
	var notes = {
		"Shatter": "Ice freezes and embrittles; a Kinetic hit then shatters the target and hurts its neighbours (never the shooter). Works from one gun carrying both, or two guns.",
		"Gravity well": "A Poison mine with a big Vortex share becomes a gravity well that drags everything nearby together.",
		"Rend & burn": "Pierce rends armour (+20% damage taken) and passes through a whole line; Fire's burn then scales with the shot.",
		"Storm": "Lightning chains and paralyses; Explosion splashes onto the locked-up targets.",
	}
	var out: Array = []
	for name in ElementCombos.COMBOS:
		var c: Dictionary = ElementCombos.COMBOS[name]
		out.append({"name": name.to_upper(), "elements": "%s + %s" % [EnergyPacket.element_name(int(c["a"])).capitalize(), EnergyPacket.element_name(int(c["b"])).capitalize()], "desc": notes.get(name, "")})
	out.append({"name": "VORTEX CRASH", "elements": "Vortex", "desc": "Enemies dragged into each other by a Vortex pull hurt each other, more the faster and harder they are pulled. An Anchor fed with energy softens it for you."})
	out.append({"name": "ENEMY COMBOS", "elements": "", "desc": "On higher difficulties some enemies carry these same pairs. The War Room shows when they lean on an element you can counter with a Shock, Freeze or Stun Guard."})
	return out

var garage: GarageMenu
var _popup: PopupPanel = null

func _init(p_garage: GarageMenu):
	garage = p_garage

func show_popup():
	if not _popup:
		_popup = _build_popup()
		garage.add_child(_popup)
	_popup.popup_centered(Vector2(460, 520))
	UiFx.pop_in_popup(_popup)

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
	header.text = "How each element behaves - shield bonuses are always mutual (both directions apply). FLIGHT describes how the shot itself moves; mixed packets blend flight behaviors by their ratios."
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

		if entry.has("movement"):
			var move_label = Label.new()
			move_label.text = "FLIGHT: " + entry.movement
			move_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			move_label.custom_minimum_size = Vector2(390, 0)
			move_label.add_theme_font_size_override("font_size", 12)
			move_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
			text_vbox.add_child(move_label)

		vbox.add_child(HSeparator.new())

	_add_section(vbox, "TERRAIN - how the ground changes a fight", terrain_entries())
	_add_section(vbox, "COMBINATIONS - elements that work together", combo_entries())

	return popup

func _add_section(vbox: VBoxContainer, title: String, entries: Array) -> void:
	var head = Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(head)
	for e in entries:
		var name_label = Label.new()
		name_label.text = e["name"] + ("  (" + e["elements"] + ")" if e.get("elements", "") != "" else "")
		name_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		vbox.add_child(name_label)
		var desc_label = Label.new()
		desc_label.text = e["desc"]
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(390, 0)
		vbox.add_child(desc_label)
	vbox.add_child(HSeparator.new())
