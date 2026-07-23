class_name MechRenderer
extends Node2D

const MechPartRenderer = preload("res://scripts/visuals/MechPartRenderer.gd")
const ModuleLib = preload("res://scripts/visuals/MechModuleLibrary.gd")

var components: Dictionary = {}
var drawn_parts: Dictionary = {}

# Rarity>=UNCOMMON parts used to each get their own CPUParticles2D. With up
# to 6 parts per mech and ~80 mechs on the field that was potentially
# hundreds of concurrent CPU particle systems. Now every part just
# contributes emission points to ONE shared system per mech.
var _particle_points: Array = []
var _particle_color: Color = Color.WHITE
var _shared_particles: CPUParticles2D = null

const MechStatusBars = preload("res://scripts/visuals/MechStatusBars.gd")

# Role-based visual scale of the LAST rebuild (0.8 scout ... 1.8 boss) - the
# status bar layer reads this to push itself high enough to clear the head/
# antenna silhouette on big-scale mechs instead of using one fixed offset
# that only worked for the smallest builds. Set at the bottom of
# _rebuild_visuals().
var last_render_scale: float = 1.0

func _ready():
	_rebuild_visuals()

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
		"diver":
			# Amphibious - teal/aquatic palette distinct from the scout's
			# olive-green, so "this one ignores water" reads at a glance
			# before the player ever sees it actually cross a lake.
			return {"color": Color(0.15, 0.5, 0.55), "scale": 0.8, "accent": "diver"}
		"jammer":
			return {"color": Color(0.25, 0.15, 0.45), "scale": 1.1, "accent": "jammer"}
		"support":
			return {"color": Color(0.2, 0.7, 0.75), "scale": 1.0, "accent": "support"}
		"commander":
			# Was falling through to the generic default before (this role
			# didn't exist yet when the table above was written) - same gap
			# scout/jammer/support used to have. Regal purple/gold, and the
			# tallest baseline scale since Overlord bosses use this role.
			return {"color": Color(0.35, 0.15, 0.45), "scale": 1.3, "accent": "commander"}
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
	var is_boss = mech and "is_boss" in mech and mech.is_boss
	var profile = _get_role_visual_profile("player" if is_hero else role)
	if is_boss:
		# Bosses read as a darker, more armored variant of their base role's
		# palette. On its own that's a subtle tell, but combined with the
		# boss-only silhouette accents added in _draw_torso/_draw_head below
		# (one per role - see the `if is_boss:` blocks there) each of the 6
		# boss archetypes ends up genuinely distinct from both its own grunt
		# and from the other 5 bosses, not just a bigger version of one model.
		profile = profile.duplicate()
		profile.color = profile.color.darkened(0.15)
	_particle_color = profile.color.lightened(0.3)
	last_render_scale = profile.scale

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

		var tier = _tier_of(mech)
		var part_name = ""
		if comp.slot_type == HexTile.BodySlot.TORSO:
			part_name = "Torso"
			_draw_torso(null, _part_color(profile.color, mech, "torso", tier), rng, rarity_mult, comp.rarity, profile.accent, is_boss, comp)
		elif comp.slot_type == HexTile.BodySlot.ARM_L:
			part_name = "Arm_true"
			_draw_arm(null, _part_color(profile.color, mech, "arm_l", tier), true, rng, rarity_mult, comp.rarity, profile.accent, comp)
		elif comp.slot_type == HexTile.BodySlot.ARM_R:
			part_name = "Arm_false"
			_draw_arm(null, _part_color(profile.color, mech, "arm_r", tier), false, rng, rarity_mult, comp.rarity, profile.accent, comp)
		elif comp.slot_type == HexTile.BodySlot.LEG_L:
			part_name = "Leg_true"
			_draw_leg(null, _part_color(profile.color, mech, "leg_l", tier), true, rng, rarity_mult, comp.rarity, comp)
		elif comp.slot_type == HexTile.BodySlot.LEG_R:
			part_name = "Leg_false"
			_draw_leg(null, _part_color(profile.color, mech, "leg_r", tier), false, rng, rarity_mult, comp.rarity, comp)
		elif comp.slot_type == HexTile.BodySlot.HEAD:
			part_name = "Head"
			_draw_head(null, _part_color(profile.color, mech, "head", tier), rng, rarity_mult, comp.rarity, profile.accent, is_boss, comp)

		# Playtest request: "if I have something a bit shieldy but very fast
		# it could be bulky sleek... they need to be visually distinct in
		# spite of the bulk" - a single net bulk-minus-sleek scalar (the
		# previous version of this feature) let a build with both cancel
		# back out to looking neutral, exactly the flattening the user
		# didn't want. bulk and sleek are now two INDEPENDENT axes (see
		# _compute_visual_factors) applied as a genuine anisotropic
		# stretch on the already-drawn part's container - X (width) reads
		# bulk, Y (length) reads sleek, and since neither can go below
		# 1.0, a "bulky AND sleek" build gets both wider AND longer at
		# once instead of averaging to plain. Doesn't touch a single
		# coordinate inside the hand-authored module-vocabulary library -
		# Node2D.scale on the part's container does the whole stretch.
		if part_name != "" and drawn_parts.has(part_name):
			drawn_parts[part_name].scale = _compute_visual_factors(comp)

	# Draw standard parts for any slots that weren't overridden by tiles
	var rng_def = RandomNumberGenerator.new()
	rng_def.seed = 12345

	var def_tier = _tier_of(mech)
	if not drawn_parts.has("Torso"):
		_draw_torso(null, _part_color(profile.color, mech, "torso", def_tier), rng_def, profile.scale, 0, profile.accent, is_boss)
	if not drawn_parts.has("Arm_true"):
		_draw_arm(null, _part_color(profile.color, mech, "arm_l", def_tier), true, rng_def, profile.scale, 0, profile.accent)
	if not drawn_parts.has("Arm_false"):
		_draw_arm(null, _part_color(profile.color, mech, "arm_r", def_tier), false, rng_def, profile.scale, 0, profile.accent)
	if not drawn_parts.has("Leg_true"):
		_draw_leg(null, _part_color(profile.color, mech, "leg_l", def_tier), true, rng_def, profile.scale, 0)
	if not drawn_parts.has("Leg_false"):
		_draw_leg(null, _part_color(profile.color, mech, "leg_r", def_tier), false, rng_def, profile.scale, 0)
	if not drawn_parts.has("Head"):
		_draw_head(null, _part_color(profile.color, mech, "head", def_tier), rng_def, profile.scale, 0, profile.accent, is_boss)

	_finalize_particles()

	# Added LAST so it's the final child in the tree - Godot draws sibling
	# CanvasItems in child order, so being last means this always renders on
	# top of every body part regardless of where its shapes fall vertically.
	# Previously the bars were drawn via this node's OWN _draw(), which (being
	# the parent) rendered BEFORE any of the part children added above -  the
	# head/antenna silhouette painted right over it. See MechStatusBars.gd.
	var bars = MechStatusBars.new()
	bars.owner_mech = mech
	bars.owner_renderer = self
	add_child(bars)

