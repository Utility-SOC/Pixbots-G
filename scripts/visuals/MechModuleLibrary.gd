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
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == "Weapon Mount":
			has_mount = true
		elif t.tile_type == "Shield Generator":
			has_shield = true

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

# Shared shoulder + upper-arm segment every recipe starts from, in the role's
# chassis color so the arm still reads as part of THIS mech before the
# neutral hardware takes over. Deliberately COMPACT (the module is the star,
# and the 32-cell bake canvas caps total reach). Returns the y where the
# module should start.
static func _draw_upper_arm(r, role_color: Color, s: float, sign: float) -> float:
	r.add_fill(_rect(-8.0 * s, -12.0 * s, 16.0 * s, 7.0 * s), role_color.darkened(0.2)) # shoulder block
	r.add_fill(_rect(-5.0 * s, -6.0 * s, 10.0 * s, 9.0 * s), role_color)                # upper arm
	r.add_fill(_ngon(Vector2(0, 3.0 * s), 4.0 * s, 8), role_color.darkened(0.3))        # elbow joint
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
	r.add_fill(_rect(-8.0 * s, y, 16.0 * s, 11.0 * s), GUN_D)                    # receiver
	if detailed:
		r.add_fill(_rect(-8.0 * s, y + 2.0 * s, 16.0 * s, 2.5 * s), GUN_M)       # vent band
	var blen = (12.0 + rng.randf_range(0.0, 3.0)) * s
	r.add_fill(_rect(-5.5 * s, y + 11.0 * s, 11.0 * s, blen), GUN_M)             # barrel housing
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
	r.add_fill(_rect(-11.0 * s, y, 22.0 * s, 11.0 * s), GUN_D)                   # wide receiver
	r.add_fill(_rect(-11.0 * s, y + 2.0 * s, 22.0 * s, 2.5 * s), GUN_M)          # vent band
	var blen = (11.0 + rng.randf_range(0.0, 3.0)) * s
	for side in [-1.0, 1.0]:
		var bx = 5.8 * s * side
		r.add_fill(_rect(bx - 4.2 * s, y + 11.0 * s, 8.4 * s, blen), GUN_M)      # twin housings
		r.add_fill(_rect(bx - 4.2 * s, y + 9.0 * s + blen, 8.4 * s, 3.5 * s), GUN_L) # muzzles
	r.add_fill(_ngon(Vector2(12.0 * s * sign, y + 4.0 * s), 5.0 * s, 8), GUN_L)  # drum
	r.add_fill(_rect(-1.7 * s, y + 4.0 * s, 3.4 * s, 3.4 * s), accent)           # center sensor
	return _rect(-13.0 * s, -12.0 * s, 26.0 * s, y + 15.0 * s + blen + 12.0 * s)

static func arm_sniper(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	r.add_fill(_rect(-6.0 * s, y, 12.0 * s, 9.0 * s), GUN_M)                     # receiver
	var blen = (20.0 + rng.randf_range(0.0, 4.0)) * s
	r.add_fill(_rect(-2.8 * s, y + 7.0 * s, 5.6 * s, blen), GUN_D)               # long barrel
	r.add_fill(_rect(-4.2 * s, y + 5.0 * s + blen, 8.4 * s, 4.0 * s), GUN_M)     # muzzle brake
	var scope_x = 5.0 * s * sign
	r.add_fill(_rect(scope_x - 3.5 * s, y + 1.5 * s, 7.0 * s, 6.5 * s), GUN_L)   # scope (outboard)
	if detailed:
		r.add_fill(_rect(scope_x - 1.7 * s, y + 3.0 * s, 3.4 * s, 3.4 * s), accent) # lens glint
	return _rect(-8.5 * s, -12.0 * s, 17.0 * s, y + 11.0 * s + blen + 12.0 * s)

static func arm_missile_pod(r, role_color: Color, s: float, sign: float, rng: RandomNumberGenerator, accent: Color, detailed: bool = true, cols: int = 2, rows: int = -1) -> PackedVector2Array:
	var y = _draw_upper_arm(r, role_color, s, sign)
	var box_color = role_color.lerp(GUN_M, 0.55).darkened(0.1)
	if rows < 0:
		rows = 2 + (1 if (detailed and rng.randf() < 0.4) else 0)
	var box_w = (4.0 + cols * 9.5) * s
	var box_h = (5.0 + rows * 8.0) * s
	r.add_fill(_rect(-box_w / 2.0, y, box_w, box_h), box_color)                  # pod box
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
	r.add_fill(_rect(-8.0 * s, y, 16.0 * s, 10.0 * s), role_color.lerp(GUN_M, 0.4)) # fuel tank
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
	r.add_fill(_rect(-4.5 * s, y, 9.0 * s, 8.0 * s), GUN_M)                      # wrist
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
	r.add_fill(_rect(-3.5 * s, y, 7.0 * s, 14.0 * s), role_color.darkened(0.05)) # forearm
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
		"missile_pod": return arm_missile_pod(r, role_color, s, sign, rng, accent, detailed)
		"siege_pod": return arm_siege_pod(r, role_color, s, sign, rng, accent, detailed)
		"projector": return arm_projector(r, role_color, s, sign, rng, accent, detailed)
		"claw": return arm_claw(r, role_color, s, sign, rng, accent, detailed)
		"shield": return arm_shield(r, role_color, s, sign, rng, accent, detailed)
		"beam_blade": return arm_beam_blade(r, role_color, s, sign, rng, accent, detailed)
		_: return arm_manipulator(r, role_color, s, sign, rng, accent, detailed)
