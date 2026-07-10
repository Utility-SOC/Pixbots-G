class_name Projectile
extends Area2D


const Trail2D = preload("res://scripts/visuals/Trail2D.gd")
const FireTrail2D = preload("res://scripts/visuals/FireTrail2D.gd")
const PulseRingVisual = preload("res://scripts/attacks/PulseRingVisual.gd")

# --- POISON MINE (Natalia: "poison's projectile behavior needs to change so
# that when combined with other things it makes them into a mine/stationary
# projectile") ------------------------------------------------------------
# A packet with enough POISON in it stops behaving like a normal shot: it
# either sits exactly where it was fired (no KINETIC) or crawls slowly in
# its fired direction (KINETIC present, speed scales with how much), skips
# all the other elements' flight distortions (gravity lob, vortex swirl,
# etc. would look wrong on a stationary blob), and detonates into an AoE
# themed by whichever OTHER synergy is strongest - on expiry (lifetime runs
# out) OR on contact with an enemy, whichever comes first. KINETIC and RAW
# are excluded from theme selection since they're the "is this a missile or
# a mine" mobility stat and the colorless default, not a detonation flavor.
const MINE_POISON_THRESHOLD = 0.15
const MINE_CRAWL_SPEED = 260.0
var _is_poison_mine: bool = false
var _mine_detonated: bool = false

var base_speed: float = 500.0
var final_speed: float = 500.0

# --- Range (Natalia: "kinetic should increase range... everything should
# have basic good range from the outset") -------------------------------
# BASE_RANGE is a generous floor so no build feels short-ranged by default
# (FIRE's much shorter time-based lifetime below still gives it its own
# "short burst" identity independent of this - whichever limit is hit first
# ends the shot). KINETIC is the one stat that explicitly extends this
# further, a clean, attributable "more kinetic = more range" lever - KINETIC's
# whole identity now (range went from "double at full ratio" to triple, and
# the flat projectile-speed bonus it used to also carry moved to PIERCE
# instead, see _calculate_stats() - "armor-piercing round" fits a raw
# velocity bonus better than "range" does).
const BASE_RANGE = 1400.0
const KINETIC_RANGE_BONUS = 2800.0
var max_range: float = BASE_RANGE
var distance_traveled: float = 0.0

var damage: float = 10.0
var is_crit: bool = false
var direction: Vector2 = Vector2.ZERO
var target_direction: Vector2 = Vector2.ZERO
var synergies: Dictionary = {}
var weapon_rarity: int = 0
# Resonator Sync procs carried over from the firing EnergyPacket - see
# EnergyPacket.proc_synergies and _apply_synergy_status_effects() below.
var proc_synergies: Dictionary = {}

var ratios: Dictionary = {}
var total_power: float = 0.0
var final_color: Color = Color.WHITE
# From Mythic AoE-focused Amplifiers (EnergyPacket.aoe_bonus): grows the
# projectile's scale and explosion radius.
var aoe_bonus: float = 0.0

var stat_modifiers: Dictionary = {}

# Modifiers
var pierce_count: int = 1
var is_homing: bool = false
var time_alive: float = 0.0

var visual_node: Node2D
var helix_particles: Array = []
var fired_by_player: bool = true
var source_mech: Node2D = null
# Set true when a Mythic Magnet in Repel mode bounces this shot back at its
# original owner (see Mech.gd's magnet-repel flip block) - carried through to
# apply_damage() so Squad._calculate_fitness can score reflection deaths
# separately from ordinary combat losses (see Mech.gd's took_damage signal).
var was_reflected: bool = false
# Every target _handle_hit() has actually processed (direct hit OR the
# tunneling-sweep below) - see _handle_hit()'s own guard. Never cleared, so
# this also means a projectile can't double-dip the same target twice (e.g.
# if it exits and re-enters the same body's shape) - a reasonable trade-off,
# and not a real loss since pierce_count exists specifically to hit
# multiple DIFFERENT targets, not the same one repeatedly.
var _handled_targets: Dictionary = {}
# Grace window before an off-screen shot gets culled - see the
# OFF-SCREEN CULLING block in _ready() for why this isn't instant anymore.
const OFFSCREEN_GRACE_SEC = 2.0
var _offscreen_cull_timer: Timer = null
# Magnitude-driven size multiplier computed in _build_visuals() (its local
# p_scale) - the actual on-screen shape is scale * visual_scale (self.scale
# is the ratio-driven s_mod from _calculate_stats, visual_node inherits it
# and then multiplies its own polys by p_scale on top). The collision
# hitbox in _ready() used to only apply `scale`, never visual_scale, so a
# big combined/amplified shot (p_scale up to 8x) could visually look like a
# huge blast while its real hitbox stayed tiny - "there are a lot of things
# I should be hitting but am not." Stored here so _ready() can size the
# CollisionShape2D to match what's actually drawn.
var visual_scale: float = 1.0

# Lightning zig-zag state - jagged, held-and-snapped offsets rather than a
# smooth wave, so it actually reads as a bolt (see the LIGHTNING ZIG-ZAG
# section of _physics_process()).
var _lightning_segment_index: int = -1
var _lightning_prev_offset: float = 0.0
var _lightning_target_offset: float = 0.0

# Rust GDExtension flight-math (rust_ext/src/projectile_flight.rs) - checked
# ONCE ever via a static (shared across every live projectile, not
# per-instance) rather than each of the potentially 100+ live projectiles
# doing its own ClassDB lookup. Same checked-then-cached pattern as
# MechPartRenderer.gd's PartRasterizer; falls back to the original GDScript
# math in _physics_process if the extension isn't compiled/loaded.
static var _flight_checked: bool = false
static var _flight_rasterizer = null

static func _ensure_flight_rust():
	if not _flight_checked:
		_flight_checked = true
		if ClassDB.class_exists("ProjectileFlight"):
			_flight_rasterizer = ClassDB.instantiate("ProjectileFlight")

# --- Perf: throttled physics queries -----------------------------------
# With combat spam (radial/shotgun Mythic patterns, several squads all
# firing) it's easy to have 100+ live projectiles at once, and every one of
# these was doing a full PhysicsShapeQueryParameters2D.intersect_shape()
# EVERY SINGLE PHYSICS TICK - that's the actual cost of "too many
# projectiles slogs", not the visuals. None of these three need 60Hz
# precision to look/feel right, so they're throttled to a much cheaper
# refresh rate instead of being cut - the pretty graphics stay untouched.
const HOMING_QUERY_INTERVAL = 0.1 # vampiric/homing target re-acquisition
const VORTEX_QUERY_INTERVAL = 0.05 # nearby-item pull scan
# Below this much travel in one tick, the projectile's own hitbox plus a
# typical small enemy's hitbox still overlap at tick-end, so the normal
# Area2D body_entered/area_entered signals reliably catch the hit on their
# own - the tunneling sweep only matters for shots fast enough to actually
# skip clean through a target inside one tick (kinetic/pierce bonuses,
# lightning's forced 4200+). Was gated at just 4.0px, which meant almost
# EVERY projectile paid for a sweep query almost every tick regardless of
# speed.
const TUNNEL_RISK_MOVE_THRESHOLD = 24.0

var _homing_query_timer: float = 0.0
var _cached_homing_target: Node2D = null
var _vortex_query_timer: float = 0.0

