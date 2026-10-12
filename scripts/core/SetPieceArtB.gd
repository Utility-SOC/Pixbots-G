class_name SetPieceArtB
extends RefCounted

# Second half of the set-piece art (see SetPieceArt for the contract: [Rect2, Color] in footprint top-left coordinates,
# deterministic per seed). Urban, monuments, fortifications, camps, power, wrecks, ancient ruins and extra gothic, deco,
# agricultural and industrial kits. Shared palette and the cell-fill helper live in SetPieceArt.

static func styles() -> Array:
	return ["bell_tower", "crypt", "ruined_arch", "graveyard", "cinema", "hotel", "deco_station",
		"apartment_block", "office_slab", "shop_row", "parking_garage", "billboard", "tenement",
		"obelisk", "war_memorial", "fountain", "mausoleum", "shrine", "statue",
		"gatehouse", "wall_segment", "corner_tower", "pillbox", "tank_traps",
		"tent_cluster", "field_hospital", "supply_dump", "radar_dish", "antenna_mast",
		"pylon", "substation", "wind_turbine", "solar_array",
		"wrecked_tank", "wrecked_truck", "downed_aircraft", "derelict_railcar",
		"windmill", "greenhouse", "water_tower", "stable", "corn_crib",
		"crane", "refinery_tower", "warehouse", "gasometer",
		"temple", "column_ruin", "ziggurat", "sandstone_arch"]

static func _f(o: Array, c0: int, r0: int, c1: int, r1: int, col: Color, cols: int, rows: int) -> void:
	SetPieceArt._f(o, c0, r0, c1, r1, col, cols, rows)

# Grid of small windows inside a block.
static func _wins(o: Array, c0: int, r0: int, c1: int, r1: int, ww: int, wh: int, gx: int, gy: int, col: Color, cols: int, rows: int, rng: RandomNumberGenerator = null) -> void:
	var r = r0
	while r + wh <= r1:
		var c = c0
		while c + ww <= c1:
			var lit = col
			if rng != null and rng.randf() < 0.18:
				lit = SetPieceArt.GOLD.darkened(0.2) # a lit window
			_f(o, c, r, c + ww, r + wh, lit, cols, rows)
			c += ww + gx
		r += wh + gy

# Triangular roof of `h` rows whose base spans c0..c1 and sits on row r_base.
static func _pitch(o: Array, c0: int, c1: int, r_base: int, h: int, col: Color, cols: int, rows: int) -> void:
	for i in range(h):
		var inset = (h - 1 - i) * maxi(1, (c1 - c0) / (2 * maxi(1, h)))
		_f(o, c0 + inset, r_base - h + i, c1 - inset, r_base - h + i + 1, col if i % 2 == 0 else col.lightened(0.08), cols, rows)

static func rects(style: String, footprint: Vector2, seed_v: int) -> Array:
	var cols = int(footprint.x / SetPieceArt.PIX)
	var rows = int(footprint.y / SetPieceArt.PIX)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var o: Array = []
	match style:
		"bell_tower": _bell_tower(o, cols, rows)
		"crypt": _crypt(o, cols, rows)
		"ruined_arch": _ruined_arch(o, cols, rows)
		"graveyard": _graveyard(o, cols, rows, rng)
		"cinema": _cinema(o, cols, rows)
		"hotel": _hotel(o, cols, rows, rng)
		"deco_station": _deco_station(o, cols, rows)
		"apartment_block": _apartments(o, cols, rows, rng)
		"office_slab": _office(o, cols, rows, rng)
		"shop_row": _shop_row(o, cols, rows, rng)
		"parking_garage": _garage(o, cols, rows)
		"billboard": _billboard(o, cols, rows)
		"tenement": _tenement(o, cols, rows, rng)
		"obelisk": _obelisk(o, cols, rows)
		"war_memorial": _memorial(o, cols, rows)
		"fountain": _fountain(o, cols, rows)
		"mausoleum": _mausoleum(o, cols, rows)
		"shrine": _shrine(o, cols, rows)
		"statue": _statue(o, cols, rows)
		"gatehouse": _gatehouse(o, cols, rows)
		"wall_segment": _wall(o, cols, rows)
		"corner_tower": _corner_tower(o, cols, rows)
		"pillbox": _pillbox(o, cols, rows)
		"tank_traps": _traps(o, cols, rows)
		"tent_cluster": _tents(o, cols, rows, rng)
		"field_hospital": _hospital(o, cols, rows)
		"supply_dump": _supplies(o, cols, rows, rng)
		"radar_dish": _radar(o, cols, rows)
		"antenna_mast": _mast(o, cols, rows)
		"pylon": _pylon(o, cols, rows)
		"substation": _substation(o, cols, rows)
		"wind_turbine": _turbine(o, cols, rows)
		"solar_array": _solar(o, cols, rows)
		"wrecked_tank": _wreck_tank(o, cols, rows)
		"wrecked_truck": _wreck_truck(o, cols, rows)
		"downed_aircraft": _aircraft(o, cols, rows)
		"derelict_railcar": _railcar(o, cols, rows)
		"windmill": _windmill(o, cols, rows)
		"greenhouse": _greenhouse(o, cols, rows)
		"water_tower": _water_tower(o, cols, rows)
		"stable": _stable(o, cols, rows)
		"corn_crib": _crib(o, cols, rows)
		"crane": _crane(o, cols, rows)
		"refinery_tower": _refinery(o, cols, rows)
		"warehouse": _warehouse(o, cols, rows)
		"gasometer": _gasometer(o, cols, rows)
		"temple": _temple(o, cols, rows)
		"column_ruin": _columns(o, cols, rows, rng)
		"ziggurat": _ziggurat(o, cols, rows)
		"sandstone_arch": _sandstone_arch(o, cols, rows)
	return o

