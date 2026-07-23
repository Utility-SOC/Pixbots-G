extends Node

# Task #12: game-over explosion + crater cinematic. Verifies GameOverCinematic.gd
# in isolation (not through the full Main.gd death flow - same narrower-but-
# meaningful test boundary as ContiguousAccumulatorCheck.gd/
# ReverseAccumulatorCheck.gd use for testing a helper directly):
#   1. A "GAME OVER" label is created and fades in.
#   2. Engine.time_scale dips for the slow-mo beat, then genuinely returns
#      to 1.0 on its own (not left slowed forever - the exact bug this test
#      exists to catch, since a leaked time_scale would slow-mo the ENTIRE
#      game afterward).
#   3. The battle camera (found via the "camera" group, same lookup
#      CameraShake._enter_strategic uses) detaches from its parent
#      (top_level) and pushes in toward the death position.
#   4. The whole cinematic self-frees well before Main.gd's real 3-second
#      Garage-transition timer would fire, so nothing is still animating
#      once the world pauses for the Garage.

const GameOverCinematicScript = preload("res://scripts/visuals/GameOverCinematic.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	Engine.time_scale = 1.0 # clean baseline regardless of prior state

	var world = Node2D.new()
	add_child(world)

	var camera = Camera2D.new()
	camera.set_script(load("res://scripts/core/CameraShake.gd"))
	camera.add_to_group("camera")
	camera.global_position = Vector2(100, 100)
	camera.zoom = Vector2(1.5, 1.5)
	world.add_child(camera)

	var death_pos = Vector2(900, -300)
	var cinematic = GameOverCinematicScript.new()
	cinematic.death_position = death_pos
	world.add_child(cinematic)

	var label = cinematic.get_children().filter(func(c): return c is Label)[0] if cinematic.get_child_count() > 0 else null
	_check("a GAME OVER label was created", label != null and label.text == "GAME OVER")
	_check("label starts fully transparent (about to fade in)", label != null and label.modulate.a < 0.01)

	_check("Engine.time_scale dips immediately for the slow-mo beat", Engine.time_scale < 1.0)
	_check("camera detaches from its parent (top_level) to free-move toward the crater", camera.top_level == true)
	_check("camera position smoothing disabled so the push-in isn't fighting a smoothed follow", camera.position_smoothing_enabled == false)

	# Poll (real time, since Engine.time_scale slows sim-time delivery) until
	# the label has fully faded in and time_scale has genuinely restored.
	var label_faded = false
	var scale_restored = false
	for i in range(600): # generous ceiling - up to ~10s real time at 60fps polling
		await get_tree().process_frame
		if not label_faded and is_instance_valid(label) and label.modulate.a > 0.99:
			label_faded = true
		if not scale_restored and Engine.time_scale >= 0.999:
			scale_restored = true
		if label_faded and scale_restored:
			break

	_check("GAME OVER label fully fades in", label_faded)
	_check("Engine.time_scale genuinely returns to 1.0 (not left slow-mo'd)", scale_restored)
	_check("Engine.time_scale is exactly 1.0 after restoring, not some other stray value", Engine.time_scale == 1.0)

	var moved_toward_target = camera.global_position.distance_to(death_pos) < camera.global_position.distance_to(Vector2(100, 100))
	_check("camera actually moved toward the death position (push-in)", moved_toward_target)
	_check("camera zoomed in (push-in), not out", camera.zoom.x < 1.5)

	# Cinematic should self-free shortly after - well before Main.gd's real
	# 3-second Garage timer would fire.
	var self_freed = false
	for i in range(300):
		await get_tree().process_frame
		if not is_instance_valid(cinematic):
			self_freed = true
			break
	_check("cinematic self-frees on its own (doesn't linger)", self_freed)

	Engine.time_scale = 1.0 # tidy up regardless of outcome
	if failures == 0:
		print("PASS: game-over cinematic fades in a title card, slow-mo dips and genuinely restores, camera pushes toward the crater, and self-frees")
	get_tree().quit(0 if failures == 0 else 1)