func _ready():
	# Desync throttled queries (Natalia: "freezing is still happening
	# regularly") - every projectile defaulted these timers to 0.0, so every
	# projectile fired in the same volley (a shotgun/radial Mythic pattern,
	# or just several weapons releasing the same tick) ran its first homing/
	# vortex physics query on the exact same frame, and stayed in lockstep
	# on every refresh after that - a thundering herd of shape queries
	# landing together every ~0.05-0.1s instead of spread across frames.
	# Randomizing the starting value only changes WHEN it first fires.
	_homing_query_timer = randf() * HOMING_QUERY_INTERVAL
	_vortex_query_timer = randf() * VORTEX_QUERY_INTERVAL

	# Calculate total power
	for k in synergies:
		total_power += synergies[k]
	if total_power <= 0:
		total_power = 1.0
		ratios[EnergyPacket.SynergyType.RAW] = 1.0
	else:
		for k in synergies:
			ratios[k] = synergies[k] / total_power

	_is_poison_mine = ratios.get(EnergyPacket.SynergyType.POISON, 0.0) > MINE_POISON_THRESHOLD
	# Mines use their own separate movement model (_physics_process_mine) -
	# never registered with the batched flight-math manager, which only
	# ever drives the normal ORGANIC VELOCITY ACCUMULATION path.
	if not _is_poison_mine:
		ProjectileManager.register(self)

	_calculate_stats()
	_build_visuals()
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	# Both factors matter: `scale` (ratio-driven, from _calculate_stats) and
	# visual_scale (magnitude-driven, from _build_visuals - set just above
	# this point, so it's already valid here). Missing visual_scale entirely
	# used to leave the hitbox far smaller than the rendered shape for any
	# big combined/amplified shot - that was the original "should be hitting
	# this but I'm not" report.
	# BUT multiplying the two factors together directly compounds them
	# (same mistake _calculate_stats's own comment already warns about for
	# p_scale/s_mod) - visual_scale alone reaches 8x, so a hit rect could
	# balloon to 250+px on a big charged shot. sqrt() dampens that: still
	# meaningfully bigger for big shots (sqrt(8) ~= 2.8x) without matching
	# the full glow/bloom radius, which is deliberately oversized for flair
	# and was never meant to be 1:1 with the actual hit area.
	rect.size = Vector2(8, 8) * scale * sqrt(visual_scale)
	shape.shape = rect
	add_child(shape)
	
	# Registered so systems can find live projectiles cheaply - the Mythic
	# Magnet's reflection field (Mech's magnet block) is the first consumer.
	add_to_group("projectile")

	collision_layer = 0
	if fired_by_player:
		collision_mask = 4 | 1 # Enemy (Layer 3) + World (Layer 1)
	else:
		collision_mask = 8 | 1 # Player (Layer 4) + World (Layer 1)
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# EXPLOSION DETONATION
	var timer = Timer.new()
	timer.wait_time = _get_lifetime()
	timer.one_shot = true
	timer.timeout.connect(_expire)
	add_child(timer)
	timer.start()
	
	# OFF-SCREEN CULLING FOR PERFORMANCE - used to queue_free() the instant
	# the shot left the camera's view, which meant nothing could ever be
	# shot at past the edge of the screen ("I need to be able to shoot far
	# enough off screen... right now it just seems like my projectiles die
	# as soon as they go off screen" - Natalia). Enemies can absolutely be
	# positioned beyond the current view, so that's a real problem, not
	# just a wasted perf optimization. Now it's a grace window instead of
	# an instant kill: a shot that's still off-screen after
	# OFFSCREEN_GRACE_SEC gets cleaned up (still catches wild missed shots
	# flying into empty space), but one that's actually travelling toward a
	# real off-screen target gets real distance to cover, and the grace
	# timer cancels outright if it comes back on screen before firing.
	# _get_lifetime() (~4s baseline) is still the hard cap regardless, so
	# this can't leak projectiles forever even if the grace timer somehow
	# never fires.
	var vis_notifier = VisibleOnScreenNotifier2D.new()
	vis_notifier.rect = Rect2(-10, -10, 20, 20)
	vis_notifier.screen_exited.connect(func():
		if is_queued_for_deletion() or _offscreen_cull_timer:
			return
		_offscreen_cull_timer = Timer.new()
		_offscreen_cull_timer.wait_time = OFFSCREEN_GRACE_SEC
		_offscreen_cull_timer.one_shot = true
		_offscreen_cull_timer.timeout.connect(func():
			if not is_queued_for_deletion():
				queue_free()
		)
		add_child(_offscreen_cull_timer)
		_offscreen_cull_timer.start()
	)
	vis_notifier.screen_entered.connect(func():
		if _offscreen_cull_timer:
			_offscreen_cull_timer.stop()
			_offscreen_cull_timer.queue_free()
			_offscreen_cull_timer = null
	)
	add_child(vis_notifier)

	# INSTANT LIGHTNING (FEATURE_ROADMAP.md group 3): a lightning-dominant
	# shot shouldn't visibly "fly". The projectile still exists - every bit
	# of hit/chain/status logic is unchanged - but it crosses the screen
	# near-instantly, and what the player SEES is a world-anchored bolt
	# flash along the flight path plus the arc flashes on whatever gets
	# struck. Stylized-jagged, not photoreal, to keep the pixel identity.
	if not _is_poison_mine and ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) > 0.5:
		final_speed = max(final_speed, 4200.0)
		call_deferred("_spawn_instant_bolt_flash")

func _exit_tree():
	if not _is_poison_mine:
		ProjectileManager.unregister(self)

func _spawn_instant_bolt_flash():
	if not get_parent() or direction == Vector2.ZERO:
		return
	var bolt = Line2D.new()
	bolt.width = 3.0
	bolt.default_color = EnergyPacket.get_color_blend(synergies)
	bolt.z_index = 60
	var span = direction * 520.0
	var ortho = Vector2(-direction.y, direction.x)
	var pts = PackedVector2Array([Vector2.ZERO])
	var segments = 9
	for i in range(1, segments):
		var t = float(i) / segments
		# sin(t*PI) envelope keeps the jag pinned at muzzle and endpoint
		pts.append(span * t + ortho * randf_range(-26.0, 26.0) * sin(t * PI))
	pts.append(span)
	bolt.points = pts
	bolt.global_position = global_position
	get_parent().add_child(bolt)
	var tw = bolt.create_tween()
	tw.tween_property(bolt, "modulate:a", 0.0, 0.18)
	tw.tween_callback(bolt.queue_free)

# Shared end-of-flight cleanup - called both by the lifetime Timer (time ran
# out) and by the max_range distance check in _physics_process (traveled far
# enough). Same outcome either way: detonate if this shot carries EXPLOSION,
# then clean up.
func _expire():
	if _is_poison_mine:
		_trigger_poison_mine_detonation()
	elif ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) > 0.1:
		_trigger_explosion()
	if not is_queued_for_deletion():
		queue_free()

func _get_lifetime() -> float:
	var base_life = 4.0
	if ratios.has(EnergyPacket.SynergyType.FIRE):
		base_life = lerp(base_life, 0.4, ratios[EnergyPacket.SynergyType.FIRE]) # Very short lifetime for fire
		if ratios.has(EnergyPacket.SynergyType.KINETIC):
			# Kinetic stretches the fire plume length
			base_life += 1.0 * ratios[EnergyPacket.SynergyType.KINETIC]
	return max(0.1, base_life)

