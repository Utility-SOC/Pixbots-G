class_name MechStatusGraph
extends Control

# Small black-and-green "systems" schematic in the bottom-right corner: the player's mech as a paper doll
# (head, pack, arms, torso, legs) with every IMPORTANT tile drawn as a tiny line glyph at its real position
# inside its component, so one glance answers "what is still working?" when deciding whether to go back to the
# Garage.
#
#   glyphs   ○ actuator   ◇ jumpjet / maneuvering thruster   △ weapon (mount, lance, missile rack, orbiting array)
#            □ component link   ✚ other module (shield, heal beacon, jammer, cloak, drone bay)
#   states   bright = fine,  dim = damaged (under 60% HP),  blinking = knocked offline, rebooting,
#            X = fried (power lost; only a Garage repair fixes it).
#   limbs    the box outline dims at under 50% integrity; a destroyed limb is dashed with a slash through it.
#   RPR bar  (only with a MYTHIC heal beacon) how charged the beacon's Field Repair pulse is.
#
# Toggle with F10 or Settings > Visuals. Purely a read-only view of Mech state; redraws ~5x a second.

const SIZE := Vector2(236.0, 196.0)
const MARGIN := 14.0
const GREEN := Color(0.25, 1.0, 0.35)
const GREEN_DIM := Color(0.11, 0.55, 0.19)
const GREEN_FAINT := Color(0.07, 0.30, 0.11)
const DAMAGED_FRACTION := 0.6
const LIMB_HURT_FRACTION := 0.5

enum Kind { NONE, ACTUATOR, JUMPJET, WEAPON, LINK, MODULE }
enum State { OK, DAMAGED, REBOOTING, LOST }

# Script file name -> glyph kind. Subclasses (brand variants under tiles/brands/) are matched by walking up
# the script inheritance chain, so they inherit their base tile's glyph.
const KIND_BY_FILE := {
	"ActuatorTile.gd": Kind.ACTUATOR,
	"JumpjetTile.gd": Kind.JUMPJET,
	"ManeuveringThrusterTile.gd": Kind.JUMPJET,
	"WeaponMountTile.gd": Kind.WEAPON,
	"LanceMountTile.gd": Kind.WEAPON,
	"MissileRackTile.gd": Kind.WEAPON,
	"OrbitingArrayTile.gd": Kind.WEAPON,
	"ComponentLinkTile.gd": Kind.LINK,
	"ShieldGeneratorTile.gd": Kind.MODULE,
	"HealBeaconTile.gd": Kind.MODULE,
	"JammerModuleTile.gd": Kind.MODULE,
	"CloakTile.gd": Kind.MODULE,
	"DroneBayTile.gd": Kind.MODULE,
}

# Body slot -> [grid column, grid row, label]. Column widths and row heights are fixed below.
const SLOT_CELLS := {
	HexTile.BodySlot.HEAD: [1, 0, "HEAD"],
	HexTile.BodySlot.BACKPACK: [2, 0, "PACK"],
	HexTile.BodySlot.ARM_L: [0, 1, "L.ARM"],
	HexTile.BodySlot.TORSO: [1, 1, "TORSO"],
	HexTile.BodySlot.ARM_R: [2, 1, "R.ARM"],
	HexTile.BodySlot.LEG_L: [0, 2, "L.LEG"],
	HexTile.BodySlot.LEG_R: [2, 2, "R.LEG"],
}
const COL_X := [6.0, 68.0, 172.0]
const COL_W := [58.0, 100.0, 58.0]
const ROW_Y := [6.0, 60.0, 144.0]
const ROW_H := [50.0, 80.0, 46.0]

var main: Node = null # Main, set by Main._setup_hud (the player Mech is main.player)
var _t := 0.0
var _redraw_t := 0.0

func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _reposition() -> void:
	var vs := get_viewport_rect().size
	position = Vector2(vs.x - SIZE.x - MARGIN, vs.y - SIZE.y - MARGIN)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		SaveManager.set_status_graph(not SaveManager.show_status_graph)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_t += delta
	var player: Mech = _player()
	var show_it: bool = SaveManager.show_status_graph and player != null and not _garage_open()
	if visible != show_it:
		visible = show_it
	if not show_it:
		return
	_redraw_t += delta
	if _redraw_t >= 0.2:
		_redraw_t = 0.0
		queue_redraw()

func _player() -> Mech:
	if main != null and is_instance_valid(main) and "player" in main and is_instance_valid(main.player):
		return main.player
	return null

func _garage_open() -> bool:
	return main != null and "garage_ui" in main and is_instance_valid(main.garage_ui)

