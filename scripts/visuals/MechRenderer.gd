class_name MechRenderer
extends Node2D

const MechPartRenderer = preload("res://scripts/visuals/MechPartRenderer.gd")

var components: Dictionary = {}
var drawn_parts: Dictionary = {}

# Rarity>=UNCOMMON parts used to each get their own CPUParticles2D. With up
# to 6 parts per mech and ~80 mechs on the field that was potentially
# hundreds of concurrent CPU particle systems. Now every part just
# contributes emission points to ONE shared system per mech.
var _particle_points: Array = []
var _particle_color: Color = Color.WHITE
var _shared_particles: CPUParticles2D = null

func _ready():
	_rebuild_visuals()

func _process(_delta):
	queue_redraw()

func _draw():
	var mech = get_parent()
	if not mech or not "hp" in mech: return

	var bar_width = 40.0
	var bar_height = 4.0
	var y_offset = -40.0

	# Draw background
	draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color.BLACK)

	# Draw HP
	var hp_pct = clamp(mech.hp / max(1.0, mech.max_hp), 0.0, 1.0)
	var hp_color = Color.GREEN if mech.is_player else Color.RED
	draw_rect(Rect2(-bar_width/2, y_offset, bar_width * hp_pct, bar_height), hp_color)

	# Draw Shield
	if mech.max_shield_hp > 0:
		var shld_pct = clamp(mech.shield_hp / max(1.0, mech.max_shield_hp), 0.0, 1.0)
		draw_rect(Rect2(-bar_width/2, y_offset - bar_height - 1, bar_width * shld_pct, bar_height), Color(0.2, 0.6, 1.0))

# -----------------------------------------------------------------------------
# ROLE VISUAL PROFILES
# -----------------------------------------------------------------------------
# Single source of truth for role -> (color, scale, accent) instead of the
# same if/elif chain duplicated in two places. Also gives every combat role
# a distinct look (previously scout/jammer/support silently fell through to
# the generic gray-blue default, indistinguishable from an unbuilt mech).
# Lets Mech.gd size its main collision box to match how big this mech
# actually renders (role-based visual scale, e.g. scout=0.8x, brawler=1.2x)
# instead of every role sharing one fixed hitbox regardless of silhouette
# size. Per-part hitboxes already scale correctly on their own since their
# CollisionPolygon2D is built straight from the same scaled points as the
# visual shape - it was only the main body collision box that didn't.
func get_role_scale(role: String, is_hero: bool) -> float:
	return _get_role_visual_profile("player" if is_hero else role).scale

func _get_role_visual_profile(role: String) -> Dictionary:
	match role:
		"player":
			# The one hero-robot silhouette in a field of mass-production
			# practice bots - bright primary colors instead of the muted
			# military palette everything else gets, and its own "hero"
			# accent (head crest) instead of the baseline Zaku V-fin/pauldron
			# kit the practice bots all share (see _draw_head/_draw_torso).
			return {"color": Color(0.85, 0.15, 0.15), "scale": 1.05, "accent": "hero"}
		"sniper":
			return {"color": Color(0.2, 0.3, 0.6), "scale": 0.9, "accent": "sniper"}
		"brawler":
			return {"color": Color(0.6, 0.2, 0.2), "scale": 1.2, "accent": "brawler"}
		"flamethrower":
			return {"color": Color(0.8, 0.4, 0.1), "scale": 1.0, "accent": "flamethrower"}
		"ambusher":
			return {"color": Color(0.15, 0.15, 0.18), "scale": 0.85, "accent": "ambusher"}
		"scout":
			return {"color": Color(0.5, 0.75, 0.4), "scale": 0.8, "accent": "scout"}
		"jammer":
			return {"color": Color(0.25, 0.15, 0.45), "scale": 1.1, "accent": "jammer"}
		"support":
			return {"color": Color(0.2, 0.7, 0.75), "scale": 1.0, "accent": "support"}
		"boss":
			return {"color": Color(0.1, 0.1, 0.1), "scale": 1.8, "accent": "boss"}
		_:
			return {"color": Color(0.3, 0.4, 0.5), "scale": 1.0, "accent": ""}