func _calculate_stats():
	# Organic Stat Scaling
	var r_raw = ratios.get(EnergyPacket.SynergyType.RAW, 0.0)
	var r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	var r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
	var r_exp = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	var r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
	var r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
	
	# Base Speed - PIERCE is the velocity stat (armor-piercing round flavor);
	# KINETIC no longer contributes here at all, its whole budget moved to
	# range below instead (see BASE_RANGE's field comment).
	var spd_mod = 0.0
	spd_mod += 1200.0 * r_prc
	spd_mod -= 250.0 * r_psn
	spd_mod -= 200.0 * r_ice
	final_speed = base_speed + spd_mod
	if final_speed < 50.0: final_speed = 50.0

	# Range: generous baseline (BASE_RANGE) for every shot, plus an explicit
	# Kinetic bonus on top - see the field comment above for why this is
	# KINETIC's whole identity now.
	max_range = BASE_RANGE + KINETIC_RANGE_BONUS * r_kin

	# Size/Mass (ratio-driven only - magnitude-driven size lives entirely in
	# _build_visuals()'s p_scale below. An earlier pass also added a
	# magnitude factor HERE, which multiplied against p_scale instead of
	# replacing/adding to it - two compounding exponential-ish curves
	# instead of one produced the "comically big" shapes. One authoritative
	# place for magnitude scaling now.)
	var s_mod = 1.0 + r_raw # RAW directly increases volume
	s_mod += 1.5 * r_ice # ICE adds crystalline mass
	s_mod += 2.0 * r_exp # EXPLOSION adds volatility/size
	s_mod -= 0.5 * r_prc # PIERCE makes it sleek
	scale = Vector2(s_mod, s_mod)
	
	# Base Damage Multiplier
	# RAW gives max raw damage, but other elements still give baseline scaling 
	# so that converting RAW into elements doesn't cripple your DPS.
	var base_mult = 1.0 + (r_raw * 1.5) + ((1.0 - r_raw) * 1.0)
	damage *= base_mult
	
	# Pierce Count (PIERCE sets base to high, otherwise 1)
	if r_prc > 0.0:
		pierce_count = 1 + int(4.0 * r_prc)
	else:
		pierce_count = 1
		
	# Homing check
	if ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0) > 0.05:
		is_homing = true
		
	# Apply Component Stat Modifiers
	if stat_modifiers.has("dmg_mult"): damage *= stat_modifiers["dmg_mult"]
	if stat_modifiers.has("spd_mult"): final_speed *= stat_modifiers["spd_mult"]
	
	# Apply Elemental Multipliers from Components based on ratios
	if stat_modifiers.has("kin_mult") and r_kin > 0: damage *= lerp(1.0, stat_modifiers["kin_mult"], r_kin)
	if stat_modifiers.has("fire_mult") and ratios.has(EnergyPacket.SynergyType.FIRE): damage *= lerp(1.0, stat_modifiers["fire_mult"], ratios[EnergyPacket.SynergyType.FIRE])
	if stat_modifiers.has("ice_mult") and r_ice > 0: damage *= lerp(1.0, stat_modifiers["ice_mult"], r_ice)
	if stat_modifiers.has("vtx_mult") and ratios.has(EnergyPacket.SynergyType.VORTEX): damage *= lerp(1.0, stat_modifiers["vtx_mult"], ratios[EnergyPacket.SynergyType.VORTEX])
	if stat_modifiers.has("ltg_mult") and ratios.has(EnergyPacket.SynergyType.LIGHTNING): damage *= lerp(1.0, stat_modifiers["ltg_mult"], ratios[EnergyPacket.SynergyType.LIGHTNING])
	if stat_modifiers.has("psn_mult") and r_psn > 0: damage *= lerp(1.0, stat_modifiers["psn_mult"], r_psn)
	if stat_modifiers.has("exp_mult") and r_exp > 0: damage *= lerp(1.0, stat_modifiers["exp_mult"], r_exp)
	if stat_modifiers.has("prc_mult") and r_prc > 0: damage *= lerp(1.0, stat_modifiers["prc_mult"], r_prc)
	if stat_modifiers.has("vmp_mult") and ratios.has(EnergyPacket.SynergyType.VAMPIRIC): damage *= lerp(1.0, stat_modifiers["vmp_mult"], ratios[EnergyPacket.SynergyType.VAMPIRIC])
		
	# Color Blending - Keep vibrancy by picking dominant color and boosting
	final_color = Color(0,0,0,0)
	var max_r = 0.0
	var dom_t = -1
	for k in ratios:
		if k == EnergyPacket.SynergyType.RAW and ratios.size() > 1:
			continue
		if ratios[k] > max_r:
			max_r = ratios[k]
			dom_t = k
	if dom_t != -1:
		final_color = EnergyPacket.get_color_for_synergy(dom_t)
		# Boost vibrancy slightly for additive blending
		final_color = final_color * 1.5
		final_color.a = 1.0
	else:
		final_color = Color.WHITE

	if weapon_rarity == 4: # Mythic
		final_color = Color(0.2, 0.9, 0.9, 1.0) # Shiny teal

	# Chromatic intensity scales with magnitude the same way size does - a
	# massive combined blast should visually READ as more powerful, not
	# just bigger. Additive blending (see _build_visuals) makes an
	# overbright color actually glow harder rather than just clip to white.
	var intensity = 1.0 + sqrt(total_power / 500.0) * 0.3
	final_color = final_color * intensity
	final_color.a = 1.0