# ---- gothic / deco extras ---------------------------------------------------------------------------------------
static func _bell_tower(o, cols, rows):
	var c0 = cols / 4
	var c1 = cols - cols / 4
	_f(o, c0, rows / 3, c1, rows, SetPieceArt.STONE, cols, rows)
	_f(o, c0, rows / 3, c0 + 1, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, c0 - 1, rows / 3 - 2, c1 + 1, rows / 3, SetPieceArt.STONE_D, cols, rows)
	_f(o, c0 + 1, rows / 3 - 6, c1 - 1, rows / 3 - 2, SetPieceArt.SHADOW, cols, rows) # open belfry
	_f(o, cols / 2 - 1, rows / 3 - 5, cols / 2 + 1, rows / 3 - 3, SetPieceArt.GOLD, cols, rows) # the bell
	_pitch(o, c0 - 1, c1 + 1, rows / 3 - 6, 5, SetPieceArt.SLATE, cols, rows)
	SetPieceArt._arch(o, cols / 2 - 1, rows / 2, maxi(3, rows / 4), SetPieceArt.SHADOW, cols, rows)
	_f(o, cols / 2 - 1, rows - 3, cols / 2 + 1, rows, SetPieceArt.SHADOW, cols, rows)

static func _crypt(o, cols, rows):
	_f(o, 0, rows / 2, cols, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, 0, rows / 2, cols, rows / 2 + 2, SetPieceArt.STONE, cols, rows)
	for c in range(1, cols - 1, 5):
		_f(o, c, rows / 2 + 3, c + 3, rows - 2, SetPieceArt.SHADOW, cols, rows) # sealed niches
	_f(o, cols / 2 - 2, rows / 3, cols / 2 + 2, rows / 2, SetPieceArt.STONE_L, cols, rows) # cross plinth
	_f(o, cols / 2, rows / 4, cols / 2 + 1, rows / 2, SetPieceArt.STONE_L, cols, rows)
	_f(o, cols / 2 - 2, rows / 3 + 1, cols / 2 + 3, rows / 3 + 2, SetPieceArt.STONE_L, cols, rows)

static func _ruined_arch(o, cols, rows):
	var w = maxi(3, cols / 5)
	_f(o, 0, rows / 3, w, rows, SetPieceArt.STONE, cols, rows)
	_f(o, cols - w, rows / 4, cols, rows, SetPieceArt.STONE, cols, rows) # broken right pier
	_f(o, 0, rows / 3, w, rows / 3 + 1, SetPieceArt.STONE_L, cols, rows)
	var span = cols - 2 * w
	for i in range(span):
		var lift = int(sin(PI * float(i) / float(maxi(1, span - 1))) * float(rows) / 5.0)
		_f(o, w + i, rows / 3 - lift, w + i + 1, rows / 3 - lift + 3, SetPieceArt.STONE_L if i % 2 == 0 else SetPieceArt.STONE, cols, rows) # the arch ring
	_f(o, w, rows - 3, cols - w, rows, SetPieceArt.STONE_D, cols, rows) # fallen stones
	_f(o, w + 2, rows - 5, w + 5, rows - 3, SetPieceArt.STONE, cols, rows)

static func _graveyard(o, cols, rows, rng):
	_f(o, 0, 0, cols, rows, Color(0.28, 0.34, 0.24), cols, rows)
	_f(o, 0, 0, cols, 1, SetPieceArt.STONE_D, cols, rows) # low wall
	_f(o, 0, rows - 1, cols, rows, SetPieceArt.STONE_D, cols, rows)
	for r in range(3, rows - 2, 5):
		for c in range(3, cols - 3, 4):
			if rng.randf() < 0.85:
				_f(o, c, r, c + 2, r + 3, SetPieceArt.STONE_L if rng.randf() < 0.5 else SetPieceArt.STONE, cols, rows)
				_f(o, c, r, c + 2, r + 1, SetPieceArt.STONE_D, cols, rows)

static func _cinema(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows, SetPieceArt.DECO, cols, rows)
	_f(o, cols / 4, 1, cols - cols / 4, rows / 3, SetPieceArt.DECO_L, cols, rows)
	_f(o, cols / 4 - 1, rows / 3 - 1, cols - cols / 4 + 1, rows / 3, SetPieceArt.GOLD, cols, rows)
	_f(o, cols / 4 + 2, 3, cols - cols / 4 - 2, rows / 3 - 3, SetPieceArt.GOLD.darkened(0.2), cols, rows) # sign board
	_f(o, cols / 2 - 3, rows - 6, cols / 2 + 3, rows, SetPieceArt.SHADOW, cols, rows) # lobby
	_f(o, 1, rows - 6, cols / 2 - 4, rows - 2, SetPieceArt.GLASS, cols, rows)
	_f(o, cols / 2 + 4, rows - 6, cols - 1, rows - 2, SetPieceArt.GLASS, cols, rows)
	_f(o, 0, rows / 3 + 1, cols, rows / 3 + 2, SetPieceArt.GOLD, cols, rows)

static func _hotel(o, cols, rows, rng):
	_f(o, 0, 3, cols, rows, SetPieceArt.BRICK.lightened(0.15), cols, rows)
	_wins(o, 2, 6, cols - 2, rows - 6, 2, 3, 2, 2, SetPieceArt.GLASS.darkened(0.25), cols, rows, rng)
	_f(o, 0, 2, cols, 4, SetPieceArt.GOLD, cols, rows)
	_f(o, cols / 2 - 4, rows - 6, cols / 2 + 4, rows - 5, SetPieceArt.GOLD, cols, rows) # marquee
	_f(o, cols / 2 - 3, rows - 5, cols / 2 + 3, rows, SetPieceArt.SHADOW, cols, rows)
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, 2, SetPieceArt.GOLD, cols, rows)

static func _deco_station(o, cols, rows):
	_f(o, 0, rows / 2, cols * 2 / 3, rows, SetPieceArt.DECO_L, cols, rows) # office
	_f(o, 0, rows / 2, cols * 2 / 3, rows / 2 + 1, SetPieceArt.GOLD, cols, rows)
	_f(o, 2, rows / 2 + 3, cols * 2 / 3 - 2, rows - 2, SetPieceArt.GLASS, cols, rows)
	_f(o, cols / 3, 1, cols, 4, SetPieceArt.DECO, cols, rows) # canopy
	_f(o, cols / 3, 4, cols / 3 + 1, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, cols - 2, 4, cols - 1, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, cols * 2 / 3 + 1, rows - 6, cols * 2 / 3 + 4, rows - 1, SetPieceArt.RUST, cols, rows) # pump
	_f(o, cols * 2 / 3 + 1, rows - 6, cols * 2 / 3 + 4, rows - 5, SetPieceArt.GOLD, cols, rows)

