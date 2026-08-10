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
# Sixth-and-a-half line: Main's wave-clear bookkeeping (active_enemies,
# _spawning_wave, current_wave), added 2026-08-05 after TWO prior blind
# fixes to a "stuck on a wave forever" report both failed to actually
# resolve it - the underlying state was never visible in any screenshot,
# forcing every diagnosis to reason from visual symptoms alone. Reads
# Main via get_tree().current_scene (same lookup pattern MissileRackTile.gd/
# SquadDirector.gd use elsewhere for cross-script state) rather than a new
# autoload - this is diagnostic-only, no other system needs to reach it.
var wave_state_label: Label
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
# Seventh line (wave-138 playtest: "shoot"/"projectile_physics" dwarfing
# everything else, but with no way to tell how much of "shoot" was real
# firing work vs. per-tick overhead on ticks that had nothing ready to fire,
# and ProjectileBroadphase/Mech.apply_damage were both completely invisible
# blind spots) - see Mech._perf_shoot_fired_usec/_perf_shoot_checked_only_usec/
# _perf_apply_damage_usec and ProjectileBroadphase._perf_physics_usec.
var perf_label3: Label
# Eighth line: breakdown of the "bot_spawn" bucket on perf_label3 (confirmed
# dominant by live playtest: 927ms/sec while actively spawning) - see
# Mech._perf_shape_gen_usec/_perf_build_loadout_usec/_perf_visual_build_usec.
var perf_label4: Label
# Ninth line: AutoEquipSolver's internal cost breakdown (live playtest:
# build_loadout - perf_label4 above - confirmed as the single biggest perf
# problem this session, 1300-2700ms/sec at wave 160+; this line answers
# WHICH of solve()'s four candidate cost centers actually dominates) - see
# AutoEquipSolver.gd's own _perf_bfs_usec/_perf_lengthen_path_usec/
# _perf_reattach_usec/_perf_placement_scan_usec.
var perf_label5: Label
# Sixth line: build/version tag - see _compute_build_version() below.
var version_label: Label
var _perf_sample_timer: float = 0.0
const PERF_SAMPLE_INTERVAL = 1.0
var _frame_times: Array[float] = []
const SMOOTH_WINDOW = 20 # rolling average - raw per-frame jitter is noisy

# Build/version tag, so a bug report's screenshot says which build produced
# it without needing to separately ask "what version are you on?" - resolved
# once in _ready() and cached, not recomputed every frame. project.godot's
# config/version (bumped per release tag, e.g. "1.1.4") is the primary
# source since it's baked into every export, editor or not. The short git
# commit hash is a bonus, dev-only signal layered on top when available -
# OS.execute("git", ...) only succeeds when running from a source checkout
# with a .git folder next to the executable, which an exported build never
# ships (no shim/fallback needed - a failed execute here just leaves the
# hash blank, same as any other "not applicable" case elsewhere in this
# file, e.g. ProjectileManager/EntityCache being null in the editor).
var _build_version_text: String = ""