# One shared particle system per mech instead of one per high-rarity part.
func _finalize_particles():
	if _particle_points.is_empty():
		return
	var particles = CPUParticles2D.new()
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	particles.emission_points = PackedVector2Array(_particle_points)
	# Sparse and cell-sized: a few motes at the bake's pixel scale read as
	# an energy aura; dozens of sub-cell dots read as static noise.
	particles.amount = clamp(_particle_points.size() / 3, 4, 12)
	particles.lifetime = 1.2
	particles.gravity = Vector2(0, -10)
	particles.scale_amount_min = MechPartRenderer.CELL_SIZE
	particles.scale_amount_max = MechPartRenderer.CELL_SIZE
	particles.color = Color(_particle_color, 0.75)
	add_child(particles)
	_shared_particles = particles

# -----------------------------------------------------------------------------
# SHAPE DEFINITIONS
# -----------------------------------------------------------------------------

# Parts-bin surplus palette for grunt mechs (design ruling: "mismatch
# grunts!!"): early-wave practice bots are assembled from whatever colors
# the shop bin had, each PART its own material - exactly the S/T/U
# reference-sheet look. Coherence rises with the wave counter (the
# Director fields better-maintained units as the game escalates) until
# ~wave 50 grunts wear clean role colors again. Heroes/bosses always
# coordinated.
const SURPLUS_COLORS = [
	Color(0.45, 0.47, 0.32), # olive drab
	Color(0.62, 0.55, 0.38), # khaki tan
	Color(0.45, 0.47, 0.52), # gunship grey
	Color(0.38, 0.31, 0.26), # rust brown
	Color(0.36, 0.44, 0.38), # drab green
	Color(0.52, 0.48, 0.42), # dust beige
]