# ---- urban --------------------------------------------------------------------------------------------------------
static func _apartments(o, cols, rows, rng):
	_f(o, 0, 0, cols, rows, SetPieceArt.BRICK.darkened(0.1), cols, rows)
	_f(o, 0, 0, cols, 2, SetPieceArt.CONCRETE_D, cols, rows)
	_wins(o, 2, 4, cols - 2, rows - 5, 2, 3, 2, 2, SetPieceArt.GLASS.darkened(0.3), cols, rows, rng)
	for c in range(3, cols - 2, 8):
		_f(o, c, 0, c + 2, 2, SetPieceArt.RUST, cols, rows) # roof units
	_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, SetPieceArt.SHADOW, cols, rows)

static func _office(o, cols, rows, rng):
	_f(o, 0, 0, cols, rows, Color(0.38, 0.45, 0.5), cols, rows)
	_f(o, 0, 0, cols, 2, SetPieceArt.CONCRETE, cols, rows)
	for r in range(3, rows - 4, 3):
		_f(o, 1, r, cols - 1, r + 2, SetPieceArt.GLASS.lightened(0.05 * (r % 2)), cols, rows)
	for c in range(0, cols, 5):
		_f(o, c, 2, c + 1, rows, Color(0.26, 0.3, 0.34), cols, rows) # mullions
	_f(o, cols / 2 - 2, rows - 4, cols / 2 + 2, rows, SetPieceArt.SHADOW, cols, rows)
	_f(o, cols / 2, 0, cols / 2 + 1, -2 + 2, SetPieceArt.GOLD, cols, rows)

static func _shop_row(o, cols, rows, rng):
	var n = maxi(2, cols / 8)
	var w = cols / n
	var palette = [Color(0.6, 0.35, 0.3), Color(0.35, 0.5, 0.55), Color(0.65, 0.55, 0.3), Color(0.4, 0.5, 0.35)]
	for i in range(n):
		var c0 = i * w
		var col: Color = palette[rng.randi() % palette.size()]
		_f(o, c0, 2, c0 + w - 1, rows, col, cols, rows)
		_f(o, c0, 0, c0 + w - 1, 2, SetPieceArt.CONCRETE_D, cols, rows)
		_f(o, c0 + 1, rows / 2, c0 + w - 2, rows - 2, SetPieceArt.GLASS, cols, rows) # shopfront
		_f(o, c0, rows / 2 - 2, c0 + w - 1, rows / 2, col.lightened(0.35), cols, rows) # awning
		_f(o, c0 + 2, 3, c0 + w - 3, rows / 2 - 3, SetPieceArt.GLASS.darkened(0.3), cols, rows)

static func _garage(o, cols, rows):
	_f(o, 0, 0, cols, rows, SetPieceArt.CONCRETE, cols, rows)
	var floors = maxi(2, rows / 5)
	for f in range(floors):
		var r0 = f * rows / floors
		_f(o, 0, r0, cols, r0 + 2, SetPieceArt.CONCRETE.lightened(0.15), cols, rows)
		_f(o, 1, r0 + 3, cols - 1, (f + 1) * rows / floors - 1, SetPieceArt.SHADOW, cols, rows)
		for c in range(3, cols - 2, 6):
			_f(o, c, r0 + 3, c + 1, (f + 1) * rows / floors - 1, SetPieceArt.CONCRETE_D, cols, rows) # pillars
	_f(o, 0, rows - 2, cols, rows, SetPieceArt.CONCRETE_D, cols, rows)

static func _billboard(o, cols, rows):
	_f(o, cols / 2 - 1, rows / 2, cols / 2 + 1, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, 1, 1, cols - 1, rows / 2, SetPieceArt.WOOD.darkened(0.2), cols, rows)
	_f(o, 2, 2, cols - 2, rows / 2 - 1, Color(0.8, 0.3, 0.25), cols, rows)
	_f(o, 4, 4, cols - 6, 7, SetPieceArt.GOLD, cols, rows)
	_f(o, 4, 9, cols - 10, 11, Color(0.95, 0.92, 0.85), cols, rows)

static func _tenement(o, cols, rows, rng):
	_f(o, 0, 3, cols, rows, SetPieceArt.BRICK, cols, rows)
	_pitch(o, 0, cols, 3, 3, SetPieceArt.SLATE, cols, rows)
	_wins(o, 2, 6, cols - 2, rows - 6, 2, 3, 3, 3, SetPieceArt.GLASS.darkened(0.3), cols, rows, rng)
	for r in range(8, rows - 3, 6):
		_f(o, 1, r, cols - 1, r + 1, SetPieceArt.RUST, cols, rows) # fire escape
	_f(o, cols / 2 - 1, rows - 4, cols / 2 + 2, rows, SetPieceArt.SHADOW, cols, rows)

# ---- monuments ----------------------------------------------------------------------------------------------------
static func _obelisk(o, cols, rows):
	_f(o, cols / 2 - 3, rows - 3, cols / 2 + 3, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, cols / 2 - 2, rows - 5, cols / 2 + 2, rows - 3, SetPieceArt.STONE, cols, rows)
	for r in range(2, rows - 5):
		var half = 1 + r / maxi(4, rows / 4)
		_f(o, cols / 2 - half, r, cols / 2 + half, r + 1, SetPieceArt.STONE_L if r % 6 else SetPieceArt.STONE, cols, rows)
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, 2, SetPieceArt.GOLD, cols, rows)

static func _memorial(o, cols, rows):
	_f(o, 1, rows - 3, cols - 1, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, 3, rows - 6, cols - 3, rows - 3, SetPieceArt.STONE, cols, rows)
	_f(o, cols / 2 - 3, 2, cols / 2 + 3, rows - 6, SetPieceArt.STONE_L, cols, rows) # cenotaph
	_f(o, cols / 2 - 4, 1, cols / 2 + 4, 2, SetPieceArt.STONE, cols, rows)
	_f(o, cols / 2 - 1, 4, cols / 2 + 1, 6, SetPieceArt.STONE_D, cols, rows) # inscription
	_f(o, 0, rows - 1, cols, rows, SetPieceArt.STONE_D.darkened(0.2), cols, rows)