func _build_visuals():
	visual_node = Node2D.new()
	add_child(visual_node)
	var add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	visual_node.material = add_mat
	
	# Determine dominant and secondary synergies for shape generation
	var sorted_synergies = []
	for k in synergies:
		if k == EnergyPacket.SynergyType.RAW and synergies.size() > 1:
			continue # Ignore RAW if we have other synergies
		sorted_synergies.append({"type": k, "power": synergies[k]})
	sorted_synergies.sort_custom(func(a, b): return a.power > b.power)
	
	var dominant = -1
	var secondary = -1
	if sorted_synergies.size() > 0: dominant = sorted_synergies[0].type
	if sorted_synergies.size() > 1: secondary = sorted_synergies[1].type
	
	# Procedural Shape based on Dominant Element - this is the ONE place
	# magnitude drives visual size (see _calculate_stats() for why it's not
	# also duplicated there anymore). Log growth is gentle/self-limiting on
	# its own (only reaches ~4.3 even at the 150,000 magnitude ceiling), so
	# this cap is mostly just a hard safety ceiling, not the thing actually
	# doing the limiting day to day.
	var p_scale = 1.0 + log(1.0 + total_power / 200.0) * 0.5
	p_scale = min(p_scale, 5.0)
	# Mythic AoE-focused Amplifiers physically grow the projectile
	p_scale *= (1.0 + 0.5 * aoe_bonus)
	p_scale = min(p_scale, 8.0)
	visual_scale = p_scale # so _ready()'s CollisionShape2D can match this

	if dominant == EnergyPacket.SynergyType.KINETIC:
		# Sharp, aerodynamic shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(10, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.FIRE:
		# Spreading fire trail
		var fire_trail = FireTrail2D.new()
		fire_trail.scale_amount_min *= p_scale
		fire_trail.scale_amount_max *= p_scale
		# Use MIX instead of ADD so the black soot is visible
		var mix_mat = CanvasItemMaterial.new()
		mix_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		fire_trail.material = mix_mat
		visual_node.add_child(fire_trail)
	elif dominant == EnergyPacket.SynergyType.ICE:
		# Crystalline, jagged shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(0, 4), Vector2(-5, 2), Vector2(-3, 0), Vector2(-5, -2), Vector2(0, -4)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.POISON:
		# Teardrop shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(-2, 4), Vector2(-5, 2), Vector2(-5, -2), Vector2(-2, -4)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.LIGHTNING:
		# Zig-zag bolt shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, -2), Vector2(2, 4), Vector2(0, 0), Vector2(-6, 4), Vector2(-2, -4), Vector2(0, 0)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.EXPLOSION:
		# Spiky burst shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(6, 0), Vector2(2, 2), Vector2(0, 6), Vector2(-2, 2),
			Vector2(-6, 0), Vector2(-2, -2), Vector2(0, -6), Vector2(2, -2)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.PIERCE:
		# Needle shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(12, 0), Vector2(-6, 2), Vector2(-4, 0), Vector2(-6, -2)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.VAMPIRIC:
		# Blood drop shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(-4, 6), Vector2(-2, 0), Vector2(-4, -6)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.VORTEX:
		# Diamond shape for vortex core
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0), Vector2(0, -5)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
		
		# Purple spiral
		var spiral = Line2D.new()
		var s_pts = PackedVector2Array()
		for i in range(30):
			var a = i * PI / 4.0
			var r = i * 0.4
			s_pts.append(Vector2(cos(a), sin(a)) * r)
		spiral.points = s_pts
		spiral.width = 1.5
		spiral.default_color = Color(0.6, 0.2, 0.9) # Bright purple
		spiral.scale = Vector2.ONE * p_scale
		visual_node.add_child(spiral)
	elif dominant == EnergyPacket.SynergyType.RAW or dominant == -1:
		# Glowing Raw Energy Sphere
		var circ = Polygon2D.new()
		var pts = PackedVector2Array()
		for i in range(16):
			var a = i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 5.0 * p_scale)
		circ.polygon = pts
		circ.color = final_color
		visual_node.add_child(circ)
		
	# Secondary Element modifies properties
	if secondary == EnergyPacket.SynergyType.POISON:
		# Toxic trail
		var trail = GPUParticles2D.new()
		trail.amount = 20
		var process_mat = ParticleProcessMaterial.new()
		process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process_mat.emission_sphere_radius = 4.0
		process_mat.gravity = Vector3(0, 10, 0)
		process_mat.color = Color(0.2, 0.8, 0.2, 0.5)
		trail.process_material = process_mat
		trail.lifetime = 0.5
		trail.local_coords = false
		visual_node.add_child(trail)
	elif secondary == EnergyPacket.SynergyType.PIERCE:
		# Add a glowing core
		var core = Polygon2D.new()
		core.polygon = PackedVector2Array([
			Vector2(5, 0), Vector2(0, 2), Vector2(-5, 0), Vector2(0, -2)
		])
		core.color = Color(1.0, 1.0, 1.0, 0.8)
		core.scale = Vector2.ONE * p_scale
		visual_node.add_child(core)
		
	# Setup helix for multi-synergy combos
	if sorted_synergies.size() >= 2:
		for k in synergies:
			if k != EnergyPacket.SynergyType.RAW:
				var h = Polygon2D.new()
				var pts = PackedVector2Array()
				for i in range(8):
					var a = i * PI / 4.0
					pts.append(Vector2(cos(a), sin(a)) * 2.0)
				h.polygon = pts
				h.color = EnergyPacket.get_color_for_synergy(k)
				visual_node.add_child(h)
				helix_particles.append({
					"node": h,
					"phase": helix_particles.size() * PI,
					"speed": 10.0 + ratios[k] * 10.0,
					"radius": (8.0 + ratios[k] * 12.0) * p_scale
				})
	
	# Kinetic Trail
	if ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0) > 0.1:
		var trail = Trail2D.new()
		trail.width = 4.0
		trail.default_color = final_color * Color(1,1,1,0.5)
		visual_node.add_child(trail)
		
	# Vortex Helix Orbs
	if ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0) > 0.05:
		for i in range(3):
			var orb = Polygon2D.new()
			var pts = PackedVector2Array()
			for j in range(8):
				var a = j * PI / 4.0
				pts.append(Vector2(cos(a), sin(a)) * 2.0)
			orb.polygon = pts
			orb.color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.VORTEX)
			visual_node.add_child(orb)
			helix_particles.append({
				"node": orb,
				"phase": i * (PI * 2.0 / 3.0),
				"speed": 15.0,
				"radius": 8.0
			})

	# Apply glowing material to all visuals
	var mat = visual_node.material
	for child in visual_node.get_children():
		if child is CanvasItem and child.material == null:
			child.material = mat
			
	if weapon_rarity == 4: # Mythic
		var glow = Polygon2D.new()
		glow.name = "MythicGlow"
		var pts = PackedVector2Array()
		for i in range(16):
			var a = i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 12.0 * p_scale)
		glow.polygon = pts
		glow.color = Color(0.2, 1.0, 1.0, 0.2)
		visual_node.add_child(glow)


func _process(delta):
	if weapon_rarity == 4 and visual_node:
		var glow = visual_node.get_node_or_null("MythicGlow")
		if glow:
			glow.scale = Vector2.ONE * (1.0 + sin(time_alive * 8.0) * 0.15)
			glow.color.a = 0.2 + sin(time_alive * 5.0) * 0.1

# Cache of this frame's setup values (ratio unpacking, homing target,
# steering_resistance/straighten) - populated once by _prepare_flight_
# request(), read back by _physics_process() regardless of which path
# (batched Rust via ProjectileManager, single-call Rust, or full GDScript
# fallback) ends up actually computing this frame's movement, so the
# throttled homing-target physics query never runs twice in one frame.
var _flight_r_kin: float = 0.0
var _flight_r_vamp: float = 0.0
var _flight_r_ice: float = 0.0
var _flight_r_fire: float = 0.0
var _flight_r_prc: float = 0.0
var _flight_r_psn: float = 0.0
var _flight_r_vtx: float = 0.0
var _flight_r_ltg: float = 0.0
var _flight_straighten: float = 0.0
var _flight_steering_resistance: float = 1.0
var _flight_active_homing_target: Node2D = null

# Called by ProjectileManager BEFORE its batched Rust call this frame (see
# that file's module comment for the process_priority ordering this relies
# on), and by this projectile itself as a one-off fallback if the manager
# didn't cover it (its very first tick, before it had a chance to
# register, or the extension isn't loaded at all). Runs the throttled
# homing-target physics query and packages everything the flight math
# needs into a request Dictionary shaped for ProjectileFlight.compute_step/
# compute_batch. Never called for poison mines (see _ready - they use
# _physics_process_mine's entirely separate movement model instead).
func _prepare_flight_request(delta: float) -> Dictionary:
	var space_state = get_world_2d().direct_space_state

	_flight_r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	_flight_r_vamp = ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
	_flight_r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
	_flight_r_fire = ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
	_flight_r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
	_flight_r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
	_flight_r_vtx = ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	_flight_r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)

	# KINETIC "The Straightener" (Natalia: "kinetic should also straighten
	# paths") - dampens how hard OTHER elements bend this shot's actual
	# flight path off a straight line, on top of the passive aim-correction
	# steering Kinetic already gets below. Only applies to distortions that
	# move the real position (Poison's downward arc, Vortex's tangential
	# swirl) - Lightning's zigzag is purely a cosmetic visual_node offset,
	# the underlying path is already straight, so there's nothing there for
	# Kinetic to straighten.
	_flight_straighten = clamp(1.0 - _flight_r_kin, 0.0, 1.0)

	# 1. MASS / INERTIA (ICE & RAW)
	# Heavy objects resist steering. Pierce ignores friction but doesn't affect mass steering resistance.
	_flight_steering_resistance = 1.0 + (3.0 * _flight_r_ice) # Ice makes it very hard to turn

	# 2. VAMPIRIC TERMINAL HOMING ("The Hunter")
	# Re-acquiring the best target only needs to happen a few times a second,
	# not every single physics tick - the shape query here was the single
	# biggest per-projectile cost once combat got busy. The cached target's
	# CURRENT position is still read fresh every tick below (so steering
	# stays smooth), only the "who's the best target" search is throttled.
	_flight_active_homing_target = null
	if is_homing or _flight_r_vamp > 0.0:
		_homing_query_timer -= delta
		if _homing_query_timer <= 0.0 or not is_instance_valid(_cached_homing_target):
			_homing_query_timer = HOMING_QUERY_INTERVAL
			_cached_homing_target = _find_homing_target(space_state, _flight_r_kin, _flight_r_vamp, _flight_r_ltg)
		if is_instance_valid(_cached_homing_target):
			_flight_active_homing_target = _cached_homing_target
			target_direction = (_cached_homing_target.global_position - global_position).normalized()

	return {
		"instance_id": get_instance_id(),
		"ratios": {"r_kin": _flight_r_kin, "r_vamp": _flight_r_vamp, "r_fire": _flight_r_fire, "r_psn": _flight_r_psn, "r_vtx": _flight_r_vtx, "r_ltg": _flight_r_ltg, "r_prc": _flight_r_prc},
		"direction": direction, "target_direction": target_direction, "has_homing_target": _flight_active_homing_target != null,
		"final_speed": final_speed, "time_alive": time_alive, "delta": delta,
		"steering_resistance": _flight_steering_resistance, "straighten": _flight_straighten,
		"lightning_state": {"segment_index": _lightning_segment_index, "prev_offset": _lightning_prev_offset, "target_offset": _lightning_target_offset},
	}

