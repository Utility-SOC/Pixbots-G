extends Node

# Diagnostic: generates one map and writes an overview PNG (ground, set pieces with their era wear, obstacles, zones) so a
# map type can be reviewed by eye without running the game.
#   godot --headless --path . res://scripts/debug/MapPreviewDiag.tscn -- <MapType> <era> <seed> <out.png>
const MapGen = preload("res://scripts/core/MapGenerator.gd")
const DOWN = 8

func _ready():
	var args = OS.get_cmdline_user_args()
	var t = args[0] if args.size() > 0 else "Urban"
	var era = args[1] if args.size() > 1 else ""
	var sd = int(args[2]) if args.size() > 2 else 1234
	var out_path = args[3] if args.size() > 3 else "/tmp/claude-1000/preview.png"
	var m = MapGen.new()
	m.map_type = t
	m.era_override = era if era != "auto" else ""
	m.map_seed = sd
	add_child(m)
	await get_tree().process_frame
	var ts = m.tile_size
	var px = ts / DOWN # pixels per tile in the overview
	var img = Image.create(m.width * px, m.height * px, false, Image.FORMAT_RGBA8)
	var tint = m.ground_tint()
	for ty in range(m.height):
		for tx in range(m.width):
			var c: Color = m._get_biome_color(m.terrain[ty][tx]) * tint
			var dk = m.decor.get(Vector2i(tx, ty), "")
			if dk.begins_with("poppy"):
				c = c.lerp(Color(0.85, 0.15, 0.1), 0.45)
			elif dk == "yellow_road":
				c = Color(0.95, 0.8, 0.2)
			elif dk.begins_with("pool_"):
				c = {"pool_deep": Color(0.05, 0.2, 0.55), "pool_blue": Color(0.1, 0.5, 0.8), "pool_green": Color(0.2, 0.7, 0.55), "pool_yellow": Color(0.9, 0.85, 0.3), "pool_orange": Color(0.9, 0.45, 0.15)}[dk]
			elif dk == "crater" or dk == "scorch":
				c = c.darkened(0.45)
			elif dk == "wire":
				c = Color(0.2, 0.2, 0.22)
			img.fill_rect(Rect2i(tx * px, ty * px, px, px), c)
	for cell in m.obstacles:
		var n = m.obstacles[cell]
		var oc = Color(0.45, 0.45, 0.5)
		match n:
			"Tree": oc = Color(0.05, 0.3, 0.1)
			"Boulder": oc = Color(0.4, 0.4, 0.44)
			"StoneWall", "Wall": oc = Color(0.3, 0.3, 0.36)
			"Fence": oc = Color(0.3, 0.22, 0.12)
			"RuinPart": continue
			"Cactus": oc = Color(0.2, 0.5, 0.2)
			"IceBoulder": oc = Color(0.75, 0.88, 0.95)
		img.fill_rect(Rect2i(cell.x * px, cell.y * px, px, px), oc)
	for spec in m.ruin_specs:
		var style = SetPieces.evolved(spec.get("type", "ruin"), spec.get("era", "prewar"))
		var fp = Vector2(spec.w * ts, spec.h * ts)
		var rects = []
		if SetPieceArt.has_style(style):
			rects = SetPieceEra.apply(SetPieceArt.rects(style, fp, 5), fp, spec.get("era", "prewar"), 5)
		else:
			rects = [[Rect2(Vector2.ZERO, fp), Color(0.55, 0.55, 0.6)]]
		for r in rects:
			var rc: Rect2 = r[0]
			img.fill_rect(Rect2i(spec.x * px + int(rc.position.x / DOWN), spec.y * px + int(rc.position.y / DOWN), maxi(1, int(rc.size.x / DOWN)), maxi(1, int(rc.size.y / DOWN))), r[1])
	for z in m.zones:
		var zc = Color(1, 0.2, 0.2) if z.kind == "fort" else Color(0.2, 0.4, 1)
		img.fill_rect(Rect2i(int(z.pos.x) * px - 3, int(z.pos.y) * px - 3, 7, 7), zc)
	img.fill_rect(Rect2i(m.width / 2 * px - 3, m.height / 2 * px - 3, 7, 7), Color(1, 1, 0)) # spawn
	img.save_png(out_path)
	print("MAPPREVIEW %s era=%s size=%dx%d pieces=%d obstacles=%d decor=%d zones=%d main=%d" % [t, m.era, m.width, m.height, m.ruin_specs.size(), m.obstacles.size(), m.decor.size(), m.zones.size(), m.main_continent_tiles.size()])
	get_tree().quit()