func _part_color(base_color: Color, mech, slot_key: String, tier: String) -> Color:
	if tier != "grunt":
		return base_color
	var wave = 1
	var scene = get_tree().current_scene if is_inside_tree() else null
	if scene and "current_wave" in scene:
		wave = scene.current_wave
	var coherence = clamp((wave - 5.0) / 45.0, 0.0, 1.0)
	if coherence >= 1.0:
		return base_color
	var seed_base = mech.visual_seed if (mech and "visual_seed" in mech) else 0
	var crng = RandomNumberGenerator.new()
	crng.seed = hash(str(seed_base) + "|paint|" + slot_key)
	var surplus = SURPLUS_COLORS[crng.randi() % SURPLUS_COLORS.size()]
	# Keep a faint role-hue floor so a sniper still reads as a sniper.
	return surplus.lerp(base_color, 0.15 + 0.85 * coherence)

# Shared tier rule for the module vocabulary (see MechModuleLibrary).
func _tier_of(mech) -> String:
	if mech and mech.get("is_player") == true:
		return "hero"
	if mech and mech.get("is_boss") == true:
		return "boss"
	return "grunt"

func _draw_torso(tile, color, rng, scale_mult, rarity, accent: String = "", is_boss: bool = false, glow_comp = null):
	var body_slot = tile.body_slot if tile else HexTile.BodySlot.TORSO
	var part: PartHandle
	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		# Vocabulary path: stacked beveled boxes in the role color (the
		# reference sheets' colored-plastic chassis). Reactor glow,
		# pauldrons, and role/boss accents layer on top below, unchanged.
		part = _begin_part("Torso", Vector2.ZERO)
		var hitbox_pts = ModuleLib.draw_torso_module(part.renderer, color, scale_mult, rng)
		_attach_part_hitbox(part.container, hitbox_pts, body_slot)
	else:
		part = _render_mechanical_part(pts, color, Vector2.ZERO, "Torso", body_slot, rarity)
	# Layering ruling: torso in front of limbs/backpack, behind the head.
	part.container.z_index = 1

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

	# Boss-only silhouette accents, one per role, layered on top of the
	# regular role accent above. Keyed off boss_profile.base_role (always
	# one of the 6 fixed role strings, even after mutation - see
	# BossProfile.ALL_ROLES), so a given archetype's model stays recognizable
	# across its whole evolutionary lineage instead of changing every time it
	# graduates a mutation. Two of the six (sniper/jammer) are head-mounted
	# instead - see _draw_head.
	if is_boss:
		if accent == "brawler":
			# Warhulk: aggressive triangular spike-crown jutting off both
			# pauldrons, on top of the baseline pauldron block everyone gets.
			for side in [-1.0, 1.0]:
				var spike_x = 14.0 * side * scale_mult
				part.renderer.add_fill(PackedVector2Array([
					Vector2(spike_x - 5 * scale_mult, -16 * scale_mult),
					Vector2(spike_x + 1 * scale_mult, -28 * scale_mult),
					Vector2(spike_x + 5 * scale_mult, -16 * scale_mult)
				]), color.darkened(0.35))
		elif accent == "flamethrower":
			# Incinerator: exposed fuel tank on the back feeding the exhaust
			# ring, with a visible pipe run - reads as "the tank itself is
			# part of the threat," not just a bigger nozzle.
			var tank_w = 6.0 * scale_mult
			var tank_top = 4.0 * scale_mult
			var tank_h = 12.0 * scale_mult
			part.renderer.add_fill(PackedVector2Array([
				Vector2(-tank_w, tank_top), Vector2(tank_w, tank_top),
				Vector2(tank_w * 0.8, tank_top + tank_h), Vector2(-tank_w * 0.8, tank_top + tank_h)
			]), Color(0.22, 0.22, 0.24))
			part.renderer.add_line(Vector2(-tank_w * 0.5, tank_top + tank_h), Vector2(-tank_w * 0.5, tank_top + tank_h + 8.0 * scale_mult), Color(0.85, 0.45, 0.1), 2.0)
			part.renderer.add_line(Vector2(tank_w * 0.5, tank_top + tank_h), Vector2(tank_w * 0.5, tank_top + tank_h + 8.0 * scale_mult), Color(0.85, 0.45, 0.1), 2.0)
		elif accent == "commander":
			# Overlord: a cape/cloak hanging off the back - the "the
			# important one" tell, distinct from any grunt commander escort.
			var cape_w = 15.0 * scale_mult
			var cape_h = 20.0 * scale_mult
			part.renderer.add_fill(PackedVector2Array([
				Vector2(-cape_w, -4 * scale_mult), Vector2(cape_w, -4 * scale_mult),
				Vector2(cape_w * 0.65, cape_h), Vector2(0, cape_h * 1.2), Vector2(-cape_w * 0.65, cape_h)
			]), color.darkened(0.3))
			part.renderer.add_fill(PackedVector2Array([
				Vector2(-cape_w * 0.35, -4 * scale_mult), Vector2(cape_w * 0.35, -4 * scale_mult),
				Vector2(0, cape_h * 0.5)
			]), Color(0.85, 0.65, 0.15))
	_draw_conduit_glows(glow_comp, part, rng, scale_mult)
	part.renderer.finish()

