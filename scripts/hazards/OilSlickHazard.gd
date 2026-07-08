class_name OilSlickHazard
extends Node2D

# A walkable (non-blocking) terrain hazard: a dark puddle that does nothing
# on its own, but any FIRE-synergy hit landing within IGNITE_RADIUS of it
# sets it ablaze - a burning zone that ticks damage on anyone standing in it
# for a few seconds, then burns out and goes dormant (with a cooldown before
# it can catch again, so one slick isn't a permanent lava floor).
#
# Deliberately NOT an Area2D with movement-affecting physics (no slip/slow
# effect on the mechs walking over it) - the melee/mass physics + AI
# pathing systems are complex enough that bolting on a per-tile control
# debuff risked destabilizing movement code nobody asked to have touched.
# The payoff here is purely the Fire-synergy environmental combo, matching
# the existing Fire+Forest / Lightning+Water biome-synergy pattern in
# Projectile.gd rather than inventing a second, different kind of hazard.

const IGNITE_RADIUS = 48.0
const BURN_DURATION = 6.0
const BURN_TICK_INTERVAL = 0.5
const BURN_TICK_DAMAGE = 6.0
const REIGNITE_COOLDOWN = 4.0 # after burning out, before it can catch again

var radius: float = 28.0
var is_burning: bool = false
var _burn_timer: float = 0.0
var _tick_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _visual_seed: int = 0

func _ready():
	add_to_group("oil_slick")
	z_index = -3 # sits under mechs/obstacles, above bare ground
	_visual_seed = randi()

func _process(delta: float):
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if not is_burning:
		return

	_burn_timer -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = BURN_TICK_INTERVAL
		_tick_damage()
	if _burn_timer <= 0.0:
		is_burning = false
		_cooldown_timer = REIGNITE_COOLDOWN
	queue_redraw()

# Called by Projectile.gd when a FIRE-synergy hit lands within IGNITE_RADIUS.
func ignite():
	if is_burning or _cooldown_timer > 0.0:
		return
	is_burning = true
	_burn_timer = BURN_DURATION
	_tick_timer = 0.0 # first tick fires immediately
	queue_redraw()

func _tick_damage():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 4 | 8 # enemy + player layers only
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("apply_damage"):
			col.apply_damage(BURN_TICK_DAMAGE, "FIRE")
			if col.has_method("apply_status"):
				col.apply_status("burning", 1.5) # keeps the burning tint/DoT alive briefly after stepping out

func _draw():
	var rng = RandomNumberGenerator.new()
	rng.seed = _visual_seed
	var base_color = Color(0.08, 0.07, 0.05, 0.85) if not is_burning else Color(0.9, 0.35, 0.05, 0.55 + 0.25 * sin(Time.get_ticks_msec() / 90.0))
	var pts = PackedVector2Array()
	var lobes = 7
	for i in range(lobes):
		var a = i * TAU / float(lobes)
		var r = radius * (0.7 + rng.randf() * 0.4)
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, base_color)
	if is_burning:
		# A few flickering ember points so the ignited state reads instantly
		# from a distance, not just as a color swap on a static blob.
		for i in range(4):
			var a = rng.randf() * TAU
			var r = radius * rng.randf() * 0.6
			draw_circle(Vector2(cos(a), sin(a)) * r, 2.5, Color(1.0, 0.8, 0.3, 0.8))