static func _fountain(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, 2, rows / 3 + 2, cols - 2, rows - 2, Color(0.3, 0.5, 0.65), cols, rows) # water
	_f(o, cols / 2 - 2, rows / 3 - 1, cols / 2 + 2, rows - 3, SetPieceArt.STONE, cols, rows) # pedestal
	_f(o, cols / 2 - 1, 1, cols / 2 + 1, rows / 3, SetPieceArt.STONE_L, cols, rows)
	_f(o, cols / 2 - 4, 3, cols / 2 + 4, 4, Color(0.5, 0.7, 0.85, 1.0), cols, rows) # spray

static func _mausoleum(o, cols, rows):
	_f(o, 1, rows / 3, cols - 1, rows, SetPieceArt.STONE_L, cols, rows)
	_f(o, 0, rows / 3 - 1, cols, rows / 3 + 1, SetPieceArt.STONE, cols, rows)
	_pitch(o, 0, cols, rows / 3 - 1, rows / 3 - 1, SetPieceArt.STONE_D, cols, rows)
	for c in range(3, cols - 3, 4):
		_f(o, c, rows / 3 + 2, c + 2, rows, SetPieceArt.STONE, cols, rows) # columns
	_f(o, cols / 2 - 2, rows / 2 + 2, cols / 2 + 2, rows, SetPieceArt.SHADOW, cols, rows) # sealed door

static func _shrine(o, cols, rows):
	_f(o, 2, rows - 3, cols - 2, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, 3, rows / 2, cols - 3, rows - 3, SetPieceArt.WOOD, cols, rows)
	_f(o, cols / 2 - 2, rows / 2 + 2, cols / 2 + 2, rows - 3, SetPieceArt.SHADOW, cols, rows)
	_f(o, cols / 2 - 1, rows / 2 + 4, cols / 2 + 1, rows / 2 + 6, SetPieceArt.GOLD, cols, rows) # offering
	_f(o, 0, rows / 2 - 2, cols, rows / 2, Color(0.7, 0.2, 0.18), cols, rows) # curved roof
	_f(o, 1, rows / 2 - 4, cols - 1, rows / 2 - 2, Color(0.55, 0.15, 0.13), cols, rows)
	_f(o, 3, rows / 2 - 5, cols - 3, rows / 2 - 4, Color(0.7, 0.2, 0.18), cols, rows)

static func _statue(o, cols, rows):
	_f(o, 2, rows - 4, cols - 2, rows, SetPieceArt.STONE_D, cols, rows)
	_f(o, 3, rows - 7, cols - 3, rows - 4, SetPieceArt.STONE, cols, rows)
	_f(o, cols / 2 - 2, 4, cols / 2 + 2, rows - 7, SetPieceArt.STONE_L, cols, rows) # figure
	_f(o, cols / 2 - 1, 1, cols / 2 + 1, 4, SetPieceArt.STONE_L, cols, rows) # head
	_f(o, cols / 2 + 2, 4, cols / 2 + 5, 6, SetPieceArt.STONE_L, cols, rows) # raised arm
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, 1, SetPieceArt.GOLD, cols, rows)

# ---- fortifications -----------------------------------------------------------------------------------------------
static func _gatehouse(o, cols, rows):
	var tw = maxi(4, cols / 4)
	_f(o, 0, 1, tw, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, cols - tw, 1, cols, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, tw, rows / 3, cols - tw, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, tw + 1, rows / 3 + 2, cols - tw - 1, rows, SetPieceArt.SHADOW, cols, rows) # gate passage
	for c in range(tw + 2, cols - tw - 1, 2):
		_f(o, c, rows / 3 + 2, c + 1, rows - 2, SetPieceArt.CONCRETE_D.lightened(0.1), cols, rows) # portcullis
	for side in [0, cols - tw]:
		for c in range(side, side + tw, 2):
			_f(o, c, 0, c + 1, 2, SetPieceArt.CONCRETE.lightened(0.1), cols, rows) # battlements
		_f(o, side + tw / 2 - 1, rows / 3, side + tw / 2 + 1, rows / 3 + 3, SetPieceArt.SHADOW, cols, rows)
	_f(o, tw, rows / 3 - 1, cols - tw, rows / 3, SetPieceArt.CONCRETE.lightened(0.1), cols, rows)

static func _wall(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows, SetPieceArt.CONCRETE, cols, rows)
	for c in range(0, cols, 4):
		_f(o, c, rows / 3 - 2, c + 2, rows / 3, SetPieceArt.CONCRETE.lightened(0.1), cols, rows) # crenels
	for r in range(rows / 3 + 2, rows, 3):
		_f(o, 0, r, cols, r + 1, SetPieceArt.CONCRETE_D, cols, rows)
	for c in range(2, cols - 2, 6):
		_f(o, c, rows / 3 + 2, c + 1, rows / 3 + 5, SetPieceArt.SHADOW, cols, rows) # arrow slits
	_f(o, 0, rows - 2, cols, rows, SetPieceArt.CONCRETE_D.darkened(0.2), cols, rows)

static func _corner_tower(o, cols, rows):
	_f(o, 0, 2, cols, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, 0, 2, 2, rows, SetPieceArt.CONCRETE_D, cols, rows)
	for c in range(0, cols, 2):
		_f(o, c, 0, c + 1, 2, SetPieceArt.CONCRETE.lightened(0.12), cols, rows)
	_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows / 3 + 4, SetPieceArt.SHADOW, cols, rows)
	_f(o, cols / 2 - 2, rows - 3, cols / 2 + 2, rows, SetPieceArt.SHADOW, cols, rows)

static func _pillbox(o, cols, rows):
	_f(o, 1, rows / 3, cols - 1, rows, SetPieceArt.CONCRETE, cols, rows)
	_f(o, 2, rows / 3 - 1, cols - 2, rows / 3, SetPieceArt.CONCRETE.lightened(0.15), cols, rows)
	_f(o, 3, rows / 2, cols - 3, rows / 2 + 2, SetPieceArt.SHADOW, cols, rows)
	_f(o, 1, rows - 2, cols - 1, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, 0, rows - 4, 1, rows, Color(0.6, 0.52, 0.34), cols, rows)
	_f(o, cols - 1, rows - 4, cols, rows, Color(0.6, 0.52, 0.34), cols, rows)