# ------------------------------------------------------------------ pure helpers (unit-tested)

static func kind_of(tile) -> int:
	var s = tile.get_script()
	while s != null:
		var f: String = s.resource_path.get_file()
		if KIND_BY_FILE.has(f):
			return KIND_BY_FILE[f]
		s = s.get_base_script()
	return Kind.NONE

static func state_of(tile) -> int:
	if tile.power_lost:
		return State.LOST
	if tile.is_disabled:
		return State.REBOOTING
	if tile.max_hp > 0.0 and tile.hp < tile.max_hp * DAMAGED_FRACTION:
		return State.DAMAGED
	return State.OK

# 0 fine, 1 hurt (integrity under half), 2 destroyed.
static func limb_state(comp) -> int:
	if comp.is_broken:
		return 2
	if comp.integrity >= 0.0 and comp.max_integrity > 0.0 and comp.integrity < comp.max_integrity * LIMB_HURT_FRACTION:
		return 1
	return 0

static func hex_world(q: int, r: int) -> Vector2:
	return Vector2(sqrt(3.0) * (float(q) + float(r) / 2.0), 1.5 * float(r))

# Where the tiles sit inside `inner`: returns {"scale": float, "origin": Vector2} so that
# hex_world(p) * scale + origin lands inside the rect, centred, with the scale capped so tiny grids stay tiny.
static func fit(points: Array, inner: Rect2, max_scale: float = 7.0) -> Dictionary:
	if points.is_empty():
		return {"scale": 1.0, "origin": inner.get_center()}
	var lo: Vector2 = points[0]
	var hi: Vector2 = points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var ext := (hi - lo) + Vector2(2.0, 2.0) # a hex is about one unit either side of its centre
	var sc := minf(minf(inner.size.x / ext.x, inner.size.y / ext.y), max_scale)
	var centre := (lo + hi) * 0.5
	return {"scale": sc, "origin": inner.get_center() - centre * sc}

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var player: Mech = _player()
	if player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color.BLACK, true)
	draw_rect(Rect2(Vector2.ZERO, SIZE), GREEN_DIM, false, 1.0)
	for slot in SLOT_CELLS:
		var cell = SLOT_CELLS[slot]
		var rect := Rect2(COL_X[cell[0]], ROW_Y[cell[1]], COL_W[cell[0]], ROW_H[cell[1]])
		if player.components.has(slot):
			_draw_component(player.components[slot], rect, cell[2])
		else:
			_draw_dashed_rect(rect, GREEN_FAINT)
			_label(cell[2], rect.position + Vector2(3, 9), GREEN_FAINT)
	_draw_vitals(player, Rect2(COL_X[0], ROW_Y[0], COL_W[0], ROW_H[0]))
	_draw_legend(Rect2(COL_X[1], ROW_Y[2], COL_W[1], ROW_H[2]))

func _label(text: String, pos: Vector2, col: Color, font_size: int = 8) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

func _draw_component(comp, rect: Rect2, title: String) -> void:
	var ls := limb_state(comp)
	var outline := GREEN if ls == 0 else (GREEN_DIM if ls == 1 else GREEN_FAINT)
	if ls == 2:
		_draw_dashed_rect(rect, outline)
		draw_line(rect.position, rect.end, outline, 1.0, true)
		_label(title, rect.position + Vector2(3, 9), outline)
		return
	draw_rect(rect, outline, false, 1.0)
	_label(title, rect.position + Vector2(3, 9), outline)

	var tiles: Array = comp.hex_grid.get_all_tiles()
	if tiles.is_empty():
		return
	var pts: Array = []
	for t in tiles:
		if t.grid_position != null:
			pts.append(hex_world(t.grid_position.q, t.grid_position.r))
	var inner := Rect2(rect.position + Vector2(4, 12), rect.size - Vector2(8, 16))
	var f := fit(pts, inner)
	var g: float = clampf(float(f["scale"]) * 0.5, 2.0, 4.5)
	for t in tiles:
		var kind := kind_of(t)
		if kind == Kind.NONE or t.grid_position == null:
			continue
		var c: Vector2 = hex_world(t.grid_position.q, t.grid_position.r) * float(f["scale"]) + (f["origin"] as Vector2)
		_draw_glyph(kind, state_of(t), c, g)

