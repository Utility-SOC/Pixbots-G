extends RefCounted

# Procedural module vocabulary for mech parts - phase 1 of the "make the
# generator look like the reference sheets" plan (arm hardware first).
# Instead of one jittered polygon blob per arm, an arm is now assembled from
# recognizable module recipes (gatling / sniper / missile pod / projector /
# claw / shield / manipulator), chosen from what the component's hex grid
# actually CONTAINS and which synergy dominates its mounts - the sprite
# reports the build.
#
# Every recipe draws into a MechPartRenderer (add_fill/add_line - the same
# primitives the Rust rasterizer consumes, so nothing changes downstream)
# and returns the silhouette polygon for the part's hitbox.
#
# DESIGN RULE - think in bake cells, not pixels: MechPartRenderer rasterizes
# at CELL_SIZE (4.5px) on a 32x32 cell canvas. Any feature thinner than one
# cell dissolves; a gap thinner than one cell merges. All the magic numbers
# below are chosen as cell multiples at scale 1.0 so the shapes still READ
# after rasterization (this is also why the reference sheets work - their
# minimech panels are exactly this chunky).
#
# Coordinate frame (matches the old template arms): arm-local, +Y = down =
# muzzle direction (rotate_arms/get_muzzle_position assume this), origin at
# the shoulder attach. `sign` = -1 for the left arm, +1 for the right -
# passed into recipes so asymmetric bits (ammo drums, scopes) sit on the
# outboard side.

const MechPartRendererScript = preload("res://scripts/visuals/MechPartRenderer.gd")

# Shared gunmetal ramp - weapons stay neutral regardless of role hue, same
# as the reference sheets (colored chassis, grey hardware). Pushed darker/
# lighter than the legs' slate armor (0.3-0.38 band) on purpose - hardware
# drawn in that same band visually merged with the legs.
const GUN_D = Color(0.10, 0.11, 0.14)
const GUN_M = Color(0.24, 0.26, 0.31)
const GUN_L = Color(0.56, 0.60, 0.68)
const WARHEAD = Color(0.85, 0.25, 0.20)

# ---------------------------------------------------------------- picking --

# Decides which arm module a component gets. Returns
# {"kind": String, "synergy": int}. comp may be null (a default stub arm on
# a mech with nothing equipped in that slot) -> bare manipulator.
#
# TIERS (design ruling): regular enemies get smaller, more basic versions
# of the same core library; the player and bosses each also have EXCLUSIVE
# hardware the other never fields:
#   - hero-only: "beam_blade" (an unarmed hero arm ignites an energy blade
#     instead of the grunts' cargo claw - protagonist kit)
#   - boss-only: "twin_gatling" and "siege_pod" (oversized escalations of
#     gatling/missile_pod - a boss never fields the basic version)
# tier: "grunt" (default) | "hero" | "boss"
static func pick_arm_module(comp, mech, slot: int, tier: String = "grunt") -> Dictionary:
	if comp == null or not ("hex_grid" in comp) or comp.hex_grid == null:
		if tier == "hero":
			return {"kind": "beam_blade", "synergy": EnergyPacket.SynergyType.RAW}
		return {"kind": "manipulator", "synergy": EnergyPacket.SynergyType.RAW}

	var has_mount = false
	var has_shield = false
	var has_lance = false
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == "Weapon Mount":
			has_mount = true
		elif t.tile_type == "Lance Mount":
			has_lance = true
		elif t.tile_type == "Shield Generator":
			has_shield = true

	if has_lance:
		return {"kind": "lance", "synergy": _dominant_arm_synergy(comp, mech, slot)}

	if not has_mount:
		if has_shield:
			return {"kind": "shield", "synergy": EnergyPacket.SynergyType.ICE}
		if tier == "hero":
			return {"kind": "beam_blade", "synergy": EnergyPacket.SynergyType.RAW}
		return {"kind": "claw", "synergy": EnergyPacket.SynergyType.RAW}

	var syn = _dominant_arm_synergy(comp, mech, slot)
	var kind: String
	match syn:
		EnergyPacket.SynergyType.KINETIC, EnergyPacket.SynergyType.PIERCE:
			kind = "sniper"
		EnergyPacket.SynergyType.EXPLOSION, EnergyPacket.SynergyType.POISON, EnergyPacket.SynergyType.VORTEX:
			kind = "missile_pod"
		EnergyPacket.SynergyType.FIRE, EnergyPacket.SynergyType.ICE, EnergyPacket.SynergyType.VAMPIRIC:
			kind = "projector"
		_:
			kind = "gatling" # RAW / LIGHTNING / unknown

	# Boss-exclusive escalations of the base kinds.
	if tier == "boss":
		if kind == "gatling":
			kind = "twin_gatling"
		elif kind == "missile_pod":
			kind = "siege_pod"
	return {"kind": kind, "synergy": syn}