func _rebuild_visuals():
	# Clear existing
	for child in get_children():
		child.queue_free()
	drawn_parts.clear()
	_particle_points.clear()
	_shared_particles = null

	var mech = get_parent()
	var role = mech.combat_role if (mech and "combat_role" in mech) else ""
	var is_hero = mech and "is_player" in mech and mech.is_player
	var profile = _get_role_visual_profile("player" if is_hero else role)
	_particle_color = profile.color.lightened(0.3)

	for slot in components.keys():
		var comp = components[slot]
		var rarity_mult = (1.0 + (comp.rarity * 0.05)) * profile.scale

		# Deterministic per-mech random seed so the same mech always looks
		# the same across rebuilds (e.g. re-equipping a different slot).
		var rng = RandomNumberGenerator.new()
		var v_seed = 0
		if mech and "visual_seed" in mech:
			v_seed = mech.visual_seed
		rng.seed = hash(comp.component_name) + comp.rarity + v_seed

		if comp.slot_type == HexTile.BodySlot.TORSO:
			_draw_torso(null, profile.color, rng, rarity_mult, comp.rarity, profile.accent)
		elif comp.slot_type == HexTile.BodySlot.ARM_L:
			_draw_arm(null, profile.color, true, rng, rarity_mult, comp.rarity, profile.accent)
		elif comp.slot_type == HexTile.BodySlot.ARM_R:
			_draw_arm(null, profile.color, false, rng, rarity_mult, comp.rarity, profile.accent)
		elif comp.slot_type == HexTile.BodySlot.LEG_L:
			_draw_leg(null, profile.color, true, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == HexTile.BodySlot.LEG_R:
			_draw_leg(null, profile.color, false, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == HexTile.BodySlot.HEAD:
			_draw_head(null, profile.color, rng, rarity_mult, comp.rarity, profile.accent)

	# Draw standard parts for any slots that weren't overridden by tiles
	var rng_def = RandomNumberGenerator.new()
	rng_def.seed = 12345

	if not drawn_parts.has("Torso"):
		_draw_torso(null, profile.color, rng_def, profile.scale, 0, profile.accent)
	if not drawn_parts.has("Arm_true"):
		_draw_arm(null, profile.color, true, rng_def, profile.scale, 0, profile.accent)
	if not drawn_parts.has("Arm_false"):
		_draw_arm(null, profile.color, false, rng_def, profile.scale, 0, profile.accent)
	if not drawn_parts.has("Leg_true"):
		_draw_leg(null, profile.color, true, rng_def, profile.scale, 0)
	if not drawn_parts.has("Leg_false"):
		_draw_leg(null, profile.color, false, rng_def, profile.scale, 0)
	if not drawn_parts.has("Head"):
		_draw_head(null, profile.color, rng_def, profile.scale, 0, profile.accent)

	_finalize_particles()

# One shared particle system per mech instead of one per high-rarity part.
func _finalize_particles():
	if _particle_points.is_empty():
		return
	var particles = CPUParticles2D.new()
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	particles.emission_points = PackedVector2Array(_particle_points)
	particles.amount = clamp(_particle_points.size() / 2, 8, 40)
	particles.lifetime = 1.0
	particles.gravity = Vector2(0, -10)
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.5
	particles.color = _particle_color
	add_child(particles)
	_shared_particles = particles

# -----------------------------------------------------------------------------
# SHAPE DEFINITIONS
# -----------------------------------------------------------------------------

func _draw_torso(tile, color, rng, scale_mult, rarity, accent: String = ""):
	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		var w = 18.0 * scale_mult
		var h = 22.0 * scale_mult
		pts = PackedVector2Array([
			Vector2(-w*0.8, -h), Vector2(w*0.8, -h),
			Vector2(w, -h*0.3), Vector2(w*0.6, h),
			Vector2(-w*0.6, h), Vector2(-w, -h*0.3)
		])
		var jitter = 3.0 * scale_mult # proportional so small chassis don't jitter into a self-intersecting mess
		for i in range(pts.size()):
			pts[i] += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))

	var body_slot = tile.body_slot if tile else HexTile.BodySlot.TORSO
	var part = _render_mechanical_part(pts, color, Vector2.ZERO, "Torso", body_slot, rarity)

	# Core Reactor Glow - was its own Polygon2D child, now just another fill
	# layer on the part's single draw node.
	var ring = PackedVector2Array()
	for i in range(8):
		var a = i * (PI / 4.0)
		ring.append(Vector2(cos(a), sin(a)) * 8.0 * scale_mult)
	part.renderer.add_fill(ring, color * 1.5)

	# Baseline "practice bot" silhouette - every non-player mech gets blocky
	# shoulder pauldrons (a Zaku/mass-production-suit cue) so the whole
	# roster reads as one family of chassis before role-specific accents on
	# top. The player's hero unit skips this in favor of chest vents.
	if accent == "hero":
		var vent_color = Color(0.9, 0.85, 0.2)
		for side in [-1.0, 1.0]:
			var vx = 6.0 * side * scale_mult
			part.renderer.add_fill(PackedVector2Array([
				Vector2(vx - 1.5, -6 * scale_mult), Vector2(vx + 1.5, -6 * scale_mult),
				Vector2(vx + 1.5, 4 * scale_mult), Vector2(vx - 1.5, 4 * scale_mult)
			]), vent_color)
	else:
		var pauldron_color = color.darkened(0.25)
		for side in [-1.0, 1.0]:
			var px = 14.0 * side * scale_mult
			part.renderer.add_fill(PackedVector2Array([
				Vector2(px - 5 * scale_mult, -16 * scale_mult), Vector2(px + 5 * scale_mult, -16 * scale_mult),
				Vector2(px + 6 * scale_mult, -6 * scale_mult), Vector2(px - 6 * scale_mult, -6 * scale_mult)
			]), pauldron_color)

	if accent == "flamethrower":
		# Exhaust nozzle ring behind the torso
		var nozzle = PackedVector2Array()
		for i in range(10):
			var a = i * (TAU / 10.0)
			nozzle.append(Vector2(cos(a), sin(a)) * 5.0 * scale_mult + Vector2(0, 14 * scale_mult))
		part.renderer.add_fill(nozzle, Color(1.0, 0.5, 0.1))
	elif accent == "support":
		# Small cross/medic marker on the chest
		var cx = 0.0
		var cy = -2.0 * scale_mult
		var s = 4.0 * scale_mult
		part.renderer.add_line(Vector2(cx - s, cy), Vector2(cx + s, cy), Color(0.9, 0.95, 0.95), 2.5)
		part.renderer.add_line(Vector2(cx, cy - s), Vector2(cx, cy + s), Color(0.9, 0.95, 0.95), 2.5)
	part.renderer.finish()

