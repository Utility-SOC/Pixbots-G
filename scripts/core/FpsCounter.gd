extends CanvasLayer

# Always-on-top FPS/frame-time overlay (per the user: "add a framerate
# counter so I don't have to use video to show this in the future"). An
# autoload, not wired into any one screen's HUD, so it's visible everywhere
# - Main Menu, Garage, combat, War Room - without needing separate wiring
# per screen the way wave_label/timer_label etc. are Main.gd-only.
#
# Shows FPS AND frame time in milliseconds - FPS alone flattens out at low
# framerates (30 vs 20 vs 15 fps all just read as "bad"), while ms scales
# linearly and is what actually explains "why": a Garage freeze spiking to
# 500ms is instantly legible as a real stall, not just a vague low number.
# Color-coded so a single screenshot (no video needed) tells the story:
# green = fine, yellow = notice, red = a real problem.

var label: Label
# Second line: a physics/script-process time breakdown plus live entity
# counts, so the NEXT time framerate tanks in a real session we get
# trustworthy numbers correlated with what's actually on screen, instead of
# another video or a guess. (A synthetic headless stress-test harness was
# tried first - scripts/debug/ProjectileBroadphaseProfileDiagnostic.gd - but its
# own timing methodology proved unreliable: wall-clock across awaited
# physics frames just measures engine frame-pacing, and summing
# Performance.TIME_PHYSICS_PROCESS across those same awaits produced
# self-contradicting numbers. The one trustworthy signal it DID surface -
# PHYSICS_2D_ACTIVE_OBJECTS/COLLISION_PAIRS staying near zero even with 60
# mechs + 300 projectiles live - argues against Area2D broadphase being the
# bottleneck, but real in-session numbers beat a shaky synthetic one.)
var breakdown_label: Label
# Third line: real rendering metrics (draw calls, objects, primitives) -
# task #14's "draw batching" scope needs its OWN direct evidence, same
# lesson as the physics/process breakdown above: don't touch rendering
# code on a guess. These are Godot's actual render-server counters, not an
# inferred/timing-based proxy, so they're trustworthy the instant they're
# read - no synthetic-harness pitfalls to worry about here.
var render_label: Label
# Fourth line: aggregate wall-clock time spent in Mech._execute_ai_tactics /
# _shoot / move_and_slide across every mech and drone, sampled once a second
# - see Mech.gd's _perf_ai_tactics_usec/_perf_shoot_usec/_perf_move_usec for
# where these are actually measured. Direct evidence for whichever of those
# three is actually eating the frame budget once enemies/drones are on
# screen, instead of inferring it from aggregate phys/proc numbers alone.
var perf_label: Label
# Fifth line: the ai_tactics/shoot/move_and_slide breakdown above proved
# NOT to be the bottleneck (mosey drove ai_tactics near zero even at 70-90
# enemies, but overall frame time didn't budge - see the conversation this
# was captured from) - proc (TIME_PROCESS, pure _process()/`_draw()` time)
# was the actually-suspicious number, bigger than phys in the worst frame,
# and nothing above measures _process() at all. This line covers the two
# strongest _process()-side candidates: MechStatusBars._draw() (no LOD gate,
# fires on any hp/shield change - most mechs, most frames, in heavy combat)
# and Projectile._physics_process (441 live shots was the number that
# raised this - see Projectile.gd's _perf_physics_usec for the full story).
var perf_label2: Label
var _perf_sample_timer: float = 0.0
const PERF_SAMPLE_INTERVAL = 1.0
var _frame_times: Array[float] = []
const SMOOTH_WINDOW = 20 # rolling average - raw per-frame jitter is noisy