# Best available signal for "what element does this arm actually fire":
# the real simulated packets when the grid has been calculated (covers
# cross-component feeds), falling back to a Catalyst scan inside the
# component (covers first-draw before any recalc), else RAW.
static func _dominant_arm_synergy(comp, mech, slot: int) -> int:
	if mech != null and "precalculated_weapons" in mech and not mech.precalculated_weapons.is_empty():
		var totals = {}
		for data in mech.precalculated_weapons:
			if int(data.get("slot_type", -1)) != slot:
				continue
			for k in data.packet.synergies:
				totals[k] = totals.get(k, 0.0) + data.packet.synergies[k]
		var best = -1
		var best_val = 0.0
		for k in totals:
			if totals[k] > best_val:
				best_val = totals[k]
				best = k
		if best >= 0:
			return best

	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == "Catalyst" and "target_synergy" in t:
			return int(t.target_synergy)
	return EnergyPacket.SynergyType.RAW

# ---------------------------------------------------------------- helpers --

static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)
	])

static func _ngon(center: Vector2, radius: float, sides: int = 10) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(sides):
		var a = i * TAU / sides
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

# ------------------------------------------------- shaded primitives -------
# The reference sheets' "injection-molded plastic" read comes from one rule
# applied to EVERY part: a light band on the top face, a dark band on the
# bottom, hard edges (the rasterizer's outline supplies the 1px dark rim).
# These primitives bake that rule in, so recipes get the style by
# construction. Bands are one bake cell (4.5px) - the smallest unit that
# survives rasterization - and are skipped entirely on shapes too small to
# afford them.

const BEVEL = 4.5 # one bake cell

# Beveled box: body + top highlight band + bottom shade band.
static func box(r, x: float, y: float, w: float, h: float, color: Color):
	r.add_fill(_rect(x, y, w, h), color)
	if h >= BEVEL * 3.0 and w >= BEVEL * 2.0:
		r.add_fill(_rect(x, y, w, BEVEL), color.lightened(0.22))
		r.add_fill(_rect(x, y + h - BEVEL, w, BEVEL), color.darkened(0.28))

# Beveled capsule segment (limbs): add_line already rasterizes a true
# capsule (distance-to-segment), so this is a body stroke + a thinner
# highlight stroke offset toward the light.
static func capsule(r, a: Vector2, b: Vector2, radius: float, color: Color):
	r.add_line(a, b, color, radius * 2.0)
	if radius >= BEVEL * 1.4:
		var light_off = Vector2(-0.45, -0.7) * (radius * 0.45)
		r.add_line(a + light_off, b + light_off, color.lightened(0.2), radius * 0.8)

# Ball joint: dark sphere with a top-left glint.
static func joint(r, center: Vector2, radius: float, color: Color):
	r.add_fill(_ngon(center, radius, 8), color.darkened(0.25))
	if radius >= BEVEL:
		r.add_fill(_ngon(center + Vector2(-radius, -radius) * 0.3, radius * 0.35, 6), color.lightened(0.15))

# Dome: hemisphere read - body, inner highlight crescent, specular dot.
# glass=true tints toward the classic blue observation bubble (S3/U3).
static func dome(r, center: Vector2, radius: float, color: Color, glass: bool = false):
	var body = Color(0.45, 0.75, 0.95) if glass else color
	r.add_fill(_ngon(center, radius, 12), body)
	r.add_fill(_ngon(center + Vector2(-radius * 0.25, -radius * 0.3), radius * 0.55, 10), body.lightened(0.25))
	if radius >= BEVEL * 2.0:
		r.add_fill(_ngon(center + Vector2(-radius * 0.35, -radius * 0.45), radius * 0.18, 6), Color(1, 1, 1, 0.9))