static func _traps(o, cols, rows):
	var n = maxi(2, cols / 8)
	for i in range(n):
		var cx = cols * (2 * i + 1) / (2 * n)
		for k in range(-3, 4):
			_f(o, cx + k, rows / 2 + k, cx + k + 1, rows / 2 + k + 2, SetPieceArt.CONCRETE.lightened(0.1), cols, rows) # crossed beams
			_f(o, cx + k, rows / 2 - k, cx + k + 1, rows / 2 - k + 2, SetPieceArt.CONCRETE.lightened(0.25), cols, rows)
		_f(o, cx - 1, rows / 2 - 4, cx + 1, rows / 2 + 5, SetPieceArt.RUST, cols, rows)
	_f(o, 0, rows - 2, cols, rows - 1, SetPieceArt.CONCRETE_D.darkened(0.3), cols, rows)

# ---- camps ------------------------------------------------------------------------------------------------------------
static func _tents(o, cols, rows, rng):
	var n = maxi(2, cols / 7)
	for i in range(n):
		var cx = cols * (2 * i + 1) / (2 * n)
		var h = maxi(6, rows * 3 / 5 + (rng.randi() % 3))
		var col = Color(0.55, 0.52, 0.38) if i % 2 == 0 else SetPieceArt.OLIVE
		for r in range(h):
			var half = r * (cols / (2 * n) + 1) / h
			_f(o, cx - half, rows - h + r, cx + half + 1, rows - h + r + 1, col if r % 2 == 0 else col.darkened(0.1), cols, rows)
		_f(o, cx - 1, rows - 3, cx + 1, rows, SetPieceArt.SHADOW, cols, rows)
		_f(o, cx, rows - h - 2, cx + 1, rows - h, SetPieceArt.WOOD, cols, rows)

static func _hospital(o, cols, rows):
	_f(o, 1, rows / 3, cols - 1, rows, Color(0.82, 0.82, 0.78), cols, rows)
	for r in range(rows / 3):
		_f(o, 1 + (rows / 3 - r), r + 1, cols - 1 - (rows / 3 - r), r + 2, Color(0.88, 0.88, 0.84), cols, rows)
	_f(o, cols / 2 - 1, rows / 3 + 2, cols / 2 + 1, rows / 3 + 7, Color(0.75, 0.15, 0.15), cols, rows) # red cross
	_f(o, cols / 2 - 3, rows / 3 + 4, cols / 2 + 3, rows / 3 + 6, Color(0.75, 0.15, 0.15), cols, rows)
	_f(o, cols - 8, rows - 5, cols - 2, rows, SetPieceArt.OLIVE, cols, rows) # ambulance
	_f(o, 3, rows - 5, 8, rows - 1, SetPieceArt.SHADOW, cols, rows)

static func _supplies(o, cols, rows, rng):
	for k in range(7):
		var c = rng.randi() % maxi(1, cols - 9)
		var r = rows / 4 + (rng.randi() % maxi(1, rows * 3 / 4 - 6))
		var col = [SetPieceArt.WOOD, SetPieceArt.OLIVE, SetPieceArt.RUST, SetPieceArt.CONCRETE_D][rng.randi() % 4]
		_f(o, c, r, c + 9, r + 6, col, cols, rows)
		_f(o, c, r, c + 9, r + 2, col.lightened(0.2), cols, rows)
		_f(o, c + 3, r + 2, c + 4, r + 6, col.darkened(0.25), cols, rows)
	_f(o, 0, rows - 1, cols, rows, Color(0.35, 0.3, 0.22), cols, rows)

static func _radar(o, cols, rows):
	_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows / 2, SetPieceArt.TIN, cols, rows)
	for i in range(6):
		_f(o, cols / 2 - 8 + i, 2 + i / 2, cols / 2 + 8 - i, 3 + i / 2, SetPieceArt.TIN.lightened(0.1 * (i % 2)), cols, rows) # dish
	_f(o, cols / 2 - 1, 2, cols / 2 + 1, rows / 3, SetPieceArt.RUST, cols, rows)
	_f(o, cols / 2, 0, cols / 2 + 1, 3, SetPieceArt.GOLD, cols, rows)

static func _mast(o, cols, rows):
	_f(o, cols / 2 - 1, 2, cols / 2 + 1, rows, SetPieceArt.TIN, cols, rows)
	for r in range(6, rows - 3, 6):
		_f(o, cols / 2 - 4 + r / 6, r, cols / 2 + 4 - r / 6, r + 1, SetPieceArt.TIN.darkened(0.2), cols, rows) # stays
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, 2, Color(0.8, 0.2, 0.2), cols, rows) # beacon
	_f(o, cols / 2 - 4, rows - 4, cols / 2 + 4, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2 - 3, rows - 3, cols / 2 + 3, rows - 1, SetPieceArt.OLIVE, cols, rows)

# ---- power ---------------------------------------------------------------------------------------------------------------
static func _pylon(o, cols, rows):
	for r in range(2, rows):
		var half = 1 + r * (cols / 2 - 2) / rows
		_f(o, cols / 2 - half, r, cols / 2 - half + 1, r + 1, SetPieceArt.TIN.darkened(0.25), cols, rows)
		_f(o, cols / 2 + half - 1, r, cols / 2 + half, r + 1, SetPieceArt.TIN.darkened(0.25), cols, rows)
		if r % 5 == 0:
			_f(o, cols / 2 - half, r, cols / 2 + half, r + 1, SetPieceArt.TIN.darkened(0.35), cols, rows)
	_f(o, 1, 4, cols - 1, 5, SetPieceArt.TIN.darkened(0.3), cols, rows) # cross arms
	_f(o, 0, 8, cols, 9, SetPieceArt.TIN.darkened(0.3), cols, rows)
	for c in [1, cols - 2, cols / 2]:
		_f(o, c, 5, c + 1, 7, SetPieceArt.STONE_L, cols, rows) # insulators

static func _substation(o, cols, rows):
	_f(o, 0, rows - 2, cols, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, 1, rows / 2, cols / 2, rows - 2, SetPieceArt.CONCRETE, cols, rows) # control hut
	_f(o, 3, rows / 2 + 2, cols / 2 - 2, rows - 3, SetPieceArt.SHADOW, cols, rows)
	for c in range(cols / 2 + 2, cols - 3, 6):
		_f(o, c, rows / 3, c + 4, rows - 3, SetPieceArt.TIN.darkened(0.1), cols, rows) # transformers
		_f(o, c + 1, rows / 3 - 3, c + 3, rows / 3, SetPieceArt.STONE_L, cols, rows)
		_f(o, c, rows / 3 + 3, c + 4, rows / 3 + 4, SetPieceArt.RUST, cols, rows)
	_f(o, 0, rows / 3 - 1, cols, rows / 3, SetPieceArt.TIN.darkened(0.3), cols, rows) # bus bar