func _draw_arm(tile, color, is_left, rng, scale_mult, rarity, accent: String = "", glow_comp = null):
	var sign = -1.0 if is_left else 1.0
	# Wider/higher than the old blob arms (was 24,-5): module hardware needs
	# to clear the torso and leg mass to read, matching the reference
	# sheets' shoulder-slung weapon stance.
	var offset = Vector2(28.0 * sign, -8.0)

	var slot = HexTile.BodySlot.ARM_L if is_left else HexTile.BodySlot.ARM_R
	var body_slot = tile.body_slot if tile else slot
	var part_name = "Arm_" + str(is_left)
	var part: PartHandle

	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		# Module vocabulary path (see MechModuleLibrary.gd): the arm is
		# assembled from a recognizable hardware recipe picked from what the
		# component grid actually contains (mount + dominant synergy ->
		# gatling/sniper/missile pod/projector; shield gen -> shield; no
		# mount -> claw/manipulator) instead of the old jittered polygon
		# blob. The sprite reports the build.
		# Tier ruling: grunts get smaller, greeble-stripped versions of the
		# same core library; the hero and bosses each have exclusive kinds
		# the other never fields (beam blade / twin gatling + siege pod).
		var mech = get_parent()
		var tier = "grunt"
		if mech and mech.get("is_player") == true:
			tier = "hero"
		elif mech and mech.get("is_boss") == true:
			tier = "boss"
		var module = ModuleLib.pick_arm_module(glow_comp, mech, slot, tier)
		var accent_color = EnergyPacket.get_color_for_synergy(module.synergy)
		part = _begin_part(part_name, offset)
		var hitbox_pts = ModuleLib.draw_arm_module(module.kind, part.renderer, color, scale_mult, sign, rng, accent_color, tier)
		_attach_part_hitbox(part.container, hitbox_pts, body_slot)

		# Rarity feedback (the old blob showed this via energy underlay +
		# rings): RARE+ gets a synergy-colored energy seam on the shoulder
		# block and contributes aura particle points like every other part.
		if rarity >= HexTile.Rarity.RARE:
			part.renderer.add_line(Vector2(-7.0 * scale_mult, -6.5 * scale_mult), Vector2(7.0 * scale_mult, -6.5 * scale_mult), accent_color.lightened(0.3), 2.0)
			_particle_points.append(offset + Vector2(0, -12.0 * scale_mult))
			_particle_points.append(offset + Vector2(0, 12.0 * scale_mult))
	else:
		part = _render_mechanical_part(pts, color, offset, part_name, body_slot, rarity)

	_draw_conduit_glows(glow_comp, part, rng, scale_mult)
	part.renderer.finish()

	# Layering ruling: backpack(-1) < limbs(0) < torso(1) < head(2). Arms
	# sit wide enough (x offset 28) that the weapon hardware clears the
	# torso silhouette while the shoulder tucks behind it.
	part.container.z_index = 0

	# Rotate weapons slightly outward
	part.container.rotation = deg_to_rad(15.0 * sign)

# Locomotion kind for one side: same seeded roll for both sides (so a mech
# is normally symmetric), with a low grunt-only chance that the LEFT side
# swaps to a track - the reference sheets' asymmetric leg+track surplus
# look (S2/T2).
func _leg_kind_for_side(mech, is_left: bool, tier: String, role: String) -> String:
	var leg_rng = RandomNumberGenerator.new()
	var seed_base = mech.visual_seed if (mech and "visual_seed" in mech) else 0
	leg_rng.seed = hash(str(seed_base) + "|legs")
	var kind = ModuleLib.pick_leg_module(role, tier, leg_rng)
	if tier == "grunt" and kind != "tread" and leg_rng.randf() < 0.12 and is_left:
		return "tread"
	return kind