# Drag-to-move (playtest report: the overlay's fixed top-left spot overlaps
# the Garage's component tab row - "Torso / L. Arm / R. Arm / ..." became
# unreadable underneath it). F3 already toggled visibility (see
# _unhandled_input below); this adds click-and-drag repositioning on top of
# that, with the chosen position persisted across sessions the same way
# SettingsMenu persists volume/controls - via SaveManager.SETTINGS_PATH.
var panel: PanelContainer
var _dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_panel_pos: Vector2 = Vector2.ZERO
const SETTINGS_SECTION = "FpsOverlay"
const DEFAULT_POSITION = Vector2(4, 95)

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

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = _load_position()
	panel.add_theme_stylebox_override("panel", bg_style)
	# STOP, not IGNORE - needed to receive the mouse-down that starts a drag.
	# Only this small overlay panel grabs input, not the whole screen, so
	# gameplay clicks everywhere else are unaffected.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
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

	wave_state_label = Label.new()
	wave_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wave_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wave_state_label.add_theme_font_size_override("font_size", 12)
	wave_state_label.add_theme_constant_override("outline_size", 3)
	wave_state_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	wave_state_label.modulate = Color(0.9, 0.7, 0.95)
	box.add_child(wave_state_label)

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

	perf_label3 = Label.new()
	perf_label3.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	perf_label3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label3.add_theme_font_size_override("font_size", 12)
	perf_label3.add_theme_constant_override("outline_size", 3)
	perf_label3.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	perf_label3.modulate = Color(0.85, 1.0, 0.8)
	box.add_child(perf_label3)

	perf_label4 = Label.new()
	perf_label4.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	perf_label4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label4.add_theme_font_size_override("font_size", 12)
	perf_label4.add_theme_constant_override("outline_size", 3)
	perf_label4.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	perf_label4.modulate = Color(1.0, 0.85, 1.0)
	box.add_child(perf_label4)

	perf_label5 = Label.new()
	perf_label5.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	perf_label5.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label5.add_theme_font_size_override("font_size", 12)
	perf_label5.add_theme_constant_override("outline_size", 3)
	perf_label5.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	perf_label5.modulate = Color(0.75, 1.0, 1.0)
	box.add_child(perf_label5)

	_build_version_text = _compute_build_version()
	version_label = Label.new()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version_label.add_theme_font_size_override("font_size", 11)
	version_label.add_theme_constant_override("outline_size", 3)
	version_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	version_label.modulate = Color(0.6, 0.6, 0.6)
	version_label.text = _build_version_text
	box.add_child(version_label)

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

	var main = get_tree().current_scene
	if main and "active_enemies" in main:
		wave_state_label.text = "wave %s  active_enemies %s  spawning %s" % [
			str(main.get("current_wave")), str(main.get("active_enemies")), str(main.get("_spawning_wave"))
		]
		wave_state_label.visible = true
	else:
		wave_state_label.visible = false

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
		# projectile_construct: just the add_child(proj) call inside HexTile.
		# _fire_combined_projectile (Projectile._ready() - ratio/stat calc +
		# _build_visuals()'s child-node construction) - a SLICE of shoot_ms
		# above, not a separate cost, isolating whether "shoot" at volume is
		# dominated by construction or by the merge/pattern math around it.
		var construct_ms = HexTile._perf_projectile_construct_usec / 1000.0
		# collect/rust_call: ProjectileManager's per-tick flight-batch dispatch
		# (2026-08-03 physics-tick-at-scale investigation) - collect is the
		# GDScript-side request-building loop, rust_call is the single
		# compute_batch_flat FFI call. Split out because the flat-array
		# rewrite specifically targeted rust_call (was ~1.94ms/tick with the
		# old Dictionary-array marshalling at 500 live shots, ~0.4ms/tick
		# after - see Status.md), so live playtests can confirm the win holds
		# at real combat volumes, not just this session's synthetic tests.
		var collect_ms = ProjectileManager._perf_collect_usec / 1000.0
		var rust_call_ms = ProjectileManager._perf_rust_call_usec / 1000.0
		MechStatusBars._perf_draw_usec = 0
		Projectile._perf_physics_usec = 0
		HexTile._perf_projectile_construct_usec = 0
		ProjectileManager._perf_collect_usec = 0
		ProjectileManager._perf_rust_call_usec = 0
		# blink_query: ProjectileTargetingBatcher._resolve_blink()'s whole
		# batched call - replaces what used to be an invisible cost hidden
		# inside projectile_physics above (every Lightning-ratio projectile's
		# own independent O(entities) scan, now one shared batched query per
		# tick - see Projectile._update_blink's own comment for the full story).
		var blink_ms = Projectile._perf_blink_query_usec / 1000.0
		Projectile._perf_blink_query_usec = 0
		perf_label2.text = "per sec: status_bars_draw %.0fms  projectile_physics %.0fms  projectile_construct %.0fms  flight_collect %.0fms  flight_rust_call %.0fms  blink_query %.0fms" % [
			status_bar_ms, proj_physics_ms, construct_ms, collect_ms, rust_call_ms, blink_ms
		]

		# shoot_fired/shoot_checked: splits shoot_ms above by whether that
		# tick's _shoot() call actually fired a weapon or just paid the
		# charge-check/tax-math overhead for nothing - see Mech._shoot's own
		# comment. broadphase/apply_dmg: two real costs that were previously
		# invisible to this whole overlay.
		var shoot_fired_ms = Mech._perf_shoot_fired_usec / 1000.0
		var shoot_checked_ms = Mech._perf_shoot_checked_only_usec / 1000.0
		var broadphase_ms = ProjectileBroadphase._perf_physics_usec / 1000.0
		var apply_dmg_ms = Mech._perf_apply_damage_usec / 1000.0
		Mech._perf_shoot_fired_usec = 0
		Mech._perf_shoot_checked_only_usec = 0
		ProjectileBroadphase._perf_physics_usec = 0
		Mech._perf_apply_damage_usec = 0
		# bot_spawn: user report (2026-08-09) - "while they are spawning it is
		# REALLY slow, and when they are just existing it isn't nearly as
		# bad." Wraps SquadDirector._spawn_bot_for_role's add_child(bot) call,
		# which triggers Mech._ready() -> build_loadout_for_role() (AutoEquip
		# Solver + procedural shape generation) synchronously in one frame -
		# the likely burst-cost culprit, unconfirmed without a real playtest.
		var bot_spawn_ms = SquadDirector._perf_bot_spawn_usec / 1000.0
		SquadDirector._perf_bot_spawn_usec = 0
		perf_label3.text = "per sec: shoot_fired %.0fms  shoot_checked %.0fms  broadphase %.0fms  apply_dmg %.0fms  bot_spawn %.0fms" % [
			shoot_fired_ms, shoot_checked_ms, broadphase_ms, apply_dmg_ms, bot_spawn_ms
		]

		# bot_spawn breakdown - see Mech._perf_shape_gen_usec/_perf_build_
		# loadout_usec/_perf_visual_build_usec's own comment.
		var shape_gen_ms = Mech._perf_shape_gen_usec / 1000.0
		var build_loadout_ms = Mech._perf_build_loadout_usec / 1000.0
		var visual_build_ms = Mech._perf_visual_build_usec / 1000.0
		Mech._perf_shape_gen_usec = 0
		Mech._perf_build_loadout_usec = 0
		Mech._perf_visual_build_usec = 0
		perf_label4.text = "bot_spawn breakdown: shape_gen %.0fms  build_loadout %.0fms  visual_build %.0fms" % [
			shape_gen_ms, build_loadout_ms, visual_build_ms
		]

		# AutoEquipSolver's own internal breakdown - only non-zero on a cache
		# miss/deviation-test roll (a cache hit replays a cached plan and
		# never enters _solve_impl at all) - see that file's own comment.
		var solver_bfs_ms = AutoEquipSolver._perf_bfs_usec / 1000.0
		var solver_lengthen_ms = AutoEquipSolver._perf_lengthen_path_usec / 1000.0
		var solver_reattach_ms = AutoEquipSolver._perf_reattach_usec / 1000.0
		var solver_scan_ms = AutoEquipSolver._perf_placement_scan_usec / 1000.0
		# cache_key runs on EVERY solve() call, even cache hits (sorts+
		# formats the whole inventory just to check the cache) - extract_plan
		# only on a miss, once, to build the new cache entry.
		var solver_cache_key_ms = AutoEquipSolver._perf_cache_key_usec / 1000.0
		var solver_extract_plan_ms = AutoEquipSolver._perf_extract_plan_usec / 1000.0
		AutoEquipSolver._perf_bfs_usec = 0
		AutoEquipSolver._perf_lengthen_path_usec = 0
		AutoEquipSolver._perf_reattach_usec = 0
		AutoEquipSolver._perf_placement_scan_usec = 0
		AutoEquipSolver._perf_cache_key_usec = 0
		AutoEquipSolver._perf_extract_plan_usec = 0
		perf_label5.text = "solve() breakdown: cache_key %.0fms  bfs %.0fms  lengthen_path %.0fms  reattach %.0fms  placement_scan %.0fms  extract_plan %.0fms" % [
			solver_cache_key_ms, solver_bfs_ms, solver_lengthen_ms, solver_reattach_ms, solver_scan_ms, solver_extract_plan_ms
		]