func _physics_process(delta: float):
	time_alive += delta

	if _is_poison_mine:
		_physics_process_mine(delta)
		return

	# 3-7. KINETIC STEERING, FIRE DRAG, POISON GRAVITY LOB, VORTEX SWIRL,
	# LIGHTNING ZIG-ZAG - the "ORGANIC VELOCITY ACCUMULATION" block. Ported
	# to Rust (ProjectileFlight.compute_step/compute_batch,
	# rust_ext/src/projectile_flight.rs) with a full GDScript fallback below
	# if the extension isn't loaded - this is pure per-projectile vector
	# math, no scene-tree/physics-server coupling, so it's the actual
	# per-projectile-per-frame cost that scales with how many shots are
	# live at once (unlike the homing/vortex-pull physics QUERIES, which
	# cost the same either way and stay in GDScript regardless of path).
	#
	# The common case: ProjectileManager already computed this frame's
	# result for every registered projectile in ONE batched Rust call
	# (before this function ever runs - see that file's module comment on
	# process_priority ordering) and this just reads it back. Falls
	# through to preparing + computing inline, once, if the batch didn't
	# cover this projectile this frame (its very first tick, most likely).
	var current_speed: float
	var gravity_velocity: Vector2
	var velocity: Vector2
	var visual_offset: Vector2
	var ortho: Vector2

	var res = ProjectileManager.get_result(get_instance_id())
	if res == null:
		var req = _prepare_flight_request(delta)
		_ensure_flight_rust()
		if _flight_rasterizer:
			res = _flight_rasterizer.compute_step(
				req["ratios"], req["direction"], req["target_direction"], req["has_homing_target"],
				req["final_speed"], req["time_alive"], req["delta"],
				req["steering_resistance"], req["straighten"], req["lightning_state"], req["instance_id"]
			)

	if res != null:
		direction = res["direction"]
		velocity = res["velocity"]
		visual_offset = res["visual_offset"]
		current_speed = res["current_speed"]
		gravity_velocity = res["gravity_velocity"]
		_lightning_segment_index = res["lightning_segment_index"]
		_lightning_prev_offset = res["lightning_prev_offset"]
		_lightning_target_offset = res["lightning_target_offset"]
		ortho = Vector2(-direction.y, direction.x)
	else:
		# --- Full GDScript fallback (no Rust extension at all) - _prepare_
		# flight_request already ran above regardless of this branch, so
		# _flight_* and target_direction are already correctly set; only
		# the actual math differs from the Rust path. ---
		current_speed = final_speed

		if _flight_active_homing_target != null:
			var turn_speed = (8.0 * _flight_r_vamp) / _flight_steering_resistance
			direction = direction.lerp(target_direction, turn_speed * delta).normalized()
			# If Kinetic + Vampiric, grant pierce based on kinetic ratio
			if _flight_r_kin > 0.0 and _flight_r_vamp > 0.0:
				_flight_r_prc = max(_flight_r_prc, 0.5) # Force granting pierce
		elif target_direction != Vector2.ZERO:
			var turn_speed = 0.5 # Passive drift
			if _flight_r_kin > 0.0:
				turn_speed += (6.0 * _flight_r_kin)
			turn_speed /= _flight_steering_resistance
			direction = direction.lerp(target_direction, turn_speed * delta).normalized()

		# 4. FIRE DECELERATION ("The Plume") vs PIERCE / KINETIC
		# Pierce grants infinite mass/0 drag. Kinetic actively pushes through drag.
		if _flight_r_fire > 0.0:
			var drag_coefficient = 800.0 * _flight_r_fire
			drag_coefficient *= (1.0 - _flight_r_prc) # Pierce cancels drag organically
			drag_coefficient = max(0.0, drag_coefficient - (500.0 * _flight_r_kin)) # Kinetic fights it
			current_speed = max(50.0, final_speed - drag_coefficient * time_alive)

		# 5. POISON GRAVITY LOB ("The Mortar") - dampened by Kinetic's straightening
		gravity_velocity = Vector2.ZERO
		if _flight_r_psn > 0.0:
			gravity_velocity = Vector2(0, 400.0 * _flight_r_psn * time_alive * _flight_straighten) # Accelerates downwards over time

		# ORGANIC VELOCITY ACCUMULATION
		ortho = Vector2(-direction.y, direction.x)
		velocity = (direction * current_speed) + gravity_velocity
		visual_offset = Vector2.ZERO

		# 6. VORTEX SWIRL ("The Swirler")
		# Applies a strong tangential force that oscillates, moving the projectile itself.
		if _flight_r_vtx > 0.0:
			var swirl_amplitude = 250.0 * _flight_r_vtx * _flight_straighten # Kinetic punches through the swirl
			var swirl_freq = 6.0
			var swirl_vel = ortho * cos(time_alive * swirl_freq) * swirl_amplitude
			velocity += swirl_vel

		# 7. LIGHTNING ZIG-ZAG ("The Arc")
		# Was a smooth sin(t*40)*cos(t*25) beat pattern, which reads as a slow
		# side-to-side wobble rather than a bolt. Real lightning is jagged and
		# irregular, so instead we hold a random lateral offset for a short
		# segment, then snap-lerp to the next one - sharp direction changes,
		# no smooth oscillation.
		if _flight_r_ltg > 0.0:
			var segment_length = 0.045
			var segment_index = int(time_alive / segment_length)
			if segment_index != _lightning_segment_index:
				_lightning_segment_index = segment_index
				_lightning_prev_offset = _lightning_target_offset
				var seed = int(hash(get_instance_id())) ^ segment_index
				_lightning_target_offset = (float(abs(seed) % 2000) / 1000.0) - 1.0 # deterministic pseudo-random in [-1, 1]
			var seg_t = clamp(fmod(time_alive, segment_length) / segment_length, 0.0, 1.0)
			# Ease sharply so it snaps rather than glides between segments
			seg_t = seg_t * seg_t
			var lightning_wave = lerp(_lightning_prev_offset, _lightning_target_offset, seg_t)
			visual_offset += ortho * lightning_wave * (26.0 * _flight_r_ltg)

	# VORTEX pull query: touches OTHER physics bodies, not pure
	# per-projectile math, so it stays in GDScript regardless of which
	# path computed the movement above (see ProjectileFlight's own module
	# comment). Throttled to VORTEX_QUERY_INTERVAL instead of every tick -
	# accumulates elapsed time between pulls and passes THAT to
	# _pull_nearby_items so the total impulse over time still matches, just
	# applied in slightly chunkier steps instead of smoothly every 1/60s
	# (imperceptible for a pull effect).
	if _flight_r_vtx > 0.1:
		_vortex_query_timer += delta
		if _vortex_query_timer >= VORTEX_QUERY_INTERVAL:
			var elapsed = _vortex_query_timer
			_vortex_query_timer = 0.0
			_pull_nearby_items(elapsed)

	# APPLY PHYSICS
	var _prev_global_pos = global_position
	position += velocity * delta

	# TUNNELING FIX: Area2D has no continuous collision detection - it only
	# fires body_entered/area_entered if the shape happens to still be
	# overlapping something at the END of a physics tick. LIGHTNING-dominant
	# shots force final_speed to at least 4200 px/s (see the INSTANT
	# LIGHTNING block above), and PIERCE's speed bonus can push
	# well past 1500 - at 60 physics ticks/sec that's 25-70+ px of travel
	# PER TICK, easily more than a small enemy's whole hitbox width, so the
	# shot can cross clean through several targets without ever registering
	# an overlap. This was the actual "stuff isn't hitting targets" bug -
	# _spawn_instant_bolt_flash's visual bolt implies the whole beam path
	# connects instantly, but the real moving hitbox was skipping most of
	# what it visually crossed. Sweep the segment actually travelled this
	# tick and manually route anything crossed into the normal hit path.
	# Only pay for the sweep query when travel this tick is actually fast
	# enough to risk skipping through a target (see TUNNEL_RISK_MOVE_THRESHOLD
	# comment up top) - below that, the normal Area2D signals below already
	# reliably catch the hit for free, and this was previously gated at just
	# 4.0px, so nearly every projectile at any speed paid for a full physics
	# shape query every single tick regardless of whether it needed one.
	var _moved = global_position - _prev_global_pos
	if _moved.length() > TUNNEL_RISK_MOVE_THRESHOLD:
		_sweep_for_tunneled_hits(_prev_global_pos, _moved)

	# Range cap (see max_range's field comment) - reuses _moved rather than
	# computing distance a second way. Whichever runs out first between this
	# and the time-based lifetime Timer ends the shot; for anything that
	# isn't FIRE (whose short lifetime is almost always the binding
	# constraint anyway) this is normally the one that actually matters.
	distance_traveled += _moved.length()
	if distance_traveled >= max_range:
		_expire()
		return

	# APPLY VISUALS
	visual_node.position = visual_offset
	# If poison gravity is dominating, point downwards
	if gravity_velocity.length() > (direction * current_speed).length():
		visual_node.rotation = velocity.angle()
	else:
		visual_node.rotation = direction.angle()
	
	# Update Helix Particles
	if helix_particles.size() > 0:
		for p in helix_particles:
			var angle = time_alive * p["speed"] + p["phase"]
			p["node"].position = Vector2(cos(angle)*p["radius"]*0.5, sin(angle)*p["radius"])