func _draw_leg(tile, color, is_left, rng, scale_mult, rarity, glow_comp = null):
	var sign = -1.0 if is_left else 1.0
	var offset = Vector2(14.0 * sign, 20.0)

	var slot = HexTile.BodySlot.LEG_L if is_left else HexTile.BodySlot.LEG_R
	var body_slot = tile.body_slot if tile else slot
	var part_name = "Leg_" + str(is_left)
	var part: PartHandle

	var pts = _get_component_polygon(tile, scale_mult)
	if pts.is_empty():
		var mech = get_parent()
		var tier = _tier_of(mech)
		var role = mech.combat_role if (mech and "combat_role" in mech) else ""
		var kind = _leg_kind_for_side(mech, is_left, tier, role)
		part = _begin_part(part_name, offset)
		var hitbox_pts = ModuleLib.draw_leg_module(kind, part.renderer, color, scale_mult, sign, rng)
		_attach_part_hitbox(part.container, hitbox_pts, body_slot)
		# animate_legs reads this: treads/hover don't swing like knees do.
		part.container.set_meta("locomotion", kind)
	else:
		part = _render_mechanical_part(pts, color, offset, part_name, body_slot, rarity)

	_draw_conduit_glows(glow_comp, part, rng, scale_mult)
	part.renderer.finish()

func _draw_head(tile, color, rng, scale_mult, rarity, accent: String = "", is_boss: bool = false, glow_comp = null):
	var offset = Vector2(0, -26.0)
	var pts = _get_component_polygon(tile, scale_mult)
	var w = 12.0 * scale_mult
	var h = 10.0 * scale_mult

	# Visor/eye color - doubles as the mono-eye and the skull's socket glow.
	var visor_color = color * 1.5
	if accent == "ambusher":
		visor_color = Color(0.6, 0.05, 0.05) # single glowing red slit reads as sneaky/predatory
	elif accent == "jammer":
		visor_color = Color(0.5, 0.2, 0.9)
	elif accent == "support":
		visor_color = Color(0.3, 0.9, 0.95) # bright cyan sensor glow, reads as "scanning," not combat-red
	elif accent == "diver":
		visor_color = Color(0.3, 0.9, 0.95) # bright aqua, reads as a diving mask/goggle
	elif accent == "hero":
		visor_color = Color(0.3, 0.8, 1.0) # cool cyan "hero visor", not just a tinted mono-eye
	elif accent == "commander":
		visor_color = Color(0.9, 0.7, 0.2) # imperial gold, reads as "the one giving orders"

	var body_slot = tile.body_slot if tile else HexTile.BodySlot.HEAD
	var part: PartHandle
	var head_kind = "template"
	if pts.is_empty():
		# Vocabulary path: head type by role/tier (skull for bosses, sensor
		# mast for jammers/scouts, glass dome for support/divers, mono-eye
		# default). Role accents below layer on top.
		head_kind = ModuleLib.pick_head_module(accent, _tier_of(get_parent()), rng)
		part = _begin_part("Head", offset)
		var hitbox_pts = ModuleLib.draw_head_module(head_kind, part.renderer, color, scale_mult, visor_color, rng)
		_attach_part_hitbox(part.container, hitbox_pts, body_slot)
	else:
		part = _render_mechanical_part(pts, color, offset, "Head", body_slot, rarity)
		var visor = PackedVector2Array([
			Vector2(-w*0.8, h*0.2), Vector2(w*0.8, h*0.2),
			Vector2(w*0.6, h*0.6), Vector2(-w*0.6, h*0.6)
		])
		part.renderer.add_fill(visor, visor_color)
	# Layering ruling: head on top of everything.
	part.container.z_index = 2

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
	elif head_kind in ["template", "mono_eye"]:
		# V-fin antenna - the classic mass-production mobile suit silhouette.
		# Only on the boxy mono-eye heads: domes, sensor masts, and skulls
		# have their own toppers and a V-fin on them reads as clutter.
		var fin_h = h + 9.0 * (1.0 + rarity * 0.08)
		part.renderer.add_fill(PackedVector2Array([
			Vector2(0, -h * 0.4), Vector2(-w * 0.75, -fin_h), Vector2(-w * 0.35, -h * 0.5)
		]), color.darkened(0.15))
		part.renderer.add_fill(PackedVector2Array([
			Vector2(0, -h * 0.4), Vector2(w * 0.75, -fin_h), Vector2(w * 0.35, -h * 0.5)
		]), color.darkened(0.15))

	if accent == "scout" and head_kind in ["template", "mono_eye"]:
		# Thin whip antenna on top of the V-fin, reinforces "fast recon"
		# (the sensor head already carries its own mast).
		part.renderer.add_line(Vector2(0, -h), Vector2(0, -h - 10.0 * (1.0 + rarity * 0.1)), color.lightened(0.4), 1.0)

	# Boss-only silhouette accents for the two archetypes whose tell reads
	# better on the head than the torso (the brawler/flamethrower/commander
	# boss accents live in _draw_torso instead). See the comment there for
	# why this is keyed off role/accent rather than profile_name.
	if is_boss:
		if accent == "sniper":
			# Longshot: a tall targeting mast towering over the silhouette,
			# reads as a dedicated scope/comms array, not just a bigger head.
			var mast_h = h * 2.4
			part.renderer.add_line(Vector2(0, -h * 0.4), Vector2(0, -h * 0.4 - mast_h), color.darkened(0.2), 1.5)
			part.renderer.add_line(Vector2(-w * 0.4, -h * 0.4 - mast_h * 0.65), Vector2(w * 0.4, -h * 0.4 - mast_h * 0.65), color.darkened(0.2), 1.5)
		elif accent == "ambusher":
			# Specter: a trailing cloak-fin behind the head/back - the
			# "phantom" tell, especially striking in the moment it decloaks.
			part.renderer.add_fill(PackedVector2Array([
				Vector2(-w * 0.9, h * 0.3), Vector2(w * 0.9, h * 0.3),
				Vector2(w * 0.5, h * 2.2), Vector2(0, h * 2.6), Vector2(-w * 0.5, h * 2.2)
			]), color.darkened(0.4))
		elif accent == "jammer":
			# Warden: a satellite-dish array on top of the head
			var dish_r = w * 0.9
			var dish = PackedVector2Array()
			for i in range(10):
				var a = PI + i * (PI / 9.0)
				dish.append(Vector2(cos(a), sin(a) * 0.6) * dish_r + Vector2(0, -h - dish_r * 0.3))
			part.renderer.add_fill(dish, color.lightened(0.25))
		elif accent == "support":
			# A smaller, lighter dish than the Warden's - same sensor-array
			# language (this role jams too), scaled down since sensing/
			# healing reads as its secondary function, not its whole identity
			# (see the medic-cross chest accent below for the primary one).
			var dish_r = w * 0.6
			var dish = PackedVector2Array()
			for i in range(8):
				var a = PI + i * (PI / 7.0)
				dish.append(Vector2(cos(a), sin(a) * 0.6) * dish_r + Vector2(0, -h - dish_r * 0.3))
			part.renderer.add_fill(dish, color.lightened(0.35))
		elif accent == "diver":
			# A single dorsal fin along the back-center of the head, instead
			# of a dish/spikes - the clearest silhouette shorthand for
			# "aquatic" available at this pixel scale.
			var fin_w = w * 0.5
			var fin_h = h * 1.1
			var fin = PackedVector2Array([
				Vector2(-fin_w * 0.5, -h * 0.6), Vector2(fin_w * 0.5, -h * 0.6), Vector2(0, -h * 0.6 - fin_h)
			])
			part.renderer.add_fill(fin, color.lightened(0.2))
	_draw_conduit_glows(glow_comp, part, rng, scale_mult)
	part.renderer.finish()

