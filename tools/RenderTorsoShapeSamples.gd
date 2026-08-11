extends Node

# One-off visual sanity check (not a regression check, headless-safe -
# pure Image ops, no GPU rendering needed): renders the raw valid_hexes
# FOOTPRINT (not just placed tiles, and not the mech's pixel-art sprite,
# which is a separate hand-authored module-vocabulary system unrelated to
# valid_hexes) for each of the four newly-shaped torso roles, so the new
# shapes can be visually confirmed to read as distinct silhouettes.
# Same axial-to-pixel projection ChampionCard.gd's own blueprint renderer
# uses, just plotting the full footprint instead of only placed tiles.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const OUTPUT_DIR = "res://torso_shape_samples/"
const ROLES = ["", "scout", "sniper", "brawler", "ambusher", "jammer", "anti_missile", "diver", "remediation"]
const CELL_PX = 12

func _ready():
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for role in ROLES:
		for rarity_pair in [["mythic", HexTile.Rarity.MYTHIC], ["common", HexTile.Rarity.COMMON]]:
			var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity_pair[1])
			comp.role_variant = role
			comp.generate_shape()
			var img = _render_footprint(comp)
			var label = role if role != "" else "default"
			img.save_png(OUTPUT_DIR + "torso_" + label + "_" + rarity_pair[0] + ".png")
			print("Saved torso_" + label + "_" + rarity_pair[0] + ".png (" + str(comp.valid_hexes.size()) + " hexes)")
	get_tree().quit(0)

func _render_footprint(comp) -> Image:
	var positions = {}
	var min_px = Vector2.INF
	var max_px = -Vector2.INF
	for h in comp.valid_hexes:
		var pos = Vector2((h.q * 2.0 + h.r) * CELL_PX, h.r * CELL_PX * 1.5)
		positions[h] = pos
		min_px = min_px.min(pos)
		max_px = max_px.max(pos + Vector2(CELL_PX, CELL_PX))

	var pad = 6
	var w = int(ceil(max_px.x - min_px.x)) + pad * 2
	var h_size = int(ceil(max_px.y - min_px.y)) + pad * 2
	var img = Image.create(max(w, 1), max(h_size, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.09, 0.12, 1.0))

	var hub_set = {}
	hub_set[Vector2i(0, 0)] = true
	for d in range(6):
		var n = HexCoord.new(0, 0).neighbor(d)
		hub_set[Vector2i(n.q, n.r)] = true

	for h in comp.valid_hexes:
		var pos = positions[h] - min_px + Vector2(pad, pad)
		var color = Color(0.85, 0.3, 0.9) if hub_set.has(Vector2i(h.q, h.r)) else Color(0.35, 0.55, 1.0)
		img.fill_rect(Rect2i(int(pos.x), int(pos.y), CELL_PX - 1, CELL_PX - 1), color)
	return img