# Tread unit: dark rounded block, road wheels, light top run.
static func tread(r, x: float, y: float, w: float, h: float, color: Color):
	r.add_fill(_rect(x, y, w, h), GUN_D)
	r.add_fill(_rect(x, y, w, BEVEL), GUN_M) # top run
	var wheel_r = h * 0.28
	var count = max(2, int(w / (wheel_r * 2.6)))
	for i in range(count):
		var wx = x + wheel_r * 1.4 + (w - wheel_r * 2.8) * (float(i) / max(1, count - 1))
		r.add_fill(_ngon(Vector2(wx, y + h - wheel_r * 1.2), wheel_r, 8), color.darkened(0.1))

# Greebles ---------------------------------------------------------------
static func vents(r, x: float, y: float, w: float, count: int, color: Color):
	for i in range(count):
		r.add_fill(_rect(x, y + i * BEVEL * 1.4, w, BEVEL * 0.7), color.darkened(0.35))

static func sensor_dot(r, pos: Vector2, accent: Color, size: float = 3.0):
	r.add_fill(_rect(pos.x, pos.y, size, size), accent)

# Shared shoulder + upper-arm segment every recipe starts from, in the role's
# chassis color so the arm still reads as part of THIS mech before the
# neutral hardware takes over. Deliberately COMPACT (the module is the star,
# and the 32-cell bake canvas caps total reach). Returns the y where the
# module should start.
static func _draw_upper_arm(r, role_color: Color, s: float, sign: float) -> float:
	box(r, -8.0 * s, -12.0 * s, 16.0 * s, 7.0 * s, role_color.darkened(0.2)) # shoulder block
	box(r, -5.0 * s, -6.0 * s, 10.0 * s, 9.0 * s, role_color)                # upper arm
	joint(r, Vector2(0, 3.0 * s), 4.0 * s, role_color)                       # elbow
	return 3.0 * s

# ---------------------------------------------------------------- recipes --
# Every recipe: (renderer, role_color, s = scale_mult, sign, rng, accent,
# detailed) -> hitbox polygon. `accent` is the dominant synergy's color -
# used for sensor dots / glow tips so the element reads on the weapon
# itself. `detailed` = false for grunts: same core silhouette, but smaller
# (the dispatch shrinks s) and stripped of secondary greebles (ammo drums,
# vent bands, scope glints, hoses) - mass-production hardware.

static func arm_gatling(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -8.0 * s, y, 16.0 * s, 11.0 * s, GUN_D)                               # receiver
	if detailed:
		r.add_fill(_rect(-8.0 * s, y + 2.0 * s, 16.0 * s, 2.5 * s), GUN_M)       # vent band
	var blen = (12.0 + rng.randf_range(0.0, 3.0)) * s
	box(r, -5.5 * s, y + 11.0 * s, 11.0 * s, blen, GUN_M)                        # barrel housing
	r.add_line(Vector2(0, y + 12.0 * s), Vector2(0, y + 10.0 * s + blen), GUN_D, 2.0) # barrel slit
	r.add_fill(_rect(-5.5 * s, y + 9.0 * s + blen, 11.0 * s, 3.5 * s), GUN_L)    # muzzle band
	if detailed:
		r.add_fill(_ngon(Vector2(10.0 * s * sign, y + 4.0 * s), 5.0 * s, 8), GUN_L) # ammo drum (outboard)
		r.add_fill(_rect((8.0 * s if sign > 0 else -11.0 * s), y - 1.0 * s, 3.0 * s, 3.0 * s), accent) # sensor dot
	return _rect(-11.0 * s, -12.0 * s, 22.0 * s, y + 15.0 * s + blen + 12.0 * s)

# BOSS-EXCLUSIVE: twin-linked escalation of the gatling - two housings off
# one wide receiver. A grunt never fields this.
static func arm_twin_gatling(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -11.0 * s, y, 22.0 * s, 11.0 * s, GUN_D)                              # wide receiver
	r.add_fill(_rect(-11.0 * s, y + 2.0 * s, 22.0 * s, 2.5 * s), GUN_M)          # vent band
	var blen = (11.0 + rng.randf_range(0.0, 3.0)) * s
	for side in [-1.0, 1.0]:
		var bx = 5.8 * s * side
		box(r, bx - 4.2 * s, y + 11.0 * s, 8.4 * s, blen, GUN_M)                 # twin housings
		r.add_fill(_rect(bx - 4.2 * s, y + 9.0 * s + blen, 8.4 * s, 3.5 * s), GUN_L) # muzzles
	r.add_fill(_ngon(Vector2(12.0 * s * sign, y + 4.0 * s), 5.0 * s, 8), GUN_L)  # drum
	r.add_fill(_rect(-1.7 * s, y + 4.0 * s, 3.4 * s, 3.4 * s), accent)           # center sensor
	return _rect(-13.0 * s, -12.0 * s, 26.0 * s, y + 15.0 * s + blen + 12.0 * s)