# "Sloppy is fine" per the user - a small SUBSET of a component's Directional
# Conduit tiles glow the color of whatever synergy actually dominated the
# packets that last routed through THAT SPECIFIC conduit (see
# DirectionalConduitTile.last_dominant_synergy's comment) - a build that
# splits FIRE down one conduit and ICE down another shows two differently-
# glowing dots. This is a small discoverable detail meant to reward a close
# look, not a legible routing diagram - positions are NOT mapped to real hex
# coordinates (the rendered silhouette is a hand-authored blob shape with no
# 1:1 mapping back to grid cells - see _get_component_polygon), just a small
# seeded offset within the part's rough footprint. Uses the same seeded rng
# as the rest of the part so a given mech's glow dots stay stable across
# rebuilds instead of re-rolling every re-equip.
# Playtest report: "the appearance of the player's bot needs to vary more -
# it's identical or near identical to the mythic fully upgraded endgame
# one." Root cause - rarity only ever fed a uniform rarity_mult (bigger +
# glowier at higher tiers), so two builds at the same rarity looked the
# same regardless of what was actually equipped, and the SILHOUETTE itself
# never differed by rarity either. This reacts to actual tile COMPOSITION
# per-component instead: heavy/defensive hardware (Shield Generator, Core
# Reactor/Microcore, Accumulator, Missile Rack, Lance Mount) reads bulkier
# (wider); mobility/stealth hardware (Cloak Generator, Jumpjet, Actuator,
# Directional Conduit, Filter) reads sleeker (longer).
#
# Follow-up playtest request: "if I have something a bit shieldy but very
# fast it could be bulky sleek... they need to be visually distinct in
# spite of the bulk." The first version of this feature summed bulk and
# sleek into ONE net scalar, so a build with a healthy amount of both just
# cancelled back out to looking plain - the opposite of what was wanted.
# Bulk and sleek are now two INDEPENDENT axes, each only ever >= 1.0 (never
# a penalty on the other), returned as a Vector2 and applied directly as
# Node2D.scale (x=width from bulk, y=length from sleek) on the part's
# already-drawn container - see the call site in _rebuild_visuals(). A
# "bulky AND sleek" build gets wider AND longer at once, clearly distinct
# from pure-bulk (wide, normal length - stocky), pure-sleek (normal width,
# long - lean), and neutral (1,1) builds alike.
const _BULK_TILE_TYPES = ["Shield Generator", "Core Reactor", "Microcore", "Accumulator", "Missile Rack", "Lance Mount"]
const _SLEEK_TILE_TYPES = ["Cloak Generator", "Jumpjet", "Actuator", "Directional Conduit", "Filter"]
const _AXIS_STEP = 0.03
const _AXIS_MAX = 1.25