func _draw_arm(tile, color, is_left, rng, scale_mult, rarity, accent: String = ""):
	var sign = -1.0 if is_left else 1.0
	var offset = Vector2(24.0 * sign, -5.0)

	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		var w = 8.0 * scale_mult
		var h = 28.0 * scale_mult
		var is_weapon = (tile != null and tile.get("category") == HexTile.TileCategory.OUTPUT)
		if accent == "sniper" and not is_left:
			h *= 1.4 # Elongated barrel side, matches the long rifle arm shape
		if is_weapon:
			# Weapon/Gun arm
			pts.append_array([
				Vector2(-w, -h*0.5), Vector2(w, -h*0.5),
				Vector2(w, h*0.2), Vector2(w*0.4, h*0.8), Vector2(w*0.4, h),
				Vector2(-w*0.4, h), Vector2(-w*0.4, h*0.8), Vector2(-w, h*0.2)
			])
		else:
			# Structural/Shield arm
			pts.append_array([
				Vector2(-w*1.5, -h*0.3), Vector2(w*1.5, -h*0.3),
				Vector2(w, h*0.8), Vector2(-w, h*0.8)
			])
		# Mirror geometry if left
		if is_left:
			for i in range(pts.size()):
				pts[i].x *= -1

		var jitter = 2.0 * scale_mult
		for i in range(pts.size()):
			pts[i] += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))

	var slot = HexTile.BodySlot.ARM_L if is_left else HexTile.BodySlot.ARM_R
	var body_slot = tile.body_slot if tile else slot
	var part_name = "Arm_" + str(is_left)
	var part = _render_mechanical_part(pts, color, offset, part_name, body_slot, rarity)

	if accent == "sniper" and not is_left:
		# Laser-sight glint at the muzzle tip
		part.renderer.add_fill(PackedVector2Array([
			Vector2(-1.5, 24 * (1.0 + rarity * 0.05)), Vector2(1.5, 24 * (1.0 + rarity * 0.05)),
			Vector2(1.5, 30 * (1.0 + rarity * 0.05)), Vector2(-1.5, 30 * (1.0 + rarity * 0.05))
		]), Color(1.0, 0.2, 0.2))
	part.renderer.finish()

	# Rotate weapons slightly outward
	part.container.rotation = deg_to_rad(15.0 * sign)