## Resolves once at _ready() (see _build_version_text) - never called again,
## OS.execute() is too slow to run per-frame even if it always succeeded.
func _compute_build_version() -> String:
	var version = ProjectSettings.get_setting("application/config/version", "")
	var text = ("v%s" % version) if version != "" else "dev build"

	var output = []
	var exit_code = OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)
	if exit_code == 0 and output.size() > 0:
		var commit_hash = String(output[0]).strip_edges()
		if commit_hash != "":
			text += " (%s)" % commit_hash

	return text

## path_override lets tests round-trip against a scratch file instead of
## the real SaveManager.SETTINGS_PATH (user://settings.cfg) - never write
## real user settings from an automated test.
func _load_position(path_override: String = "") -> Vector2:
	var settings_path = path_override if path_override != "" else SaveManager.SETTINGS_PATH
	var config = ConfigFile.new()
	if config.load(settings_path) != OK:
		return DEFAULT_POSITION
	var x = config.get_value(SETTINGS_SECTION, "x", DEFAULT_POSITION.x)
	var y = config.get_value(SETTINGS_SECTION, "y", DEFAULT_POSITION.y)
	return Vector2(x, y)

func _save_position(path_override: String = ""):
	var settings_path = path_override if path_override != "" else SaveManager.SETTINGS_PATH
	var config = ConfigFile.new()
	config.load(settings_path) # ok to fail (fresh file) - set_value below still works
	config.set_value(SETTINGS_SECTION, "x", panel.position.x)
	config.set_value(SETTINGS_SECTION, "y", panel.position.y)
	config.save(settings_path)

func _unhandled_input(event: InputEvent):
	# F3: the common cross-game convention for a debug/perf overlay toggle.
	# Deliberately a raw physical-keycode check, not a new InputMap action -
	# this is a dev/QA utility, not a bindable gameplay action that should
	# show up in a future "remap controls" list.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()
			return

	# Click-and-drag to move (playtest report: fixed top-left position
	# overlapped the Garage's component tab row). Position persists via
	# SaveManager.SETTINGS_PATH the same way SettingsMenu persists other
	# preferences, so a drag survives a restart.
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and panel.get_global_rect().has_point(event.position):
			_dragging = true
			_drag_start_mouse = event.position
			_drag_start_panel_pos = panel.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and _dragging:
			_dragging = false
			_save_position()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var target = _drag_start_panel_pos + (event.position - _drag_start_mouse)
		# Clamp so the panel can always be dragged back into view - can't get
		# permanently lost off-screen the way the tutorial panel bug (same
		# session) could silently do.
		var vp_size = get_viewport().get_visible_rect().size
		target.x = clamp(target.x, 0.0, max(0.0, vp_size.x - panel.size.x))
		target.y = clamp(target.y, 0.0, max(0.0, vp_size.y - panel.size.y))
		panel.position = target
		get_viewport().set_input_as_handled()