func _compute_visual_factors(comp) -> Vector2:
	if not comp or not ("hex_grid" in comp) or not comp.hex_grid:
		return Vector2.ONE
	var bulk_count = 0
	var sleek_count = 0
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type in _BULK_TILE_TYPES:
			bulk_count += 1
		elif t.tile_type in _SLEEK_TILE_TYPES:
			sleek_count += 1
	var bulk_scale = clamp(1.0 + bulk_count * _AXIS_STEP, 1.0, _AXIS_MAX)
	var sleek_scale = clamp(1.0 + sleek_count * _AXIS_STEP, 1.0, _AXIS_MAX)
	return Vector2(bulk_scale, sleek_scale)

func _draw_conduit_glows(comp, part, rng, scale_mult):
	if not comp or not ("hex_grid" in comp) or not comp.hex_grid:
		return
	var conduits = []
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == "Directional Conduit" and t.last_dominant_synergy >= 0:
			conduits.append(t)
	if conduits.is_empty():
		return

	var max_glows = min(2, conduits.size())
	var picked: Dictionary = {}
	var attempts = 0
	while picked.size() < max_glows and attempts < 12:
		attempts += 1
		picked[rng.randi() % conduits.size()] = true

	for idx in picked.keys():
		var conduit = conduits[idx]
		var glow_color = EnergyPacket.get_color_for_synergy(conduit.last_dominant_synergy) * 1.4
		var offset = Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-12.0, 12.0)) * scale_mult
		var glow_pts = PackedVector2Array()
		for i in range(6):
			var a = i * (TAU / 6.0)
			glow_pts.append(offset + Vector2(cos(a), sin(a)) * 3.0 * scale_mult)
		part.renderer.add_fill(glow_pts, glow_color)

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

# Shared part shell: positioned container + its MechPartRenderer, already
# registered in drawn_parts. Used by both the classic blob pipeline
# (_render_mechanical_part) and the module-vocabulary path in _draw_arm,
# which draws its own shapes and attaches its own hitbox afterwards.
func _begin_part(part_name: String, offset: Vector2) -> PartHandle:
	var container = Node2D.new()
	container.position = offset
	container.name = part_name

	var part_renderer = MechPartRenderer.new()
	part_renderer.name = part_name + "_Draw"
	container.add_child(part_renderer)

	add_child(container)
	drawn_parts[part_name] = container

	var handle = PartHandle.new()
	handle.container = container
	handle.renderer = part_renderer
	return handle

# The physical per-part hitbox (Area2D) - stays a real node, physics needs
# it. Split out of _render_mechanical_part so the module path can attach a
# hitbox from its recipe's returned silhouette.
func _attach_part_hitbox(container: Node2D, pts: PackedVector2Array, body_slot: int):
	var area = load("res://scripts/entities/PartHitbox.gd").new()
	area.name = "Hitbox"
	area.mech = get_parent()
	area.body_slot = body_slot
	# Guarded: a real Mech.gd always has collision_layer (it's a
	# CharacterBody2D), but this renderer can also be driven by a lightweight
	# preview stub (ComponentDiagramView's PreviewMechContext, a bare Node2D)
	# that has no such property - reading it unconditionally crashed the
	# Garage's live component preview the instant it tried to rebuild.
	var parent_node = get_parent()
	area.collision_layer = parent_node.collision_layer if parent_node and "collision_layer" in parent_node else 0
	area.collision_mask = 0 # It just receives hits

	var shape = CollisionPolygon2D.new()
	shape.polygon = pts
	area.add_child(shape)
	container.add_child(area)