func _draw_leg(tile, color, is_left, rng, scale_mult, rarity):
	var sign = -1.0 if is_left else 1.0
	var offset = Vector2(14.0 * sign, 20.0)

	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		var w = 10.0 * scale_mult
		var h = 24.0 * scale_mult
		pts = PackedVector2Array([
			Vector2(-w*0.8, -h*0.5), Vector2(w*0.8, -h*0.5),
			Vector2(w, h*0.5), Vector2(w*1.2, h),
			Vector2(-w*1.2, h), Vector2(-w, h*0.5)
		])
		if is_left:
			for i in range(pts.size()):
				pts[i].x *= -1
		var jitter = 2.0 * scale_mult
		for i in range(pts.size()):
			pts[i] += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))

	var slot = HexTile.BodySlot.LEG_L if is_left else HexTile.BodySlot.LEG_R
	var body_slot = tile.body_slot if tile else slot
	var part = _render_mechanical_part(pts, color, offset, "Leg_" + str(is_left), body_slot, rarity)
	part.renderer.finish()

func _draw_head(tile, color, rng, scale_mult, rarity, accent: String = ""):
	var offset = Vector2(0, -26.0)
	var pts = _get_component_polygon(tile, scale_mult)
	var w = 12.0 * scale_mult
	var h = 10.0 * scale_mult

	if pts.is_empty():
		pts = PackedVector2Array([
			Vector2(-w*0.6, -h), Vector2(w*0.6, -h),
			Vector2(w, h), Vector2(-w, h)
		])
		var jitter = 1.5 * scale_mult
		for i in range(pts.size()):
			pts[i] += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))

	var body_slot = tile.body_slot if tile else HexTile.BodySlot.HEAD
	var part = _render_mechanical_part(pts, color, offset, "Head", body_slot, rarity)

	# Visor - was its own Polygon2D child, now a fill layer. Doubles as the
	# practice bots' "mono-eye" - a single glowing slit is a core Zaku cue.
	var visor_color = color * 1.5
	if accent == "ambusher":
		visor_color = Color(0.6, 0.05, 0.05) # single glowing red slit reads as sneaky/predatory
	elif accent == "jammer":
		visor_color = Color(0.5, 0.2, 0.9)
	elif accent == "hero":
		visor_color = Color(0.3, 0.8, 1.0) # cool cyan "hero visor", not just a tinted mono-eye
	var visor = PackedVector2Array([
		Vector2(-w*0.8, h*0.2), Vector2(w*0.8, h*0.2),
		Vector2(w*0.6, h*0.6), Vector2(-w*0.6, h*0.6)
	])
	part.renderer.add_fill(visor, visor_color)

	if accent == "hero":
		# Low, wide brow crest instead of a single tall spike - a tall
		# center spike read as a "90s anime mohawk," not distinct/heroic.
		# This is closer to the classic mecha-protagonist look: a flat
		# angular ridge across the forehead plus small side fin stubs,
		# still clearly distinct from the practice bots' twin V-fin below
		# but without looking cheesy.
		var crest_h = h * 1.2 * (1.0 + rarity * 0.05)
		part.renderer.add_fill(PackedVector2Array([
			Vector2(-w * 0.85, -h), Vector2(w * 0.85, -h),
			Vector2(w * 0.55, -crest_h), Vector2(-w * 0.55, -crest_h)
		]), Color(0.9, 0.85, 0.2))
		for side in [-1.0, 1.0]:
			part.renderer.add_fill(PackedVector2Array([
				Vector2(w * 0.85 * side, -h * 0.55), Vector2(w * 1.25 * side, -h * 0.7), Vector2(w * 0.85 * side, -h * 0.85)
			]), color.darkened(0.1))
	else:
		# V-fin antenna - the classic mass-production mobile suit silhouette,
		# shared by every practice bot regardless of role.
		var fin_h = h + 9.0 * (1.0 + rarity * 0.08)
		part.renderer.add_fill(PackedVector2Array([
			Vector2(0, -h * 0.4), Vector2(-w * 0.75, -fin_h), Vector2(-w * 0.35, -h * 0.5)
		]), color.darkened(0.15))
		part.renderer.add_fill(PackedVector2Array([
			Vector2(0, -h * 0.4), Vector2(w * 0.75, -fin_h), Vector2(w * 0.35, -h * 0.5)
		]), color.darkened(0.15))

	if accent == "scout":
		# Thin whip antenna on top of the V-fin, reinforces "fast recon"
		part.renderer.add_line(Vector2(0, -h), Vector2(0, -h - 10.0 * (1.0 + rarity * 0.1)), color.lightened(0.4), 1.0)
	part.renderer.finish()