# Poison-mine movement: no gravity lob, vortex swirl, fire drag, homing, or
# range-based speed bonuses - just a straight crawl (or a dead stop with no
# KINETIC) in the direction it was fired, until it hits something or its
# lifetime Timer calls _expire(). Lightning's cosmetic zig-zag visual offset
# is kept even at zero velocity - a stationary mine crackling in place reads
# better than one sitting perfectly still.
func _physics_process_mine(delta: float):
	var r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	var r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	var velocity = direction * MINE_CRAWL_SPEED * r_kin

	var _prev_global_pos = global_position
	position += velocity * delta

	var _moved = global_position - _prev_global_pos
	if _moved.length() > TUNNEL_RISK_MOVE_THRESHOLD:
		_sweep_for_tunneled_hits(_prev_global_pos, _moved)

	distance_traveled += _moved.length()
	if distance_traveled >= max_range:
		_expire()
		return

	var visual_offset = Vector2.ZERO
	if r_ltg > 0.0:
		var ortho = Vector2(-direction.y, direction.x)
		var segment_length = 0.045
		var segment_index = int(time_alive / segment_length)
		if segment_index != _lightning_segment_index:
			_lightning_segment_index = segment_index
			_lightning_prev_offset = _lightning_target_offset
			var seed = int(hash(get_instance_id())) ^ segment_index
			_lightning_target_offset = (float(abs(seed) % 2000) / 1000.0) - 1.0
		var seg_t = clamp(fmod(time_alive, segment_length) / segment_length, 0.0, 1.0)
		seg_t = seg_t * seg_t
		var lightning_wave = lerp(_lightning_prev_offset, _lightning_target_offset, seg_t)
		visual_offset += ortho * lightning_wave * (26.0 * r_ltg)
	visual_node.position = visual_offset
	visual_node.rotation = direction.angle()

	if helix_particles.size() > 0:
		for p in helix_particles:
			var angle = time_alive * p["speed"] + p["phase"]
			p["node"].position = Vector2(cos(angle) * p["radius"] * 0.5, sin(angle) * p["radius"])

# Poison-mine detonation: an AoE burst themed by whichever non-Poison,
# non-Kinetic synergy is strongest in the packet (Kinetic is the mobility
# stat, not a detonation flavor). Called from both _expire() (ran out of
# time/range - "explodes when it expires") and _handle_hit() (an enemy
# walked into it), guarded so it only ever fires once regardless of which
# happens first.
func _trigger_poison_mine_detonation():
	if _mine_detonated:
		return
	_mine_detonated = true

	var theme = -1
	var theme_ratio = 0.0
	for k in ratios:
		if k == EnergyPacket.SynergyType.POISON or k == EnergyPacket.SynergyType.KINETIC or k == EnergyPacket.SynergyType.RAW:
			continue
		if ratios[k] > theme_ratio:
			theme_ratio = ratios[k]
			theme = k

	var radius = 220.0 * (1.0 + 0.5 * aoe_bonus)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	var results = space_state.intersect_shape(query)

	var ring_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.POISON)
	var burst_damage = damage * 1.5

	match theme:
		EnergyPacket.SynergyType.LIGHTNING:
			ring_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.LIGHTNING)
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					col.apply_damage(burst_damage, "LIGHTNING")
					if col.has_method("apply_status"):
						col.apply_status("paralyzed", 0.6)
					_draw_lightning_arc(Vector2.ZERO, to_local(col.global_position))
		EnergyPacket.SynergyType.VORTEX:
			ring_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.VORTEX)
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					col.apply_damage(burst_damage)
				if col.has_method("pull_towards"):
					col.pull_towards(global_position, 1.0, 900.0)
				elif col is CharacterBody2D:
					col.velocity = (global_position - col.global_position).normalized() * 900.0
				if col.has_method("apply_status"):
					col.apply_status("vortexed", 1.2)
		EnergyPacket.SynergyType.FIRE:
			ring_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.FIRE)
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					col.apply_damage(burst_damage)
					if col.has_method("apply_status"):
						col.apply_status("burning", 5.0)
		EnergyPacket.SynergyType.ICE:
			ring_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.ICE)
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					col.apply_damage(burst_damage * 0.6)
					if col.has_method("apply_status"):
						col.apply_status("frozen", 3.0)
		_:
			# Generic detonation - Explosion/Pierce/Vampiric/no clear
			# secondary all just get a bigger version of the plain blast.
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					col.apply_damage(burst_damage)

	if get_parent():
		var v = PulseRingVisual.new()
		v.global_position = global_position
		get_parent().add_child(v)
		v.setup(radius, ring_color, 0.5)

