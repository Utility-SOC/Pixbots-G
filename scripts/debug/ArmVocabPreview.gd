extends Node

# Visual iteration harness for the MechModuleLibrary arm vocabulary: builds
# one mech per (module kind x tier) case, lets MechRenderer bake the parts,
# composites each mech's baked part images into a labeled contact sheet PNG
# (upscaled, nearest-neighbor), and writes it to OUTPUT_PATH for a human
# (or Claude) to actually look at. Pass the output path via the
# ARM_VOCAB_OUT environment variable, else it lands in user://.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const ShieldTileScript = preload("res://scripts/tiles/ShieldTile.gd")
const CELL = 4.5

# [label, tier ("grunt"/"hero"/"boss"), role, arm spec]
# arm spec: "raw" = mount only, "<ELEMENT>" = mount+catalyst, "shield",
# "none" = empty arm component, "bare" = no arm component at all
var cases = [
	["grunt gatling RAW", "grunt", "brawler", "raw"],
	["grunt sniper KINETIC", "grunt", "sniper", "KINETIC"],
	["grunt pod EXPLOSION", "grunt", "brawler", "EXPLOSION"],
	["grunt projector FIRE", "grunt", "flamethrower", "FIRE"],
	["grunt claw (no mount)", "grunt", "scout", "none"],
	["grunt shield", "grunt", "support", "shield"],
	["hero gatling RAW", "hero", "player", "raw"],
	["hero beam blade (no mount)", "hero", "player", "none"],
	["hero sniper PIERCE", "hero", "player", "PIERCE"],
	["boss TWIN gatling RAW", "boss", "brawler", "raw"],
	["boss SIEGE pod EXPLOSION", "boss", "brawler", "EXPLOSION"],
	["boss projector VAMPIRIC", "boss", "flamethrower", "VAMPIRIC"],
]

func _ready():
	var world = Node2D.new()
	add_child(world)

	var tiles_per_mech = 48 # composite canvas in bake cells (arms at +/-28px offset need ~+/-23 cells)
	var cell_px = tiles_per_mech
	var cols = 3
	var rows = int(ceil(cases.size() / float(cols)))
	var sheet = Image.create(cols * cell_px, rows * cell_px, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.13, 0.14, 0.17))

	for i in range(cases.size()):
		var c = cases[i]
		var mech = _build_case_mech(c[1], c[2], c[3])
		world.add_child(mech) # _ready bakes the renderer
		var composite = _composite_mech(mech, tiles_per_mech)
		var dst = Vector2i((i % cols) * cell_px, (i / cols) * cell_px)
		sheet.blend_rect(composite, Rect2i(0, 0, tiles_per_mech, tiles_per_mech), dst)
		print("baked [%d] %s" % [i, c[0]])
		mech.queue_free()

	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	var out = OS.get_environment("ARM_VOCAB_OUT")
	if out == "":
		out = "user://arm_vocab_sheet.png"
	sheet.save_png(out)
	print("PASS: contact sheet written to ", out)
	get_tree().quit()

func _build_case_mech(tier: String, role: String, arm_spec: String) -> Node:
	var mech = MechScript.new()
	mech.visual_seed = 1234
	mech.is_player = (tier == "hero")
	mech.is_boss = (tier == "boss") # set BEFORE add_child so _ready sees it
	mech.combat_role = role if role != "player" else "brawler"
	mech.set_physics_process(false)

	for slot in [HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R]:
		if arm_spec == "bare":
			continue
		var comp = ComponentEquipmentScript.new(slot, HexTile.Rarity.RARE)
		if arm_spec == "shield":
			var sh = ShieldTileScript.new()
			sh.body_slot = slot
			comp.hex_grid.add_tile(HexCoord.new(1, 0), sh)
		elif arm_spec != "none":
			var mount = WeaponMountTileScript.new()
			mount.body_slot = slot
			comp.hex_grid.add_tile(HexCoord.new(1, 0), mount)
			if arm_spec != "raw":
				var cat = CatalystTileScript.new()
				cat.body_slot = slot
				cat.target_synergy = EnergyPacket.element_id(arm_spec)
				comp.hex_grid.add_tile(HexCoord.new(0, 1), cat)
		mech.components[slot] = comp
		mech.add_child(comp)
	return mech

# Blends every baked part sprite into one square image, honoring each part
# container's offset (converted from world px to bake cells).
func _composite_mech(mech: Node, size_cells: int) -> Image:
	var img = Image.create(size_cells, size_cells, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var renderer = mech.get_node_or_null("MechRenderer")
	if not renderer:
		return img
	var center = Vector2i(size_cells / 2, size_cells / 2)
	# Respect z_index like the engine does (arms sit above torso/legs),
	# stable within a layer by insertion order.
	var ordered = []
	for part_name in renderer.drawn_parts:
		ordered.append(renderer.drawn_parts[part_name])
	ordered.sort_custom(func(a, b): return a.z_index < b.z_index)
	for container in ordered:
		for child in container.get_children():
			if child is MechPartRenderer and child._sprite and child._sprite.texture:
				var part_img: Image = child._sprite.texture.get_image()
				var off = Vector2i((container.position / CELL).round()) - Vector2i(16, 16) + center
				img.blend_rect(part_img, Rect2i(0, 0, part_img.get_width(), part_img.get_height()), off)
	return img