func _render_mechanical_part(pts: PackedVector2Array, energy_color: Color, offset: Vector2, part_name: String, body_slot: int, rarity: int = 0) -> PartHandle:
	var handle = _begin_part(part_name, offset)
	var part_renderer = handle.renderer

	# Complex Edges for RARE and LEGENDARY.
	# Only notch edges long enough for a notch to read as a deliberate
	# armor cut at the bake's CELL_SIZE (3px cells): a notch on a short edge
	# rasterizes as a lone flickery corner pixel, and with every edge
	# notched the whole silhouette dissolved into zigzag noise - the
	# "fugly legendary" look. Depth is exactly one cell so the cut lands on
	# the pixel grid instead of half-covering cells.
	if rarity >= HexTile.Rarity.RARE and pts.size() >= 3:
		var new_pts = PackedVector2Array()
		var center = Vector2.ZERO
		for p in pts: center += p
		center /= pts.size()
		for i in range(pts.size()):
			var p1 = pts[i]
			var p2 = pts[(i+1)%pts.size()]
			new_pts.append(p1)
			if p1.distance_to(p2) >= MechPartRenderer.CELL_SIZE * 4.0:
				var mid = (p1 + p2) / 2.0
				var to_center = (center - mid).normalized()
				new_pts.append(mid + to_center * MechPartRenderer.CELL_SIZE)
		pts = new_pts

	# 1. Energy Sub-layer (Glow/Bleed)
	part_renderer.add_fill(pts, energy_color)

	# Particles for high rarity components now just contribute emission
	# points to ONE shared system built after all parts are drawn.
	# RARE+ only, and only every third vertex - one point per vertex of a
	# notched polygon carpeted the whole sprite in drifting dots, which read
	# as red noise speckles rather than an energy aura.
	if rarity >= HexTile.Rarity.RARE:
		for i in range(0, pts.size(), 3):
			_particle_points.append(pts[i] + offset)

	# 2. Armor Super-layer (Directional Shaded Metal)
	var base_armor_color = Color(0.3, 0.35, 0.38) # Slate metal grey
	if rarity >= HexTile.Rarity.LEGENDARY:
		base_armor_color = Color(0.18, 0.20, 0.23) # Darker, sleeker for legendary

	# Shrink the armor slightly so the energy bleeds out the edges
	var shrunk_pts = _shrink_polygon(pts, 3.0)
	part_renderer.add_fill(shrunk_pts, base_armor_color)

	# Greebling (Extra armor plate) for UNCOMMON+. Was two extra plates
	# (lightened at 6px, darkened at 9px) - at 3px cells that's concentric
	# one-cell rings of alternating brightness, which reads as banded mush,
	# not layered armor. One subtle inner plate is enough at this resolution.
	if rarity >= HexTile.Rarity.UNCOMMON:
		part_renderer.add_fill(_shrink_polygon(pts, 6.0), base_armor_color.lightened(0.12))

	# Energy Lines for RARE+ - a single one-cell ring of bright energy color
	# is the one accent that DOES read clearly at this scale, so it stays.
	if rarity >= HexTile.Rarity.RARE:
		var center_poly = _shrink_polygon(pts, 12.0)
		if center_poly.size() > 0:
			var loop_pts = center_poly.duplicate()
			loop_pts.append(center_poly[0]) # close loop
			part_renderer.add_loop(loop_pts, energy_color.lightened(0.4), 1.5)

	# NOTE: the old per-edge highlight/shadow "faux 3D bevel" lines are gone.
	# MechPartRenderer's own header says it: at this few pixels the bevel
	# treatment "just looks like noise", and _add_outline() already provides
	# the silhouette read. Three grey line tones criss-crossing a notched
	# polygon at 2px width on a 3px grid was the single biggest contributor
	# to the speckled look on RARE/LEGENDARY parts.

	part_renderer.finish()

	_attach_part_hitbox(handle.container, pts, body_slot)
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
	# Treads and hover skirts don't have knees: they bob subtly instead of
	# swinging (a rotating tank track looks broken). Kind comes from the
	# locomotion meta the vocabulary path stamps on each leg container.
	for leg_name in ["Leg_true", "Leg_false"]:
		if not drawn_parts.has(leg_name):
			continue
		var leg = drawn_parts[leg_name]
		var kind = leg.get_meta("locomotion", "biped")
		var mirror = -1.0 if leg_name == "Leg_false" else 1.0
		if kind == "tread" or kind == "hover":
			leg.rotation = lerp_angle(leg.rotation, 0.0, 0.2)
			var bob = sin(time * clamp(speed, 0.0, 300.0) * 0.015) * 1.2 if speed >= 10.0 else 0.0
			leg.position.y = 20.0 + bob
		elif speed < 10.0:
			leg.rotation = lerp_angle(leg.rotation, 0.0, 0.1)
		else:
			leg.rotation = sin(time * speed * 0.02) * 0.4 * mirror