static func _turbine(o, cols, rows):
	_f(o, cols / 2 - 1, rows / 3, cols / 2 + 1, rows, SetPieceArt.STONE_L, cols, rows)
	_f(o, cols / 2 - 2, rows - 3, cols / 2 + 2, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2 - 2, rows / 3 - 2, cols / 2 + 2, rows / 3, SetPieceArt.TIN, cols, rows) # nacelle
	for i in range(rows / 3):
		_f(o, cols / 2 - i - 1, rows / 3 - 2 - i, cols / 2 - i, rows / 3 - 1 - i, SetPieceArt.STONE_L, cols, rows) # blades
		_f(o, cols / 2 + i, rows / 3 - 2 - i, cols / 2 + i + 1, rows / 3 - 1 - i, SetPieceArt.STONE_L, cols, rows)
		_f(o, cols / 2, rows / 3 - 2 + i, cols / 2 + 1, rows / 3 - 1 + i, SetPieceArt.STONE_L, cols, rows)

static func _solar(o, cols, rows):
	for r in range(2, rows - 2, 5):
		for c in range(1, cols - 5, 7):
			_f(o, c, r, c + 6, r + 4, Color(0.18, 0.26, 0.45), cols, rows)
			_f(o, c, r, c + 6, r + 1, Color(0.3, 0.4, 0.6), cols, rows)
			for k in range(c + 1, c + 6, 2):
				_f(o, k, r + 1, k + 1, r + 4, Color(0.14, 0.2, 0.36), cols, rows)
			_f(o, c + 2, r + 4, c + 4, r + 5, SetPieceArt.TIN.darkened(0.3), cols, rows)

# ---- wrecks ---------------------------------------------------------------------------------------------------------------
static func _wreck_tank(o, cols, rows):
	_f(o, 1, rows / 2, cols - 1, rows - 2, Color(0.3, 0.28, 0.2), cols, rows) # hull
	_f(o, 0, rows - 4, cols, rows, Color(0.15, 0.15, 0.15), cols, rows) # tracks
	for c in range(1, cols - 1, 2):
		_f(o, c, rows - 3, c + 1, rows - 1, Color(0.25, 0.25, 0.25), cols, rows)
	_f(o, cols / 3, rows / 4, cols * 2 / 3, rows / 2, Color(0.26, 0.24, 0.18), cols, rows) # turret
	_f(o, cols * 2 / 3, rows / 4 + 1, cols - 1, rows / 4 + 3, Color(0.2, 0.2, 0.18), cols, rows) # drooping barrel
	_f(o, cols / 3 + 1, rows / 4 + 1, cols / 3 + 4, rows / 4 + 3, SetPieceArt.SHADOW, cols, rows) # burnt hatch
	_f(o, 2, rows / 2 + 2, 5, rows / 2 + 4, SetPieceArt.RUST, cols, rows)

static func _wreck_truck(o, cols, rows):
	_f(o, 0, rows / 3, cols / 3, rows - 3, SetPieceArt.OLIVE_D, cols, rows) # cab
	_f(o, 1, rows / 3 + 1, cols / 3 - 1, rows / 3 + 4, SetPieceArt.GLASS.darkened(0.4), cols, rows)
	_f(o, cols / 3, rows / 3 + 2, cols, rows - 3, SetPieceArt.OLIVE, cols, rows) # bed
	_f(o, cols / 3, rows / 3 + 2, cols, rows / 3 + 3, SetPieceArt.OLIVE.lightened(0.15), cols, rows)
	for c in [3, cols / 2, cols - 5]:
		_f(o, c, rows - 5, c + 4, rows, Color(0.12, 0.12, 0.12), cols, rows) # wheels
	_f(o, cols / 2, rows / 3 - 1, cols / 2 + 4, rows / 3 + 2, SetPieceArt.RUST, cols, rows)

static func _aircraft(o, cols, rows):
	_f(o, 2, rows / 2 - 2, cols - 8, rows / 2 + 4, SetPieceArt.TIN, cols, rows) # fuselage
	_f(o, cols - 8, rows / 2 - 1, cols, rows / 2 + 2, SetPieceArt.TIN.darkened(0.15), cols, rows) # tail boom
	_f(o, cols - 4, 2, cols - 2, rows / 2, SetPieceArt.TIN.darkened(0.2), cols, rows) # tail fin
	_f(o, cols / 3, 2, cols / 3 + 6, rows - 2, SetPieceArt.TIN.darkened(0.1), cols, rows) # wing
	_f(o, cols / 3 + 6, rows / 2 + 4, cols / 3 + 12, rows - 2, SetPieceArt.TIN.darkened(0.25), cols, rows) # broken wing
	_f(o, 2, rows / 2 - 1, 6, rows / 2 + 1, SetPieceArt.GLASS.darkened(0.3), cols, rows) # cockpit
	_f(o, cols / 2, rows / 2 - 2, cols / 2 + 5, rows / 2 + 1, SetPieceArt.SHADOW, cols, rows) # tear in the hull
	_f(o, 0, rows / 2 + 1, 3, rows / 2 + 3, Color(0.2, 0.2, 0.2), cols, rows)

static func _railcar(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows - 4, SetPieceArt.RUST.darkened(0.1), cols, rows)
	for c in range(2, cols, 4):
		_f(o, c, rows / 3, c + 1, rows - 4, SetPieceArt.RUST.darkened(0.35), cols, rows)
	_f(o, cols / 3, rows / 3 + 2, cols / 3 + 6, rows - 6, SetPieceArt.SHADOW, cols, rows) # open door
	_f(o, 0, rows / 3 - 1, cols, rows / 3, SetPieceArt.CONCRETE_D, cols, rows)
	for c in [3, cols - 8]:
		_f(o, c, rows - 4, c + 5, rows, Color(0.15, 0.15, 0.15), cols, rows)
	_f(o, 0, rows - 1, cols, rows, Color(0.3, 0.27, 0.2), cols, rows)

