extends Node

# Regression harness for task #14's remaining draw-batching/redraw-cost
# fixes, following up the projectile material-sharing fix:
#   1. JammerMech/SupportMech: queue_redraw() throttled from unconditional
#      60Hz to REDRAW_HZ (20Hz) - the aura's pulse animation has a ~1s
#      period, imperceptibly different at that rate.
#   2. DroneRenderer: same idea, throttled to 30Hz (a spinning-rotor
#      animation reads faster than the slow aura pulse, so a gentler cut).
#   3. DeathExplosion: GPUParticles2D burst counts (debris/core) now scale
#      down under saturation (many concurrent explosions, e.g. an AoE wipe)
#      via a static live-count + tier table, mirroring ProjectileManager's
#      established saturation-LOD pattern - full effect for an isolated
#      death, thinner under a pile-up.
#
# Headless has no real RenderingDevice, so _draw() callbacks aren't a
# reliable signal to assert on here - these check the TIMER STATE MACHINE
# directly (decrement/reset/desync), which is the actual logic that changed,
# rather than depending on the render pipeline executing.

const JammerMechScript = preload("res://scripts/entities/JammerMech.gd")
const SupportMechScript = preload("res://scripts/entities/SupportMech.gd")
const DroneRendererScript = preload("res://scripts/visuals/DroneRenderer.gd")
const DeathExplosionScript = preload("res://scripts/visuals/DeathExplosion.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- 1. JammerMech redraw throttle ---------------------------------
	var jammer = JammerMechScript.new()
	jammer.is_player = false
	world.add_child(jammer)
	jammer.set_physics_process(false)

	_check("JammerMech's redraw timer starts desynced (0 <= timer < 1/REDRAW_HZ, not always 0)",
		jammer._redraw_timer >= 0.0 and jammer._redraw_timer < (1.0 / JammerMechScript.REDRAW_HZ))

	var timer_before = jammer._redraw_timer
	jammer._process(0.001) # far smaller than any plausible redraw interval
	_check("a small delta just decrements the timer, doesn't reset it (still throttling)",
		jammer._redraw_timer < timer_before and jammer._redraw_timer > 0.0)

	# Drive past the threshold - timer must reset to a full interval, not
	# free-run negative.
	jammer._process(1.0)
	_check("once the timer crosses zero it resets to a full 1/REDRAW_HZ interval",
		jammer._redraw_timer > 0.0 and jammer._redraw_timer <= (1.0 / JammerMechScript.REDRAW_HZ))

	# --- 2. SupportMech inherits the same throttle (no separate redraw
	# call of its own - relies entirely on super._process()) -------------
	var support = SupportMechScript.new()
	support.is_player = false
	world.add_child(support)
	support.set_physics_process(false)
	_check("SupportMech has the same desynced redraw timer (inherited from JammerMech, no override)",
		support._redraw_timer >= 0.0 and support._redraw_timer < (1.0 / JammerMechScript.REDRAW_HZ))

	# --- 3. DroneRenderer redraw throttle --------------------------------
	var drone_renderer = DroneRendererScript.new()
	world.add_child(drone_renderer)
	_check("DroneRenderer's redraw timer also starts desynced",
		drone_renderer._redraw_timer >= 0.0 and drone_renderer._redraw_timer < (1.0 / DroneRendererScript.REDRAW_HZ))
	var dr_timer_before = drone_renderer._redraw_timer
	drone_renderer._process(0.001)
	_check("DroneRenderer's small delta decrements without resetting",
		drone_renderer._redraw_timer < dr_timer_before and drone_renderer._redraw_timer > 0.0)

	# --- 4. DeathExplosion saturation tiers (pure function, no live count
	# dependency) ----------------------------------------------------------
	var saved_live_count = DeathExplosionScript._live_count
	DeathExplosionScript._live_count = 0
	_check("below every tier threshold, particle scale is full (1.0)",
		DeathExplosionScript._particle_scale() == 1.0)
	DeathExplosionScript._live_count = 6
	_check("at the first tier (6 concurrent), particle scale thins to 0.75",
		DeathExplosionScript._particle_scale() == 0.75)
	DeathExplosionScript._live_count = 12
	_check("at the second tier (12 concurrent), particle scale thins to 0.5",
		DeathExplosionScript._particle_scale() == 0.5)
	DeathExplosionScript._live_count = 24
	_check("at the third tier (24 concurrent), particle scale thins to 0.25",
		DeathExplosionScript._particle_scale() == 0.25)
	DeathExplosionScript._live_count = saved_live_count

	# --- 5. A real DeathExplosion instance actually applies the scale to
	# its particle amounts, and _live_count tracks real instance lifetime. -
	DeathExplosionScript._live_count = 0
	var explosion_a = DeathExplosionScript.new()
	world.add_child(explosion_a)
	_check("spawning one explosion brings live_count to 1 (isolated death, full effect)",
		DeathExplosionScript._live_count == 1)

	var debris_a = null
	var core_a = null
	for c in explosion_a.get_children():
		if c is GPUParticles2D:
			if debris_a == null:
				debris_a = c
			else:
				core_a = c
	_check("an isolated explosion's debris burst uses the full 100-particle amount",
		debris_a != null and debris_a.amount == 100)
	_check("an isolated explosion's core burst uses the full 50-particle amount",
		core_a != null and core_a.amount == 50)

	# Force saturation and spawn a second explosion under it - its OWN
	# particle counts should come out thinned.
	DeathExplosionScript._live_count = 12
	var explosion_b = DeathExplosionScript.new()
	world.add_child(explosion_b)
	var debris_b = null
	for c in explosion_b.get_children():
		if c is GPUParticles2D:
			debris_b = c
			break
	_check("an explosion spawned while 12 are already live gets the thinned (50%) particle count",
		debris_b != null and debris_b.amount == 50)

	explosion_a.queue_free()
	explosion_b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("freeing explosions decrements live_count back down via _exit_tree",
		DeathExplosionScript._live_count == 11) # started this block at 12, +1 (explosion_b) -2 (both freed) = 11... see note below

	DeathExplosionScript._live_count = saved_live_count

	if failures == 0:
		print("PASS: JammerMech/SupportMech/DroneRenderer redraw throttling and DeathExplosion saturation-tier particle thinning all wired correctly")
	get_tree().quit(0 if failures == 0 else 1)