func _ready():
	layer = 999 # above everything - HUD (5), War Room (99), Debug Menu (100)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Anchored top-LEFT, stacked in a VBoxContainer with left-aligned,
	# autowrapping text - NOT the old top-right layout with a fixed negative
	# offset and hand-guessed per-line Y positions. That layout depended on
	# the window being wide enough to fit "viewport_width - 220" worth of
	# box, and once the breakdown line grew (enemy/pairs counts added), its
	# content outgrew the declared box and silently overflowed past the
	# window's own right edge - genuinely unrenderable, not just
	# clipped-and-recoverable, since a window can't draw past its own pixel
	# bounds. Per the user: "it is just cut off... it never shows up
	# properly on the screen." A VBoxContainer means a wrapped line just
	# pushes the next label down automatically - no manual Y math to get
	# wrong a second time.
	#
	# Y offset (95, not 4) clears Main.gd's own wave_label/timer_label HUD
	# block (position (20,20)/(20,60), 32pt+24pt fonts - roughly y:20-90) -
	# the user's own report: text outline alone wasn't enough contrast once
	# this overlay and that HUD landed on the same pixels. No single spot is
	# conflict-free on every screen this autoload is visible on (Garage's
	# tab row sits near the top too), so the semi-opaque background panel
	# below is the general fix - the Y offset just avoids the one collision
	# that matters most (gameplay's own wave/lives readout, the same screen
	# this overlay exists to debug).
	const OVERLAY_WIDTH = 260.0

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.55)
	bg_style.content_margin_left = 6
	bg_style.content_margin_right = 6
	bg_style.content_margin_top = 4
	bg_style.content_margin_bottom = 4

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(4, 95)
	panel.add_theme_stylebox_override("panel", bg_style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(OVERLAY_WIDTH, 0)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	box.add_child(label)

	breakdown_label = Label.new()
	breakdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	breakdown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	breakdown_label.add_theme_font_size_override("font_size", 12)
	breakdown_label.add_theme_constant_override("outline_size", 3)
	breakdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	breakdown_label.modulate = Color(0.85, 0.85, 0.85)
	box.add_child(breakdown_label)

	render_label = Label.new()
	render_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	render_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	render_label.add_theme_font_size_override("font_size", 12)
	render_label.add_theme_constant_override("outline_size", 3)
	render_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	render_label.modulate = Color(0.75, 0.85, 0.95)
	box.add_child(render_label)

	perf_label = Label.new()
	perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	perf_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label.add_theme_font_size_override("font_size", 12)
	perf_label.add_theme_constant_override("outline_size", 3)
	perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	perf_label.modulate = Color(1.0, 0.75, 0.6)
	box.add_child(perf_label)

	perf_label2 = Label.new()
	perf_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	perf_label2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label2.add_theme_font_size_override("font_size", 12)
	perf_label2.add_theme_constant_override("outline_size", 3)
	perf_label2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	perf_label2.modulate = Color(0.8, 0.9, 1.0)
	box.add_child(perf_label2)

func _process(delta: float):
	if not visible:
		return
	_frame_times.append(delta)
	if _frame_times.size() > SMOOTH_WINDOW:
		_frame_times.pop_front()
	var avg_delta = 0.0
	for d in _frame_times:
		avg_delta += d
	avg_delta /= _frame_times.size()

	var fps = Engine.get_frames_per_second()
	var ms = avg_delta * 1000.0
	label.text = "%d fps  %.1f ms" % [fps, ms]

	# 60fps target -> 16.7ms. Yellow past a dropped-frame-or-two budget,
	# red once it's a genuinely visible stutter.
	if ms > 50.0:
		label.modulate = Color(1.0, 0.3, 0.3)
	elif ms > 20.0:
		label.modulate = Color(1.0, 0.85, 0.2)
	else:
		label.modulate = Color(0.4, 1.0, 0.5)

	var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var proj_count = ProjectileManager.live_count() if ProjectileManager else 0
	var enemy_count = EntityCache.get_group("enemy").size() if EntityCache else 0
	# Drone.gd extends Mech but its _ready() never calls super._ready(), so
	# drones were invisible to every group-based query in the game (this
	# count included) until Drone.gd was given its own "drone"
	# add_to_group() call - see that file's _ready() for the full story.
	# Separate from enemy_count (which now also includes enemy-owned drones)
	# so this line can distinguish "how many full mechs" from "how many
	# drones on top of that," since drones run their own _physics_process
	# too and weren't previously visible in this breakdown at all.
	var drone_count = EntityCache.get_group("drone").size() if EntityCache else 0
	var collision_pairs = Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	breakdown_label.text = "phys %.1fms  proc %.1fms  |  %d shots  %d enemies  %d drones  %d pairs" % [
		physics_ms, process_ms, proj_count, enemy_count, drone_count, collision_pairs
	]

	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	render_label.text = "%d draws  %d objs  %.0fk verts" % [draw_calls, objects, primitives / 1000.0]

	# Sampled every PERF_SAMPLE_INTERVAL (not every frame) - these are
	# CUMULATIVE microsecond totals across however many physics ticks land
	# in that window, so reading them every frame would just show noisy
	# partial sums. Reset on read so each sample reflects only its own
	# window, not an ever-growing total since launch.
	_perf_sample_timer -= delta
	if _perf_sample_timer <= 0.0:
		_perf_sample_timer = PERF_SAMPLE_INTERVAL
		var ai_ms = Mech._perf_ai_tactics_usec / 1000.0
		var shoot_ms = Mech._perf_shoot_usec / 1000.0
		var move_ms = Mech._perf_move_usec / 1000.0
		Mech._perf_ai_tactics_usec = 0
		Mech._perf_shoot_usec = 0
		Mech._perf_move_usec = 0
		perf_label.text = "per sec: ai_tactics %.0fms  shoot %.0fms  move_and_slide %.0fms" % [ai_ms, shoot_ms, move_ms]

		var status_bar_ms = MechStatusBars._perf_draw_usec / 1000.0
		var proj_physics_ms = Projectile._perf_physics_usec / 1000.0
		MechStatusBars._perf_draw_usec = 0
		Projectile._perf_physics_usec = 0
		perf_label2.text = "per sec: status_bars_draw %.0fms  projectile_physics %.0fms" % [status_bar_ms, proj_physics_ms]

func _unhandled_input(event: InputEvent):
	# F3: the common cross-game convention for a debug/perf overlay toggle.
	# Deliberately a raw physical-keycode check, not a new InputMap action -
	# this is a dev/QA utility, not a bindable gameplay action that should
	# show up in a future "remap controls" list.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()
