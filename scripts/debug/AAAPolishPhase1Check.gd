extends Node

# Regression harness for AAA Polish Roadmap Phase 1 (autonomous overnight
# pass, no live playtest available to confirm by eye): HitstopManager's
# self-restoring time_scale guard, and the WorldEnvironment/HDR Bloom node
# added to Main._setup_pixel_viewport(). These are the two riskiest pieces
# of that pass - a bug in either is a severe, game-wide symptom (stuck
# slow-motion forever, or a scene that fails to boot at all) rather than a
# subtle one, so they get a dedicated check instead of relying on manual
# code review alone.

const MainScript = preload("res://scripts/core/Main.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	await _check_hitstop_restores()
	await _check_hitstop_ignores_overlap()
	await _check_world_environment_wired()

	if failures == 0:
		print("PASS: AAA Polish Phase 1 - Hitstop self-restores, WorldEnvironment glow wired into the pixel viewport")
	get_tree().quit(0 if failures == 0 else 1)

# Engine.time_scale is global state - if this fails, EVERY scene in the
# game silently runs in slow motion until process restart. Confirm the
# freeze applies immediately, and that it recovers on its own (via the
# ignore_time_scale recovery timer) without any other code having to
# intervene.
func _check_hitstop_restores():
	Engine.time_scale = 1.0 # known baseline regardless of check run order
	var duration = 0.05
	HitstopManager.trigger(duration, 0.05)
	_check("time_scale actually drops when Hitstop triggers", Engine.time_scale < 1.0)

	# Real-world wait comfortably past `duration` - the recovery timer is
	# ignore_time_scale=true, so it fires on wall-clock time regardless of
	# how slow game time itself is currently running.
	await get_tree().create_timer(duration + 0.15, true, false, true).timeout
	_check("time_scale restores to 1.0 on its own after the freeze duration elapses", Engine.time_scale == 1.0)

# A second trigger arriving mid-freeze (e.g. an execution landing right as
# a boss dies) must not stack/extend the freeze or leave two competing
# restores fighting over time_scale.
func _check_hitstop_ignores_overlap():
	Engine.time_scale = 1.0
	HitstopManager.trigger(0.05, 0.05)
	HitstopManager.trigger(5.0, 0.01) # would freeze for 5s if this weren't ignored - check would hang instead of failing fast, so the assertion below is really "the first trigger's SHORT duration won, not the second's long one"
	await get_tree().create_timer(0.25, true, false, true).timeout
	_check("an overlapping trigger while one is already active is ignored (short first duration wins, doesn't stack)",
		Engine.time_scale == 1.0)

func _check_world_environment_wired():
	var main = MainScript.new()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var layer = main.get_node_or_null("PixelViewportLayer")
	if not layer:
		_check("Main built its PixelViewportLayer (harness assumption broke)", false)
		main.queue_free()
		return
	var container = layer.get_node_or_null("PixelViewportContainer")
	var viewport = container.get_node_or_null("PixelViewport") if container else null
	var world_env = viewport.get_node_or_null("PixelViewportEnvironment") if viewport else null

	_check("PixelViewport contains a WorldEnvironment node", world_env != null and world_env is WorldEnvironment)
	if world_env:
		var env: Environment = world_env.environment
		_check("WorldEnvironment has an Environment resource with glow enabled",
			env != null and env.glow_enabled)
		_check("world (battlefield Node2D) is still a sibling under the same viewport, unaffected by the new node",
			viewport.get_node_or_null("World") == main.world)

	main.queue_free()
	await get_tree().process_frame
