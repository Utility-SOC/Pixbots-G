class_name SetPieceKit
extends RefCounted

# Kitbashing: new set pieces built by combining existing ones, like a game shop table where terrain from a dozen
# different games stands side by side. Ops work on the art's [Rect2, Color] output, so any piece (including kits) can be
# a part of another. Used for mixed-genre pieces (a castle tower on a reactor), surreal pieces (a flipped spire, an
# hourglass of two towers) and the "evolved" farm buildings that turn gothic or art deco as a war drags on.
#   stack:   `top` in the upper `frac` of the footprint, `bottom` in the rest
#   flank:   `center` in the middle, `side` on both flanks (each `frac` of the width)
#   overlay: `base` over the whole footprint, then `top` over its upper `frac`
#   flip:    `base`, mirrored top to bottom
#   hourglass: `base` flipped on top of `base`

const PIX = 4.0

const KITS = {
	# evolved farm buildings (reached through SetPieces.evolved, never picked directly)
	"gothic_silo": {"op": "stack", "top": "gothic_spire", "bottom": "silo", "frac": 0.5},
	"deco_silo": {"op": "stack", "top": "deco_tower", "bottom": "silo", "frac": 0.5},
	"granary_chapel": {"op": "stack", "top": "gothic_chapel", "bottom": "granary", "frac": 0.45},
	"cathedral_barn": {"op": "overlay", "base": "granary", "top": "gothic_cathedral", "frac": 0.7},
	"windmill_spire": {"op": "flank", "center": "windmill", "side": "gothic_spire", "frac": 0.25},
	"haystack_shrine": {"op": "stack", "top": "shrine", "bottom": "haystack", "frac": 0.55},
	"deco_stable": {"op": "overlay", "base": "stable", "top": "deco_hall", "frac": 0.55},
	# mixed-genre kitbashes
	"keep_reactor": {"op": "stack", "top": "gothic_spire", "bottom": "reactor_tower", "frac": 0.45},
	"hab_chapel": {"op": "flank", "center": "hab_dome", "side": "gothic_spire", "frac": 0.25},
	"dome_cathedral": {"op": "stack", "top": "bio_dome", "bottom": "gothic_chapel", "frac": 0.5},
	"castle_launchpad": {"op": "flank", "center": "landing_pad", "side": "bell_tower", "frac": 0.2},
	"fortress_works": {"op": "overlay", "base": "smokestack_works", "top": "gatehouse", "frac": 0.5},
	"tank_cathedral": {"op": "stack", "top": "gothic_chapel", "bottom": "wrecked_tank", "frac": 0.65},
	"deco_bunker": {"op": "stack", "top": "deco_tower", "bottom": "bunker", "frac": 0.6},
	"pylon_chapel": {"op": "flank", "center": "gothic_chapel", "side": "pylon", "frac": 0.2},
	"silo_monolith": {"op": "flank", "center": "data_monolith", "side": "silo", "frac": 0.3},
	"cathedral_hangar": {"op": "stack", "top": "gothic_cathedral", "bottom": "hangar", "frac": 0.55},
	"temple_reactor": {"op": "stack", "top": "reactor_tower", "bottom": "temple", "frac": 0.45},
	# surreal
	"upside_down_spire": {"op": "flip", "base": "gothic_spire"},
	"mirror_chapel": {"op": "hourglass", "base": "gothic_chapel"},
	"hourglass_tower": {"op": "hourglass", "base": "deco_tower"},
	"inverted_cathedral": {"op": "flip", "base": "gothic_cathedral"},
	"twin_obelisks": {"op": "flank", "center": "eye_pillar", "side": "obelisk", "frac": 0.2},
	"sky_fortress": {"op": "stack", "top": "gatehouse", "bottom": "cloud_pedestal", "frac": 0.6},
}

static func has_style(style: String) -> bool:
	return KITS.has(style)

static func styles() -> Array:
	return KITS.keys()

static func _cells(v: float) -> float:
	return maxf(PIX, round(v / PIX) * PIX)

static func _place(parts: Array, sub: Array, dx: float, dy: float) -> void:
	for r in sub:
		var rc: Rect2 = r[0]
		parts.append([Rect2(rc.position + Vector2(dx, dy), rc.size), r[1]])

static func _flip(sub: Array, height: float) -> Array:
	var out: Array = []
	for r in sub:
		var rc: Rect2 = r[0]
		out.append([Rect2(rc.position.x, height - rc.end.y, rc.size.x, rc.size.y), r[1]])
	return out

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	var k: Dictionary = KITS[style]
	var w = _cells(footprint.x)
	var h = _cells(footprint.y)
	var out: Array = []
	match k["op"]:
		"stack":
			var th = _cells(h * float(k["frac"]))
			var bh = maxf(PIX, h - th)
			_place(out, SetPieceArt.rects(k["bottom"], Vector2(w, bh), seed_v + 1), 0.0, th)
			_place(out, SetPieceArt.rects(k["top"], Vector2(w, th), seed_v + 2), 0.0, 0.0)
		"flank":
			var sw = _cells(w * float(k["frac"]))
			var cw = maxf(PIX, w - 2.0 * sw)
			_place(out, SetPieceArt.rects(k["center"], Vector2(cw, h), seed_v + 1), sw, 0.0)
			_place(out, SetPieceArt.rects(k["side"], Vector2(sw, h), seed_v + 2), 0.0, 0.0)
			_place(out, SetPieceArt.rects(k["side"], Vector2(sw, h), seed_v + 3), w - sw, 0.0)
		"overlay":
			var oh = _cells(h * float(k["frac"]))
			_place(out, SetPieceArt.rects(k["base"], Vector2(w, h), seed_v + 1), 0.0, 0.0)
			_place(out, SetPieceArt.rects(k["top"], Vector2(w, oh), seed_v + 2), 0.0, 0.0)
		"flip":
			out = _flip(SetPieceArt.rects(k["base"], Vector2(w, h), seed_v + 1), h)
		"hourglass":
			var half = _cells(h / 2.0)
			_place(out, _flip(SetPieceArt.rects(k["base"], Vector2(w, half), seed_v + 1), half), 0.0, 0.0)
			_place(out, SetPieceArt.rects(k["base"], Vector2(w, maxf(PIX, h - half)), seed_v + 2), 0.0, half)
	return out