# Approximates the shape actually moved through this tick as a rectangle
# (segment length x hitbox width) oriented along the direction of travel,
# and routes anything it overlaps into the normal _handle_hit path - see
# the call site's comment in _physics_process for why this exists. Sized to
# match the REAL CollisionShape2D (same formula _ready() uses) so this
# never claims a hit the actual hitbox wouldn't also make at close range.
func _sweep_for_tunneled_hits(from_pos: Vector2, moved: Vector2):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var seg_shape = RectangleShape2D.new()
	var hit_w = 8.0 * scale.x * sqrt(visual_scale)
	seg_shape.size = Vector2(moved.length(), max(4.0, hit_w))
	query.shape = seg_shape
	query.transform = Transform2D(moved.angle(), from_pos + moved * 0.5)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var results = space_state.intersect_shape(query, 8)
	for res in results:
		var col = res["collider"]
		if col == self or col == source_mech:
			continue
		_handle_hit(col)

# Extracted straight out of the old inline block in _physics_process (see
# the throttling comment at the call site) - same search logic, just now
# callable on its own schedule instead of every tick.
func _find_homing_target(space_state, r_kin: float, r_vamp: float, r_ltg: float) -> Node2D:
	var closest = null
	var min_dist = 400.0 + (300.0 * r_vamp)
	if r_ltg > 0.0 and r_vamp > 0.0:
		min_dist += 500.0 * r_ltg # Lightning + Vampiric massively increases targeting range

	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = min_dist
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 4 if collision_mask & 4 else 8
	var results = space_state.intersect_shape(query)

	# If Kinetic + Vampiric, look for FURTHEST target to maximize pierce potential
	if r_kin > 0.0 and r_vamp > 0.0:
		var max_dist = 0.0
		for res in results:
			var col = res["collider"]
			if col.has_method("apply_damage"):
				var d = global_position.distance_to(col.global_position)
				if d > max_dist:
					max_dist = d
					closest = col
	else:
		for res in results:
			var col = res["collider"]
			if col.has_method("apply_damage"):
				var d = global_position.distance_to(col.global_position)
				if d < min_dist:
					min_dist = d
					closest = col
	return closest

func _pull_nearby_items(delta: float):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 150.0 + 100.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	query.shape = shape
	query.transform = global_transform
	
	# Always pull Loot (16), Enemies (4), and Player (8)
	query.collision_mask = 16 | 4 | 8
		
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col == self: continue
		
		var pull_mult = 3.0 # Targets get pulled 300% as hard
		if "is_player" in col:
			if fired_by_player and col.is_player:
				pull_mult = 0.05 # Shooter is barely affected
			elif not fired_by_player and not col.is_player:
				pull_mult = 0.05 # Shooter is barely affected
				
		var pull_strength = 600.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0) * pull_mult
		
		if col.has_method("pull_towards"):
			col.pull_towards(global_position, delta, pull_strength)
		elif col is CharacterBody2D: # Fallback
			var p_dir = (global_position - col.global_position).normalized()
			var lerp_weight = 10.0 * delta
			if lerp_weight > 1.0: lerp_weight = 1.0
			col.velocity = col.velocity.lerp(p_dir * pull_strength, lerp_weight)

func _on_body_entered(body: Node2D):
	if body.get_class() == "CharacterBody2D" and body.has_method("apply_part_damage"):
		return
	_handle_hit(body)

func _on_area_entered(area: Area2D):
	_handle_hit(area)