func _get_component_polygon(comp: Node, scale_mult: float) -> PackedVector2Array:
	if not comp or not "valid_hexes" in comp or comp.valid_hexes.is_empty():
		return PackedVector2Array()

	var hex_size = 9.0 * scale_mult
	var union: Array[PackedVector2Array] = []

	for h in comp.valid_hexes:
		var x = hex_size * sqrt(3.0) * (h.q + h.r / 2.0)
		var y = hex_size * 3.0 / 2.0 * h.r

		var poly = PackedVector2Array()
		for i in range(6):
			var angle_rad = deg_to_rad(60 * i + 30)
			poly.append(Vector2(x + hex_size * cos(angle_rad), y + hex_size * sin(angle_rad)))
		union.append(poly)

	var changed = true
	while changed:
		changed = false
		var next_union: Array[PackedVector2Array] = []
		while union.size() > 0:
			var p1 = union.pop_back()
			var merged = false
			for i in range(union.size()):
				var res = Geometry2D.merge_polygons(p1, union[i])
				if res.size() == 1:
					union[i] = res[0]
					merged = true
					changed = true
					break
			if not merged:
				next_union.append(p1)
		union = next_union

	if union.size() > 0:
		# Recenter polygon
		var pts = union[0]
		var center = Vector2.ZERO
		for p in pts:
			center += p
		center /= pts.size()
		for i in range(pts.size()):
			pts[i] -= center
		return pts

	return PackedVector2Array()