# ---- agricultural extras ---------------------------------------------------------------------------------------------
static func _windmill(o, cols, rows):
	var bw = cols / 3
	for r in range(rows / 3, rows):
		var half = bw / 2 + (r - rows / 3) / 6
		_f(o, cols / 2 - half, r, cols / 2 + half, r + 1, SetPieceArt.STONE_L if r % 4 else SetPieceArt.STONE, cols, rows)
	_pitch(o, cols / 2 - bw / 2, cols / 2 + bw / 2, rows / 3, 4, SetPieceArt.WOOD, cols, rows)
	_f(o, cols / 2 - 1, rows - 4, cols / 2 + 1, rows, SetPieceArt.SHADOW, cols, rows)
	for k in range(maxi(6, rows / 3)):
		_f(o, cols / 2 + k, rows / 3 - k, cols / 2 + k + 1, rows / 3 - k + 1, SetPieceArt.WOOD.lightened(0.15), cols, rows) # sails
		_f(o, cols / 2 - k, rows / 3 + k / 2, cols / 2 - k + 1, rows / 3 + k / 2 + 1, SetPieceArt.WOOD.lightened(0.15), cols, rows)
		_f(o, cols / 2 + k, rows / 3 + k / 2, cols / 2 + k + 1, rows / 3 + k / 2 + 1, SetPieceArt.WOOD.lightened(0.15), cols, rows)

static func _greenhouse(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows, Color(0.5, 0.75, 0.7, 1.0), cols, rows)
	_pitch(o, 0, cols, rows / 3, rows / 3, Color(0.55, 0.8, 0.75), cols, rows)
	for c in range(0, cols, 4):
		_f(o, c, rows / 3, c + 1, rows, SetPieceArt.TIN, cols, rows) # frames
	_f(o, 0, rows - 3, cols, rows, Color(0.25, 0.45, 0.2), cols, rows) # plants
	for c in range(1, cols - 2, 5):
		_f(o, c, rows - 5, c + 2, rows - 3, Color(0.3, 0.55, 0.25), cols, rows)
	_f(o, 0, rows - 1, cols, rows, SetPieceArt.WOOD, cols, rows)

static func _water_tower(o, cols, rows):
	for c in [2, cols - 3]:
		_f(o, c, rows / 2, c + 1, rows, SetPieceArt.WOOD, cols, rows)
	_f(o, 2, rows * 2 / 3, cols - 2, rows * 2 / 3 + 1, SetPieceArt.WOOD.darkened(0.2), cols, rows)
	_f(o, 0, rows / 6, cols, rows / 2, SetPieceArt.RUST.lightened(0.1), cols, rows) # tank
	_f(o, 1, rows / 6 - 1, cols - 1, rows / 6, SetPieceArt.RUST, cols, rows)
	for r in range(rows / 6 + 1, rows / 2, 3):
		_f(o, 0, r, cols, r + 1, SetPieceArt.RUST.darkened(0.3), cols, rows)
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, rows / 6 - 1, SetPieceArt.TIN, cols, rows)

static func _stable(o, cols, rows):
	_f(o, 0, rows / 3, cols, rows, SetPieceArt.WOOD, cols, rows)
	_pitch(o, 0, cols, rows / 3, rows / 3, Color(0.4, 0.28, 0.2), cols, rows)
	for c in range(2, cols - 3, 6):
		_f(o, c, rows / 2, c + 4, rows, SetPieceArt.WOOD.darkened(0.45), cols, rows) # stalls
		_f(o, c, rows / 2, c + 4, rows / 2 + 1, SetPieceArt.STRAW, cols, rows)
		_f(o, c + 1, rows / 2 + 2, c + 3, rows - 1, SetPieceArt.WOOD.darkened(0.25), cols, rows) # half door
	_f(o, cols / 2 - 1, rows / 3 + 1, cols / 2 + 1, rows / 3 + 3, SetPieceArt.SHADOW, cols, rows)

static func _crib(o, cols, rows):
	_f(o, 1, rows / 3, cols - 1, rows - 3, STRAW_C(), cols, rows)
	for c in range(2, cols - 2, 2):
		_f(o, c, rows / 3, c + 1, rows - 3, SetPieceArt.WOOD.darkened(0.3), cols, rows) # slats
	_pitch(o, 0, cols, rows / 3, rows / 4, SetPieceArt.WOOD, cols, rows)
	for c in [2, cols - 3]:
		_f(o, c, rows - 3, c + 1, rows, SetPieceArt.WOOD.darkened(0.3), cols, rows) # stilts
	_f(o, 0, rows - 1, cols, rows, Color(0.3, 0.26, 0.2), cols, rows)

static func STRAW_C() -> Color:
	return Color(0.78, 0.62, 0.25)

# ---- industrial extras ------------------------------------------------------------------------------------------------
static func _crane(o, cols, rows):
	_f(o, 2, rows / 3, 4, rows, Color(0.85, 0.65, 0.15), cols, rows) # mast
	_f(o, cols - 6, rows / 3, cols - 4, rows, Color(0.85, 0.65, 0.15), cols, rows)
	_f(o, 2, 2, cols - 2, 5, Color(0.9, 0.7, 0.2), cols, rows) # gantry beam
	_f(o, 2, 2, cols - 2, 3, Color(0.95, 0.8, 0.35), cols, rows)
	for r in range(rows / 3, rows - 2, 4):
		_f(o, 2, r, 4, r + 1, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2, 5, cols / 2 + 1, rows / 2, SetPieceArt.CONCRETE_D, cols, rows) # cable
	_f(o, cols / 2 - 2, rows / 2, cols / 2 + 3, rows / 2 + 3, SetPieceArt.RUST, cols, rows) # hook block
	_f(o, 0, rows - 2, cols, rows, SetPieceArt.CONCRETE_D, cols, rows)

static func _refinery(o, cols, rows):
	for i in range(2):
		var c0 = 1 + i * (cols / 2)
		var w = cols / 2 - 3
		_f(o, c0, rows / 6 + i * 2, c0 + w, rows, SetPieceArt.TIN.darkened(0.15 * i), cols, rows)
		for r in range(rows / 6 + 3, rows, 5):
			_f(o, c0, r, c0 + w, r + 1, SetPieceArt.TIN.darkened(0.35), cols, rows)
		_f(o, c0 + w / 2, 0, c0 + w / 2 + 1, rows / 6 + i * 2, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2 - 2, rows / 2, cols / 2 + 2, rows / 2 + 1, SetPieceArt.RUST, cols, rows) # pipe bridge
	_f(o, cols / 2, 0, cols / 2 + 1, 3, Color(0.95, 0.5, 0.15), cols, rows) # flare