func _handle_hit(target: Node2D):
	if not target.has_method("apply_damage"):
		return
	# Shared choke point for both the normal signal-based hit (_on_body_entered/
	# _on_area_entered) and the tunneling sweep in _physics_process below -
	# without this, a shot whose final resting position still overlaps a
	# target it already swept-hit this tick would apply damage twice.
	var target_id = target.get_instance_id()
	if _handled_targets.has(target_id):
		return
	_handled_targets[target_id] = true

	var dominant_str = "RAW"
	var max_ratio = 0.0
	for k in ratios:
		if ratios[k] > max_ratio:
			max_ratio = ratios[k]
			match k:
				EnergyPacket.SynergyType.FIRE: dominant_str = "FIRE"
				EnergyPacket.SynergyType.ICE: dominant_str = "ICE"
				EnergyPacket.SynergyType.KINETIC: dominant_str = "KINETIC"
				EnergyPacket.SynergyType.VORTEX: dominant_str = "VORTEX"
				EnergyPacket.SynergyType.LIGHTNING: dominant_str = "LIGHTNING"
				EnergyPacket.SynergyType.POISON: dominant_str = "POISON"
				EnergyPacket.SynergyType.EXPLOSION: dominant_str = "EXPLOSION"
				EnergyPacket.SynergyType.PIERCE: dominant_str = "PIERCE"
				EnergyPacket.SynergyType.VAMPIRIC: dominant_str = "VAMPIRIC"
				
	# Apply Base Damage
	# source_mech can outlive the frame it was fired on but not survive to
	# the frame this shot actually lands (its owner died/despawned mid-
	# flight) - Godot's argument-type check rejects a freed-object reference
	# even for a nullable Node param, so this must be validated at the call
	# site rather than left to apply_damage's own is_instance_valid guard
	# further downstream (_log_incoming_damage), which never gets the
	# chance to run.
	var valid_source = source_mech if is_instance_valid(source_mech) else null
	target.apply_damage(damage, dominant_str, valid_source, was_reflected)
	
	# Massive Damage Screen Shake on Hit
	if fired_by_player and target.is_in_group("enemy") and damage >= 10000000.0:
		var cam = get_tree().get_first_node_in_group("camera")
		if cam and cam.has_method("shake"):
			var intensity = clamp(damage / 5000000.0, 1.5, 5.0)
			cam.shake(intensity, 0.4)
	
	if is_crit and target.get_parent():
		var lbl = Label.new()
		lbl.text = "CRIT!"
		lbl.modulate = Color(1.0, 0.2, 0.2)
		lbl.scale = Vector2(1.5, 1.5)
		lbl.z_index = 100
		lbl.global_position = target.global_position + Vector2(-20, -40)
		target.get_parent().add_child(lbl)
		var tw = lbl.create_tween()
		tw.tween_property(lbl, "global_position", lbl.global_position + Vector2(0, -60), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
		tw.tween_callback(lbl.queue_free)
		
	if is_instance_valid(source_mech) and source_mech.has_signal("dealt_damage") and target != source_mech:
		source_mech.dealt_damage.emit(damage)
	
	# Apply Status Effects - every synergy past its threshold leaves a
	# signature mark (FEATURE_ROADMAP.md group 3). Durations and proc
	# chances scale with the synergy's RATIO, so trace amounts from a
	# blended packet stay subtle instead of full-strength.
	_apply_synergy_status_effects(target, ratios)

	# Resonator Sync (Mythic Resonator - see ResonatorTile._process_sync):
	# proc_synergies carries statuses this packet PICKED UP from a crossed
	# sync path, entirely separate from its actual elemental composition.
	# Reuses the exact same threshold table above so a sync-conferred burn
	# behaves identically to a real one - just routed through a second,
	# non-damage-affecting dict instead of `ratios`.
	if not proc_synergies.is_empty():
		_apply_synergy_status_effects(target, proc_synergies)

# Shared by both a shot's real elemental ratios and any Resonator Sync
# proc_synergies (see above) - `sr` (synergy ratios) is just a synergy_type
# -> 0..1-ish strength dict either way, and every branch below only ever
# reads from `sr`, never `ratios` directly, so the two call sites are
# guaranteed to apply identical effects for identical strengths.
func _apply_synergy_status_effects(target: Node, sr: Dictionary):
	if not target.has_method("apply_status"):
		return

	if sr.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1:
		target.apply_status("burning", 3.0 * sr[EnergyPacket.SynergyType.FIRE])
	if sr.get(EnergyPacket.SynergyType.ICE, 0.0) > 0.1:
		target.apply_status("frozen", 3.0 * sr[EnergyPacket.SynergyType.ICE])

	# LIGHTNING: paralyze chance - a full-stop lockup, brief
	var rl = sr.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	if rl > 0.15 and randf() < 0.35 * rl:
		target.apply_status("paralyzed", 0.4 + 0.5 * rl)

	# POISON: lingering toxin - DoT plus a mild slow
	var rp = sr.get(EnergyPacket.SynergyType.POISON, 0.0)
	if rp > 0.1:
		target.apply_status("poisoned", 4.0 + 3.0 * rp)

	# KINETIC: stagger + physical shove along the shot's direction
	var rk = sr.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	if rk > 0.2:
		target.apply_status("staggered", 0.4 + 0.3 * rk)
		if "external_force" in target:
			target.external_force += direction * 260.0 * rk

	# PIERCE: rent armor - target takes increased damage for a while
	if sr.get(EnergyPacket.SynergyType.PIERCE, 0.0) > 0.15:
		target.apply_status("rent", 4.0)

	# EXPLOSION: concussion chance - near-total slow, very brief
	var re = sr.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	if re > 0.2 and randf() < 0.5 * re:
		target.apply_status("concussed", 0.35)

	# VORTEX: dragged toward the impact point for a moment
	var rv = sr.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	if rv > 0.15:
		if "vortex_drag_point" in target:
			target.vortex_drag_point = global_position
		target.apply_status("vortexed", 0.4 + 0.6 * rv)

	# VAMPIRIC: bleed; heavy vampiric hits can briefly immobilize
	var rvm = sr.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
	if rvm > 0.1:
		target.apply_status("bleeding", 3.0 + 2.0 * rvm)
		if rvm > 0.5 and randf() < 0.3:
			target.apply_status("immobilized", 0.5)
		
	# Lightning Arcing - chains through multiple enemies in sequence (not
	# just one jump), each hop dealing falloff damage. Hop count and jump
	# radius both scale with how much of the packet was actually Lightning.
	var r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	if r_ltg > 0.05 and target.is_in_group("enemy"):
		var max_hops = 1 + int(round(4.0 * r_ltg)) # up to 5 hops at 100% lightning
		var jump_radius = 350.0 * r_ltg
		var already_hit: Array = [target]
		var chain_from_pos = global_position
		var chain_damage = damage * 0.5

		for hop in range(max_hops):
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsShapeQueryParameters2D.new()
			var shape = CircleShape2D.new()
			shape.radius = jump_radius
			query.shape = shape
			query.transform = Transform2D(0, chain_from_pos)
			query.collision_mask = 4 if collision_mask & 4 else 8
			var results = space_state.intersect_shape(query)

			var closest = null
			var min_dist = shape.radius
			for res in results:
				var col = res["collider"]
				if col in already_hit: continue
				if col.has_method("apply_damage") and col.is_in_group("enemy"):
					var d = chain_from_pos.distance_to(col.global_position)
					if d < min_dist:
						min_dist = d
						closest = col

			if not closest:
				break

			_draw_lightning_arc(chain_from_pos - global_position, closest.global_position - global_position)
			closest.apply_damage(chain_damage, "LIGHTNING")

			already_hit.append(closest)
			chain_from_pos = closest.global_position
			chain_damage *= 0.7 # each additional hop falls off
			
	# Vampiric Heal
	if ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0) > 0.1:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("apply_damage"):
			players[0].apply_damage(-damage * 0.3 * ratios[EnergyPacket.SynergyType.VAMPIRIC])
			
	# Explosion AoE
	if ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) > 0.1:
		_trigger_explosion()
		
	# --- BIOME SYNERGIES ---
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.size() > 0:
		var map = maps[0]
		if map.has_method("get_biome_at_world_pos"):
			var biome = map.get_biome_at_world_pos(global_position)
			
			# Lightning + Water = Massive AoE
			if ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) > 0.1 and biome == map.BiomeType.WATER:
				_trigger_biome_explosion(400.0, damage * 2.0, "lightning")
				
			# Fire + Forest = Burn Trees
			if ratios.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1 and biome == map.BiomeType.FOREST:
				_trigger_biome_explosion(200.0, damage * 1.5, "fire")
				# If we hit an obstacle directly, destroy it
				var obs = map.get_node_or_null("Obstacles")
				if obs and target.get_parent() == obs:
					target.queue_free()

		# Fire + Oil Slick = Ignition. Oil slicks are their own scattered
		# hazard nodes (OilSlickHazard.gd), not a biome, so this checks the
		# small "oil_slick" group directly rather than the terrain grid -
		# only ever a handful of slicks exist on a given map, so the scan
		# is cheap even done per FIRE hit.
		if ratios.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1:
			for slick in get_tree().get_nodes_in_group("oil_slick"):
				if is_instance_valid(slick) and global_position.distance_to(slick.global_position) <= slick.IGNITE_RADIUS:
					slick.ignite()

	# Poison mine: contact detonates it immediately (see _trigger_poison_mine_
	# detonation's header comment) instead of piercing through like a normal
	# shot - the direct hit above already dealt its own damage, this adds
	# the AoE burst on top, then consumes the mine outright.
	if _is_poison_mine:
		_trigger_poison_mine_detonation()
		if not is_queued_for_deletion():
			queue_free()
		return

	pierce_count -= 1
	if pierce_count <= 0:
		queue_free()

# Draws one jagged bolt segment between two points, LOCAL to visual_node
# (i.e. relative to the projectile's own position at the moment of the
# hit). Used per-hop by the lightning chain above. Multiple offset
# midpoints (not just one) so it reads as an actual bolt rather than a
# single bent line.
func _draw_lightning_arc(from_local: Vector2, to_local: Vector2):
	var arc = Line2D.new()
	arc.width = 4.0
	arc.default_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.LIGHTNING)

	var span = to_local - from_local
	var length = span.length()
	var ortho = Vector2(-span.y, span.x).normalized() if length > 0.01 else Vector2.RIGHT

	var points = PackedVector2Array([from_local])
	if length > 30.0:
		var segments = clamp(int(length / 40.0), 1, 5)
		for i in range(1, segments):
			var t = float(i) / segments
			var jitter = ortho * randf_range(-length * 0.18, length * 0.18)
			points.append(from_local.lerp(to_local, t) + jitter)
	points.append(to_local)
	arc.points = points

	visual_node.add_child(arc)
	var tw = arc.create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.2)
	tw.tween_callback(arc.queue_free)

func _trigger_explosion():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	# aoe_bonus: Mythic AoE-focused Amplifiers widen the blast
	shape.radius = 100.0 * ratios[EnergyPacket.SynergyType.EXPLOSION] * (1.0 + 0.5 * aoe_bonus)
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("apply_damage"):
			col.apply_damage(damage * 0.5)

func _trigger_biome_explosion(radius: float, dmg: float, type: String):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("apply_damage"):
			col.apply_damage(dmg)
			if type == "fire" and col.has_method("apply_status"):
				col.apply_status("burning", 5.0)