# -----------------------------------------------------------------------------
# CORE RENDER PIPELINE
# -----------------------------------------------------------------------------

# Returns a small struct-like dict-free wrapper: a Node2D "container" (kept
# for external code like rotate_arms()/WeaponMountTile.get_muzzle_position(),
# which expect drawn_parts[...] to be a real positioned/rotatable node) whose
# only children are ONE MechPartRenderer (all fills/lines) and, still, a real
# Area2D hitbox (that one has to stay a real node - physics needs it).
class PartHandle:
	var container: Node2D
	var renderer: MechPartRenderer

func _render_mechanical_part(pts: PackedVector2Array, energy_color: Color, offset: Vector2, part_name: String, body_slot: int, rarity: int = 0) -> PartHandle:
	var container = Node2D.new()
	container.position = offset
	container.name = part_name

	var part_renderer = MechPartRenderer.new()
	part_renderer.name = part_name + "_Draw"
	container.add_child(part_renderer)

	# Complex Edges for RARE and LEGENDARY
	if rarity >= HexTile.Rarity.RARE and pts.size() >= 3:
		var new_pts = PackedVector2Array()
		var center = Vector2.ZERO
		for p in pts: center += p
		center /= pts.size()
		for i in range(pts.size()):
			var p1 = pts[i]
			var p2 = pts[(i+1)%pts.size()]
			new_pts.append(p1)
			# Add a small notch in the middle of each edge - capped to a
			# fraction of the edge's own length so short edges (small/thin
			# chassis) don't get notched past themselves into a
			# self-intersecting shape.
			var mid = (p1 + p2) / 2.0
			var to_center = (center - mid).normalized()
			var notch_depth = min(3.0, p1.distance_to(p2) * 0.3)
			new_pts.append(mid + to_center * notch_depth)
		pts = new_pts

	# 1. Energy Sub-layer (Glow/Bleed)
	part_renderer.add_fill(pts, energy_color)

	# Particles for high rarity components now just contribute emission
	# points to ONE shared system built after all parts are drawn.
	if rarity >= HexTile.Rarity.UNCOMMON:
		for p in pts:
			_particle_points.append(p + offset)

	# 2. Armor Super-layer (Directional Shaded Metal)
	var base_armor_color = Color(0.3, 0.35, 0.38) # Slate metal grey
	if rarity >= HexTile.Rarity.LEGENDARY:
		base_armor_color = Color(0.18, 0.20, 0.23) # Darker, sleeker for legendary

	# Shrink the armor slightly so the energy bleeds out the edges
	var shrunk_pts = _shrink_polygon(pts, 3.0)
	part_renderer.add_fill(shrunk_pts, base_armor_color)

	# Greebling (Extra armor plates) for UNCOMMON+
	if rarity >= HexTile.Rarity.UNCOMMON:
		part_renderer.add_fill(_shrink_polygon(pts, 6.0), base_armor_color.lightened(0.15))

		if rarity >= HexTile.Rarity.RARE:
			part_renderer.add_fill(_shrink_polygon(pts, 9.0), base_armor_color.darkened(0.1))

	# Energy Lines for RARE+
	if rarity >= HexTile.Rarity.RARE:
		var center_poly = _shrink_polygon(pts, 12.0)
		if center_poly.size() > 0:
			var loop_pts = center_poly.duplicate()
			loop_pts.append(center_poly[0]) # close loop
			part_renderer.add_loop(loop_pts, energy_color.lightened(0.4), 1.5)

	# 3. Highlight / Shadow lines (Faux 3D bevel)
	for i in range(shrunk_pts.size()):
		var p1 = shrunk_pts[i]
		var p2 = shrunk_pts[(i + 1) % shrunk_pts.size()]
		# Skip very short edges
		if p1.distance_to(p2) < 2.0: continue

		var edge_normal = (p2 - p1).orthogonal().normalized()

		# If normal points up/left, it's a highlight. Down/right is shadow.
		var light_dir = Vector2(-0.5, -0.8).normalized()
		var dot = edge_normal.dot(light_dir)

		var line_color: Color
		if dot > 0.2:
			line_color = Color(0.6, 0.65, 0.7) # Highlight
		elif dot < -0.2:
			line_color = Color(0.1, 0.15, 0.18) # Shadow
		else:
			line_color = Color(0.2, 0.25, 0.28) # Mid-tone

		part_renderer.add_line(p1, p2, line_color, 2.0)

	part_renderer.finish()

	# 4. Physical Hitbox (Area2D) - stays a real node, physics needs it.
	var area = load("res://scripts/entities/PartHitbox.gd").new()
	area.name = "Hitbox"
	area.mech = get_parent()
	area.body_slot = body_slot
	area.collision_layer = get_parent().collision_layer
	area.collision_mask = 0 # It just receives hits

	var shape = CollisionPolygon2D.new()
	shape.polygon = pts
	area.add_child(shape)
	container.add_child(area)

	add_child(container)
	drawn_parts[part_name] = container

	var handle = PartHandle.new()
	handle.container = container
	handle.renderer = part_renderer
	return handle