static func _warehouse(o, cols, rows):
	_f(o, 0, rows / 4, cols, rows, SetPieceArt.TIN.darkened(0.1), cols, rows)
	_f(o, 0, 0, cols, rows / 4, SetPieceArt.TIN.darkened(0.3), cols, rows)
	for c in range(0, cols, 3):
		_f(o, c, rows / 4, c + 1, rows, SetPieceArt.TIN.darkened(0.3), cols, rows)
	for c in range(3, cols - 8, 12):
		_f(o, c, rows - rows / 3, c + 8, rows, SetPieceArt.CONCRETE_D, cols, rows) # roller doors
		for r in range(rows - rows / 3, rows, 2):
			_f(o, c, r, c + 8, r + 1, SetPieceArt.CONCRETE_D.darkened(0.2), cols, rows)
	_f(o, 0, rows - 1, cols, rows, SetPieceArt.CONCRETE_D, cols, rows)

static func _gasometer(o, cols, rows):
	_f(o, 1, rows / 4, cols - 1, rows, SetPieceArt.TIN.darkened(0.15), cols, rows)
	_f(o, 3, rows / 4 - 2, cols - 3, rows / 4, SetPieceArt.TIN, cols, rows)
	for c in range(3, cols - 2, 4):
		_f(o, c, rows / 4, c + 1, rows, SetPieceArt.TIN.darkened(0.4), cols, rows) # guide frame
	for r in range(rows / 4, rows, 4):
		_f(o, 1, r, cols - 1, r + 1, SetPieceArt.TIN.darkened(0.4), cols, rows)
	_f(o, 0, rows - 2, cols, rows, SetPieceArt.CONCRETE_D, cols, rows)
	_f(o, cols / 2 - 1, 0, cols / 2 + 1, rows / 4 - 2, SetPieceArt.RUST, cols, rows)

# ---- ancient ----------------------------------------------------------------------------------------------------------------
static func _temple(o, cols, rows):
	var sand = Color(0.78, 0.7, 0.52)
	var sand_d = Color(0.62, 0.55, 0.4)
	_f(o, 0, rows - 3, cols, rows, sand_d, cols, rows)
	_f(o, 1, rows - 5, cols - 1, rows - 3, sand, cols, rows)
	_f(o, 0, 2, cols, 5, sand, cols, rows) # entablature
	_f(o, 0, 2, cols, 3, sand.lightened(0.15), cols, rows)
	for c in range(2, cols - 2, 5):
		_f(o, c, 5, c + 3, rows - 5, sand.lightened(0.05), cols, rows)
		_f(o, c, 5, c + 1, rows - 5, sand_d, cols, rows)
		_f(o, c - 1, 5, c + 4, 6, sand, cols, rows)
	_f(o, cols / 2 - 3, rows / 2, cols / 2 + 3, rows - 5, SetPieceArt.SHADOW, cols, rows)

static func _columns(o, cols, rows, rng):
	var sand = Color(0.78, 0.7, 0.52)
	for c in range(1, cols - 3, 6):
		var h = rows / 2 + (rng.randi() % maxi(1, rows / 2 - 2))
		_f(o, c, rows - h, c + 3, rows, sand, cols, rows)
		_f(o, c, rows - h, c + 1, rows, sand.darkened(0.2), cols, rows)
		_f(o, c - 1, rows - h - 1, c + 4, rows - h, sand.lightened(0.1), cols, rows) # broken capital
		_f(o, c, rows - 2, c + 3, rows, sand.darkened(0.25), cols, rows)
	_f(o, 0, rows - 2, cols, rows, Color(0.62, 0.55, 0.4), cols, rows)
	for k in range(4):
		_f(o, 2 + rng.randi() % maxi(1, cols - 6), rows - 3, 6 + rng.randi() % maxi(1, cols - 6), rows - 1, sand.darkened(0.15), cols, rows)

static func _ziggurat(o, cols, rows):
	var sand = Color(0.72, 0.6, 0.42)
	var tiers = 4
	for t in range(tiers):
		var inset = t * (cols / (2 * tiers + 1))
		var r0 = rows - (t + 1) * rows / tiers
		var r1 = rows - t * rows / tiers
		_f(o, inset, r0, cols - inset, r1, sand.darkened(0.08 * t), cols, rows)
		_f(o, inset, r0, cols - inset, r0 + 1, sand.lightened(0.18), cols, rows)
	_f(o, cols / 2 - 2, rows / 2, cols / 2 + 2, rows, sand.darkened(0.3), cols, rows) # stair
	for r in range(rows / 2, rows, 2):
		_f(o, cols / 2 - 2, r, cols / 2 + 2, r + 1, sand.lightened(0.1), cols, rows)
	_f(o, cols / 2 - 2, 0, cols / 2 + 2, 2, SetPieceArt.GOLD, cols, rows)

static func _sandstone_arch(o, cols, rows):
	var rock = Color(0.72, 0.42, 0.28)
	var rock_d = Color(0.55, 0.3, 0.2)
	var leg = maxi(4, cols / 4)
	_f(o, 0, rows / 3, leg, rows, rock, cols, rows)
	_f(o, cols - leg, rows / 3, cols, rows, rock, cols, rows)
	_f(o, 0, rows / 3, 1, rows, rock_d, cols, rows)
	_f(o, cols - 1, rows / 3, cols, rows, rock_d, cols, rows)
	for i in range(cols / 2):
		var y = rows / 3 - int(sqrt(maxf(0.0, float(cols * cols) / 4.0 - float((i - cols / 4) * (i - cols / 4)) * 4.0)) / 6.0)
		_f(o, i, maxi(0, y), i + 1, rows / 3 + 3, rock if i % 2 == 0 else rock.lightened(0.06), cols, rows)
		_f(o, cols - 1 - i, maxi(0, y), cols - i, rows / 3 + 3, rock if i % 2 == 0 else rock.lightened(0.06), cols, rows)
	for r in range(rows / 3, rows, 4):
		_f(o, 0, r, leg, r + 1, rock_d, cols, rows)
		_f(o, cols - leg, r, cols, r + 1, rock_d, cols, rows)