func _draw_glyph(kind: int, st: int, c: Vector2, g: float) -> void:
	var col := GREEN
	match st:
		State.DAMAGED:
			col = GREEN_DIM
		State.REBOOTING:
			if fmod(_t, 0.6) > 0.3:
				col = GREEN_FAINT # blink: bright-dim <-> faint
			else:
				col = GREEN_DIM
		State.LOST:
			draw_line(c + Vector2(-g, -g), c + Vector2(g, g), GREEN_FAINT, 1.0, true)
			draw_line(c + Vector2(-g, g), c + Vector2(g, -g), GREEN_FAINT, 1.0, true)
			return
	match kind:
		Kind.ACTUATOR:
			draw_arc(c, g, 0.0, TAU, 14, col, 1.0, true)
		Kind.JUMPJET:
			var d := PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0), c + Vector2(0, -g)])
			draw_polyline(d, col, 1.0, true)
		Kind.WEAPON:
			var tri := PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, g * 0.8), c + Vector2(-g, g * 0.8), c + Vector2(0, -g)])
			draw_polyline(tri, col, 1.0, true)
		Kind.LINK:
			draw_rect(Rect2(c - Vector2(g, g) * 0.8, Vector2(g, g) * 1.6), col, false, 1.0)
		Kind.MODULE:
			draw_line(c + Vector2(-g, 0), c + Vector2(g, 0), col, 1.0, true)
			draw_line(c + Vector2(0, -g), c + Vector2(0, g), col, 1.0, true)

func _draw_dashed_rect(r: Rect2, col: Color) -> void:
	var seg := 4.0
	for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var edge_len := a.distance_to(b)
		var dir := (b - a) / maxf(edge_len, 0.001)
		var d := 0.0
		while d < edge_len:
			draw_line(a + dir * d, a + dir * minf(d + seg, edge_len), col, 1.0)
			d += seg * 2.0

func _draw_vitals(player: Mech, rect: Rect2) -> void:
	_label("HP", rect.position + Vector2(2, 9), GREEN)
	var frac := clampf(player.hp / maxf(player.max_hp, 1.0), 0.0, 1.0)
	var bar := Rect2(rect.position + Vector2(2, 13), Vector2(rect.size.x - 4, 6))
	draw_rect(bar, GREEN_DIM, false, 1.0)
	draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * frac, bar.size.y - 2)), GREEN if frac > 0.35 else GREEN_DIM, true)
	var broken := 0
	var fried := 0
	var offline := 0
	for comp in player.components.values():
		if comp.is_broken:
			broken += 1
		for t in comp.hex_grid.get_all_tiles():
			if kind_of(t) == Kind.NONE:
				continue
			if t.power_lost:
				fried += 1
			elif t.is_disabled:
				offline += 1
	_label("LOST %d" % (fried + broken), rect.position + Vector2(2, 31), GREEN if fried + broken == 0 else GREEN_DIM)
	_label("REBOOT %d" % offline, rect.position + Vector2(2, 41), GREEN if offline == 0 else GREEN_DIM)
	# MYTHIC heal beacon Field Repair: how close the next repair pulse is (full bar = ready, fires when something breaks).
	if player.has_field_repair:
		var cost: float = TileStatsRegistry.get_stat("HealBeaconTile", "repair_pulse_cost", 60000.0)
		var charge := clampf(player.repair_charge / maxf(cost, 1.0), 0.0, 1.0)
		_label("RPR", rect.position + Vector2(2, 49), GREEN, 7)
		var rbar := Rect2(rect.position + Vector2(20, 43), Vector2(rect.size.x - 22, 5))
		draw_rect(rbar, GREEN_DIM, false, 1.0)
		draw_rect(Rect2(rbar.position + Vector2(1, 1), Vector2((rbar.size.x - 2) * charge, rbar.size.y - 2)), GREEN if charge >= 1.0 else GREEN_DIM, true)

func _draw_legend(rect: Rect2) -> void:
	var entries := [[Kind.ACTUATOR, "ACT"], [Kind.JUMPJET, "JET"], [Kind.WEAPON, "GUN"], [Kind.LINK, "LNK"], [Kind.MODULE, "MOD"]]
	for i in range(entries.size()):
		var col_i := i % 3
		var row_i := i / 3
		var c := rect.position + Vector2(10.0 + col_i * 32.0, 10.0 + row_i * 13.0)
		_draw_glyph(entries[i][0], State.OK, c, 3.0)
		_label(entries[i][1], c + Vector2(6, 3), GREEN_DIM, 7)
	_label("dim=hit blink=reboot", rect.position + Vector2(2, 36), GREEN_FAINT, 7)
	_label("X=fried (garage)", rect.position + Vector2(2, 44), GREEN_FAINT, 7)