func _shrink_polygon(pts: PackedVector2Array, amount: float) -> PackedVector2Array:
	if pts.is_empty():
		return pts

	var center = Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()

	# Cap the shrink amount to a fraction of the polygon's smallest
	# centroid-to-vertex distance. Fixed pixel shrink amounts (3/6/9/12px)
	# were fine on the original ~18-28px shapes, but small/thin chassis
	# (scout, ambusher, sniper - scale_mult well under 1.0) or already-thin
	# hex-derived shapes could shrink past their own center, producing an
	# inverted/self-intersecting polygon that fails triangulation.
	var min_radius = INF
	for p in pts:
		min_radius = min(min_radius, p.distance_to(center))
	var safe_amount = min(amount, max(0.5, min_radius * 0.6))

	var new_pts = PackedVector2Array()
	for p in pts:
		var dir = (p - center).normalized()
		new_pts.append(p - dir * safe_amount)
	return new_pts

func rotate_arms(target_global_pos: Vector2, mech_global_pos: Vector2):
	var dir = mech_global_pos.direction_to(target_global_pos)
	var angle = dir.angle()

	# The default angle is down (PI/2). We want the arm to point at the target.
	# Depending on how the arm was drawn (pointing down by default), we adjust.
	# We drew the arms pointing DOWN (h is positive Y).
	var target_rot = angle - PI/2.0

	if drawn_parts.has("Arm_true"):
		# Smoothly rotate left arm
		var arm_l = drawn_parts["Arm_true"]
		arm_l.rotation = lerp_angle(arm_l.rotation, target_rot, 0.1)

	if drawn_parts.has("Arm_false"):
		# Smoothly rotate right arm
		var arm_r = drawn_parts["Arm_false"]
		arm_r.rotation = lerp_angle(arm_r.rotation, target_rot, 0.1)

func animate_legs(velocity: Vector2, time: float):
	var speed = velocity.length()
	if speed < 10.0:
		# Return to idle
		if drawn_parts.has("Leg_true"):
			drawn_parts["Leg_true"].rotation = lerp_angle(drawn_parts["Leg_true"].rotation, 0.0, 0.1)
		if drawn_parts.has("Leg_false"):
			drawn_parts["Leg_false"].rotation = lerp_angle(drawn_parts["Leg_false"].rotation, 0.0, 0.1)
		return

	# Swing legs back and forth based on time and speed
	var swing = sin(time * speed * 0.02) * 0.4

	if drawn_parts.has("Leg_true"):
		drawn_parts["Leg_true"].rotation = swing
	if drawn_parts.has("Leg_false"):
		drawn_parts["Leg_false"].rotation = -swing