static func arm_sniper(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -6.0 * s, y, 12.0 * s, 9.0 * s, GUN_M)                                # receiver
	var blen = (20.0 + rng.randf_range(0.0, 4.0)) * s
	r.add_fill(_rect(-2.8 * s, y + 7.0 * s, 5.6 * s, blen), GUN_D)               # long barrel
	r.add_fill(_rect(-4.2 * s, y + 5.0 * s + blen, 8.4 * s, 4.0 * s), GUN_M)     # muzzle brake
	var scope_x = 5.0 * s * sign
	r.add_fill(_rect(scope_x - 3.5 * s, y + 1.5 * s, 7.0 * s, 6.5 * s), GUN_L)   # scope (outboard)
	if detailed:
		r.add_fill(_rect(scope_x - 1.7 * s, y + 3.0 * s, 3.4 * s, 3.4 * s), accent) # lens glint
	return _rect(-8.5 * s, -12.0 * s, 17.0 * s, y + 11.0 * s + blen + 12.0 * s)

# Lance Mount (Utility-SOC: "bolt on to the side of the arm, be
# rectangular, long, and look like it has heat sinks on it") - a long
# rectangular housing riding OUTBOARD of the arm (offset by `sign`, not
# inline with the normal barrel axis), pinned on with two mounting
# brackets back to the forearm, with alternating light/dark perpendicular
# heat-sink fins running its length and a glowing emitter tip.
static func arm_lance(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	var mount_x = 8.5 * s * sign
	var lance_w = 6.0 * s
	var lance_len = (32.0 + rng.randf_range(0.0, 6.0)) * s
	var top = y - 3.0 * s
	var left = mount_x - lance_w / 2.0

	# Mounting brackets: span from the arm centerline out to the housing's
	# near edge, whichever direction `sign` points.
	var bracket_x = min(0.0, left)
	var bracket_w = abs(left)
	r.add_fill(_rect(bracket_x, top + 2.0 * s, bracket_w, 3.0 * s), GUN_D)
	r.add_fill(_rect(bracket_x, top + lance_len - 6.0 * s, bracket_w, 3.0 * s), GUN_D)

	box(r, left, top, lance_w, lance_len, GUN_M) # main housing

	# Heat sink fins: short perpendicular ridges, alternating shade so they
	# read as separate plates rather than a stripe pattern.
	var fin_spacing = 3.4 * s
	var fin_count = max(0, int(lance_len / fin_spacing) - 1)
	for i in range(fin_count):
		var fy = top + 5.0 * s + i * fin_spacing
		var shade = GUN_L if i % 2 == 0 else GUN_D
		r.add_line(Vector2(left - 1.5 * s, fy), Vector2(left + lance_w + 1.5 * s, fy), shade, 1.4)

	r.add_fill(_rect(left + 1.0 * s, top + lance_len - 3.5 * s, lance_w - 2.0 * s, 3.5 * s), accent) # emitter tip
	if detailed:
		r.add_fill(_rect(left + 1.5 * s, top + lance_len * 0.45, lance_w - 3.0 * s, 4.0 * s), accent.lightened(0.15)) # power-cell glow

	var min_x = min(-8.5 * s, left - 1.5 * s)
	var max_x = max(8.5 * s, left + lance_w + 1.5 * s)
	var max_y = top + lance_len + 6.0 * s
	return _rect(min_x, -12.0 * s, max_x - min_x, max_y + 12.0 * s)

static func arm_missile_pod(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true, cols: int = 2, rows: int = -1) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	var box_color = role_color.lerp(GUN_M, 0.55).darkened(0.1)
	if rows < 0:
		rows = 2 + (1 if (detailed and rng.randf() < 0.4) else 0)
	var box_w = (4.0 + cols * 9.5) * s
	var box_h = (5.0 + rows * 8.0) * s
	box(r, -box_w / 2.0, y, box_w, box_h, box_color)                             # pod box
	if detailed:
		r.add_fill(_rect(-box_w / 2.0, y, box_w, 2.0 * s), box_color.lightened(0.2)) # top lip
	for row in range(rows):
		for col in range(cols):
			var wx = -box_w / 2.0 + (3.5 + col * 9.5) * s
			var wy = y + (3.0 + row * 8.0) * s
			r.add_fill(_rect(wx, wy, 5.5 * s, 5.5 * s), WARHEAD)                 # warhead tips
	r.add_fill(_rect(-2.5 * s, y + box_h, 5.0 * s, 5.0 * s), GUN_M)              # under-grip
	if detailed:
		r.add_fill(_rect((box_w / 2.0 - 3.0 * s) * sign - 1.5 * s, y - 2.5 * s, 3.0 * s, 2.5 * s), accent) # sensor
	return _rect(-box_w / 2.0 - 1.0 * s, -16.0 * s, box_w + 2.0 * s, y + box_h + 21.0 * s)

# BOSS-EXCLUSIVE: 3-column siege rack (see pick_arm_module).
static func arm_siege_pod(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	return arm_missile_pod(r, role_color, s, sign, rng, accent, true, 3, 3)

static func arm_projector(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -8.0 * s, y, 16.0 * s, 10.0 * s, role_color.lerp(GUN_M, 0.4))        # fuel tank
	if detailed:
		r.add_line(Vector2(7.0 * s * sign, y + 2.0 * s), Vector2(4.0 * s * sign, y + 13.0 * s), GUN_D, 2.0) # hose
	r.add_fill(_rect(-5.0 * s, y + 10.0 * s, 10.0 * s, 7.0 * s), GUN_M)          # throat
	r.add_fill(PackedVector2Array([                                              # flared bell nozzle
		Vector2(-5.0 * s, y + 17.0 * s), Vector2(5.0 * s, y + 17.0 * s),
		Vector2(8.0 * s, y + 26.0 * s), Vector2(-8.0 * s, y + 26.0 * s)
	]), GUN_D)
	r.add_fill(_rect(-3.5 * s, y + 22.5 * s, 7.0 * s, 3.5 * s), accent)          # element glow in the bell
	return _rect(-9.5 * s, -12.0 * s, 19.0 * s, y + 26.0 * s + 12.0 * s)

static func arm_claw(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -4.5 * s, y, 9.0 * s, 8.0 * s, GUN_M)                                 # wrist
	for side in [-1.0, 1.0]:                                                     # two curved prongs
		r.add_fill(PackedVector2Array([
			Vector2(3.0 * s * side, y + 6.0 * s),
			Vector2(9.0 * s * side, y + 12.0 * s),
			Vector2(6.5 * s * side, y + 21.0 * s),
			Vector2(2.5 * s * side, y + 15.0 * s)
		]), GUN_L)
		r.add_fill(PackedVector2Array([                                          # prong tips curl inward
			Vector2(6.5 * s * side, y + 21.0 * s),
			Vector2(2.0 * s * side, y + 25.0 * s),
			Vector2(2.5 * s * side, y + 15.0 * s)
		]), GUN_L.darkened(0.15))
	if detailed:
		r.add_fill(_ngon(Vector2(0, y + 4.0 * s), 2.5 * s, 6), accent)           # actuator glow
	return _rect(-10.0 * s, -16.0 * s, 20.0 * s, y + 25.0 * s + 16.0 * s)

static func arm_shield(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	r.add_fill(_rect(-3.5 * s, y, 7.0 * s, 10.0 * s), role_color.darkened(0.1))  # forearm behind shield
	var c = Vector2(2.0 * s * sign, y + 10.0 * s)
	r.add_fill(_ngon(c, 12.0 * s, 12), GUN_L)                                    # shield face
	r.add_fill(_ngon(c, 9.0 * s, 12), GUN_L.darkened(0.12))                      # inner plate
	if detailed:
		r.add_fill(_ngon(c, 2.8 * s, 8), accent)                                 # center boss
	return _rect(-12.0 * s + c.x, -16.0 * s, 24.0 * s, y + 22.0 * s + 16.0 * s)

static func arm_manipulator(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	box(r, -3.5 * s, y, 7.0 * s, 14.0 * s, role_color.darkened(0.05))            # forearm
	r.add_fill(_rect(-4.5 * s, y + 14.0 * s, 4.5 * s, 7.0 * s), GUN_M)           # two chunky fingers
	r.add_fill(_rect(0.5 * s, y + 14.0 * s, 4.5 * s, 5.5 * s), GUN_M)
	return _rect(-6.0 * s, -16.0 * s, 12.0 * s, y + 21.0 * s + 16.0 * s)

# HERO-EXCLUSIVE: an unarmed hero arm ignites an energy blade instead of a
# grunt's cargo claw - the one melee-flavored silhouette in the vocabulary.
static func arm_beam_blade(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	r.add_fill(_rect(-4.0 * s, y, 8.0 * s, 8.0 * s), role_color.darkened(0.05))  # forearm
	r.add_fill(_rect(-5.0 * s, y + 8.0 * s, 10.0 * s, 4.5 * s), GUN_D)           # emitter hilt
	var blade_len = 22.0 * s
	var blade = accent if accent.get_luminance() > 0.25 else Color(0.5, 0.8, 1.0)
	r.add_fill(PackedVector2Array([                                              # tapered energy blade
		Vector2(-3.0 * s, y + 12.5 * s), Vector2(3.0 * s, y + 12.5 * s),
		Vector2(0.0, y + 12.5 * s + blade_len)
	]), blade.lightened(0.2))
	r.add_line(Vector2(0, y + 13.5 * s), Vector2(0, y + 9.5 * s + blade_len), Color(1, 1, 1, 0.9), 2.0) # white-hot core
	return _rect(-6.0 * s, -16.0 * s, 12.0 * s, y + 12.5 * s + blade_len + 16.0 * s)

# Dispatch by kind string (single call site in MechRenderer._draw_arm).
# Grunts field the same core library, just smaller and stripped of
# secondary greebles - the tier ruling lives here so recipes stay dumb.
static func draw_arm_module(kind: String, r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, tier: String = "grunt") -> PackedVector2Array:
	var detailed = tier != "grunt"
	# Global chunk-up: weapons should rival the torso in presence (reference
	# sheets), then grunts shrink back toward mass-production scale.
	s *= 1.35
	if tier == "grunt":
		s *= 0.72
	match kind:
		"gatling": return arm_gatling(r, role_color, s, sign, rng, accent, detailed)
		"twin_gatling": return arm_twin_gatling(r, role_color, s, sign, rng, accent, detailed)
		"sniper": return arm_sniper(r, role_color, s, sign, rng, accent, detailed)
		"lance": return arm_lance(r, role_color, s, sign, rng, accent, detailed)
		"missile_pod": return arm_missile_pod(r, role_color, s, sign, rng, accent, detailed)
		"siege_pod": return arm_siege_pod(r, role_color, s, sign, rng, accent, detailed)
		"projector": return arm_projector(r, role_color, s, sign, rng, accent, detailed)
		"claw": return arm_claw(r, role_color, s, sign, rng, accent, detailed)
		"shield": return arm_shield(r, role_color, s, sign, rng, accent, detailed)
		"beam_blade": return arm_beam_blade(r, role_color, s, sign, rng, accent, detailed)
		_: return arm_manipulator(r, role_color, s, sign, rng, accent, detailed)


# =================================================================== chassis
# Head / locomotion / torso vocabulary (task: chassis anatomy). Same rules
# as the arm recipes: bake-cell-sized features, shaded primitives, hitbox
# polygon returned. Part-local coordinates (the container carries the
# offset), sign mirrors left/right where relevant.

# --- heads -----------------------------------------------------------------
# kind by role/tier: boss -> skull (the references put skulls on the scary
# ones), hero -> mono_eye (the crest accent layers on top), jammer/scout ->
# sensor mast, support/diver -> dome, everyone else mono_eye with a small
# seeded chance of dome/sensor so grunt waves aren't uniform.
static func pick_head_module(role: String, tier: String, rng: RandomNumberGenerator) -> String:
	if tier == "boss":
		return "skull"
	if tier == "hero":
		return "mono_eye"
	match role:
		"jammer", "scout":
			return "sensor"
		"support", "diver":
			return "dome"
		_:
			var roll = rng.randf()
			if roll < 0.12:
				return "dome"
			elif roll < 0.2:
				return "sensor"
			return "mono_eye"

# Every head recipe: (r, role_color, s, visor_color, rng) -> hitbox rect.
# Baseline footprint matches the old template head (w=12s, h=10s) so the
# existing V-fin / whip / boss accents in MechRenderer keep lining up.

static func head_mono_eye(r, color: Color, s: float, visor: Color, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -8.0 * s, -9.0 * s, 16.0 * s, 15.0 * s, color)
	r.add_fill(_rect(-6.5 * s, -2.0 * s, 13.0 * s, 4.5 * s), GUN_D)  # visor slot
	var eye_x = rng.randf_range(-3.0, 3.0) * s
	r.add_fill(_rect(eye_x - 2.2 * s, -1.2 * s, 4.4 * s, 3.0 * s), visor) # the mono-eye
	return _rect(-8.0 * s, -9.0 * s, 16.0 * s, 15.0 * s)

static func head_dome(r, color: Color, s: float, visor: Color, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -7.0 * s, -1.0 * s, 14.0 * s, 6.0 * s, color) # collar
	dome(r, Vector2(0, -4.0 * s), 8.0 * s, color, true)  # glass bubble
	return _rect(-8.0 * s, -12.0 * s, 16.0 * s, 17.0 * s)

static func head_sensor(r, color: Color, s: float, visor: Color, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -5.5 * s, -7.0 * s, 11.0 * s, 13.0 * s, color)
	r.add_fill(_rect(-4.0 * s, -3.0 * s, 8.0 * s, 3.0 * s), GUN_D)
	sensor_dot(r, Vector2(-1.5 * s, -2.5 * s), visor, 3.0 * s)
	r.add_line(Vector2(0, -7.0 * s), Vector2(0, -15.0 * s), GUN_L, 2.0)          # mast
	r.add_line(Vector2(-4.0 * s, -13.0 * s), Vector2(4.0 * s, -13.0 * s), GUN_L, 2.0) # crossbar
	r.add_fill(_ngon(Vector2(3.5 * s, -11.0 * s), 3.0 * s, 8), GUN_M)            # side dish blob
	return _rect(-6.0 * s, -16.0 * s, 12.0 * s, 22.0 * s)

const BONE = Color(0.86, 0.84, 0.76)

static func head_skull(r, color: Color, s: float, visor: Color, rng: RandomNumberGenerator) -> PackedVector2Array:
	r.add_fill(_ngon(Vector2(0, -4.0 * s), 8.0 * s, 10), BONE)                   # cranium
	r.add_fill(_ngon(Vector2(-2.5 * s, -7.0 * s), 3.0 * s, 8), BONE.lightened(0.15)) # brow highlight
	box(r, -5.0 * s, 1.0 * s, 10.0 * s, 5.0 * s, BONE.darkened(0.12))            # jaw
	for side in [-1.0, 1.0]:                                                     # eye sockets
		r.add_fill(_rect(4.0 * s * side - 2.2 * s, -6.5 * s, 4.4 * s, 4.0 * s), Color(0.05, 0.05, 0.07))
		r.add_fill(_rect(4.0 * s * side - 1.1 * s, -5.5 * s, 2.2 * s, 2.0 * s), visor) # glow
	for i in range(3):                                                           # teeth gaps
		r.add_fill(_rect(-3.5 * s + i * 3.0 * s, 3.0 * s, 1.2 * s, 3.0 * s), Color(0.05, 0.05, 0.07))
	return _rect(-8.0 * s, -12.0 * s, 16.0 * s, 18.0 * s)

static func draw_head_module(kind: String, r, color: Color, s: float, visor: Color, rng: RandomNumberGenerator) -> PackedVector2Array:
	match kind:
		"dome": return head_dome(r, color, s, visor, rng)
		"sensor": return head_sensor(r, color, s, visor, rng)
		"skull": return head_skull(r, color, s, visor, rng)
		_: return head_mono_eye(r, color, s, visor, rng)

# --- locomotion --------------------------------------------------------------
# Role-weighted, per-SIDE (asymmetric mixes like the S2 reference sheet
# leg+track are allowed for grunts at a low seeded chance - see
# MechRenderer._leg_kind_for_side). Heroes stay biped - the protagonist
# silhouette is humanoid.
static func pick_leg_module(role: String, tier: String, rng: RandomNumberGenerator) -> String:
	if tier == "hero":
		return "biped"
	var roll = rng.randf()
	match role:
		"brawler", "commander":
			return "tread" if roll < 0.4 else "biped"
		"flamethrower":
			return "tread" if roll < 0.55 else "biped"
		"sniper":
			if roll < 0.55: return "spider"
			return "tread" if roll < 0.7 else "biped"
		"scout":
			if roll < 0.3: return "spider"
			return "hover" if roll < 0.6 else "biped"
		"diver":
			return "hover" if roll < 0.7 else "spider"
		"jammer", "support":
			if roll < 0.3: return "spider"
			return "tread" if roll < 0.5 else "biped"
		_:
			return "biped"

# Every leg recipe: (r, role_color, s, sign, rng) -> hitbox rect.
# Leg-local frame, container at (+/-14, +20); +Y down. animate_legs swings
# biped/spider containers only (see MechRenderer).

static func leg_biped(r, color: Color, s: float, sign: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	capsule(r, Vector2(0, -10.0 * s), Vector2(2.0 * s * sign, 3.0 * s), 4.5 * s, color)      # thigh
	joint(r, Vector2(2.0 * s * sign, 4.0 * s), 3.5 * s, color)                               # knee
	capsule(r, Vector2(2.0 * s * sign, 5.0 * s), Vector2(1.0 * s * sign, 15.0 * s), 3.6 * s, color.darkened(0.08)) # shin
	box(r, -5.0 * s + 2.0 * s * sign, 15.0 * s, 11.0 * s, 6.0 * s, color.darkened(0.2))      # foot
	return _rect(-8.0 * s, -14.0 * s, 16.0 * s, 36.0 * s)

static func leg_tread(r, color: Color, s: float, sign: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -5.0 * s, -10.0 * s, 10.0 * s, 10.0 * s, color)   # suspension pylon
	tread(r, -9.0 * s, 0.0, 18.0 * s, 13.0 * s, color)       # track unit
	return _rect(-9.5 * s, -12.0 * s, 19.0 * s, 26.0 * s)

static func leg_spider(r, color: Color, s: float, sign: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	# two chitin legs per side: out-and-down, then a thinner lower segment
	for leg in [[0.0, 9.0], [4.0, 5.0]]:
		var hip = Vector2(leg[0] * s * sign * 0.4, -8.0 * s + leg[0] * s * 0.5)
		var knee_pt = hip + Vector2(leg[1] * s * sign, 6.0 * s)
		var foot_pt = knee_pt + Vector2(-2.0 * s * sign, 14.0 * s)
		capsule(r, hip, knee_pt, 3.2 * s, color)
		capsule(r, knee_pt, foot_pt, 2.4 * s, color.darkened(0.12))
		joint(r, knee_pt, 2.6 * s, color)
	return _rect(-12.0 * s, -12.0 * s, 26.0 * s, 34.0 * s)

static func leg_hover(r, color: Color, s: float, sign: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -4.0 * s, -10.0 * s, 8.0 * s, 8.0 * s, color)                       # strut
	box(r, -8.0 * s, -2.0 * s, 16.0 * s, 8.0 * s, color.darkened(0.1))         # skirt
	r.add_fill(PackedVector2Array([                                            # skirt taper
		Vector2(-8.0 * s, 6.0 * s), Vector2(8.0 * s, 6.0 * s),
		Vector2(5.0 * s, 10.0 * s), Vector2(-5.0 * s, 10.0 * s)
	]), color.darkened(0.25))
	r.add_fill(_rect(-4.5 * s, 10.0 * s, 9.0 * s, 2.5 * s), Color(0.45, 0.85, 1.0)) # lift glow
	return _rect(-8.5 * s, -12.0 * s, 17.0 * s, 26.0 * s)

static func draw_leg_module(kind: String, r, color: Color, s: float, sign: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	match kind:
		"tread": return leg_tread(r, color, s, sign, rng)
		"spider": return leg_spider(r, color, s, sign, rng)
		"hover": return leg_hover(r, color, s, sign, rng)
		_: return leg_biped(r, color, s, sign, rng)

# --- torso -------------------------------------------------------------------
# Stacked beveled boxes in the ROLE color (the references show colored-
# plastic chassis) instead of the old energy-blob + slate armor treatment.
# Returns the hitbox rect; MechRenderer layers the reactor glow, pauldrons,
# and all role/boss accents on top exactly as before.
static func draw_torso_module(r, color: Color, s: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	box(r, -13.0 * s, -6.0 * s, 26.0 * s, 16.0 * s, color.darkened(0.12)) # hips/abdomen
	box(r, -16.0 * s, -22.0 * s, 32.0 * s, 18.0 * s, color)               # chest
	r.add_fill(_rect(-7.0 * s, -24.0 * s, 14.0 * s, 3.0 * s), color.darkened(0.3)) # collar
	vents(r, 9.0 * s, -14.0 * s, 5.0 * s, 2, color)                        # side vents
	return _rect(-16.0 * s, -24.0 * s, 32.0 * s, 34.0 * s)
