extends Node2D
const MapGenerator = preload("res://scripts/core/MapGenerator.gd")
const Mech = preload("res://scripts/entities/Mech.gd")

const WeaponMountTile = preload("res://scripts/tiles/WeaponMountTile.gd")
const DroneBayTile = preload("res://scripts/tiles/DroneBayTile.gd")
const ChampionCardScript = preload("res://scripts/pvp/ChampionCard.gd")
const SquadTemplateMutatorScript = preload("res://scripts/ai/SquadTemplateMutator.gd")
const CutscenePlayer = preload("res://scripts/cutscene/CutscenePlayer.gd")
const BrandRegistry = preload("res://scripts/core/BrandRegistry.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

# Companion Drones (see Drone.gd/DroneBayTile.gd): one spawned alongside the
# player per Drone Bay tile installed anywhere in their Backpack on deploy -
# a build can carry more than one bay, each flying an independent drone with
# its own loadout. Each is destroyed and respawned after its own cooldown if
# it dies mid-run - "destructible, respawns" per the user's design choice.
# Both dictionaries are keyed by the owning DroneBayTile's instance ID (the
# tile itself, not the Drone node, since that's what survives a drone's
# death/respawn cycle and what GarageMenu edits).
var drone_nodes: Dictionary = {} # bay instance ID -> Drone
var _drone_respawn_timers: Dictionary = {} # bay instance ID -> float seconds remaining
const DRONE_RESPAWN_DELAY = 8.0

var current_mode: String = "sandbox"
var current_wave: int = 1
# Guaranteed once-per-wave Mythic-tier introduction, from MYTHIC_MILESTONE_
# START_WAVE onward - replaces the old per-spawn mythic_seed_chance random
# roll (SquadDirector._spawn_bot_for_role used to independently roll up to
# 20% of ALL spawns to Mythic, regardless of role/template, which scattered
# rarity unpredictably across every wave and was real AutoEquipSolver
# topology-cache/StockBuildEvolution-cache churn - see this session's own
# spawn-perf investigation). A deterministic, single, predictable event per
# wave instead of a diffuse chance across many bots - reset in _start_wave(),
# consumed by the first SquadDirector._spawn_bot_for_role call that checks
# it each wave. Per the user: first Mythic-tier grunt at wave 75 (bosses get
# their own separate always-on rule from that point too - see Main.
# _spawn_boss); wave 110+ additionally lets the loot table start dropping
# Mythic-tier COMPONENTS (not just tiles) - that's a LootManager-side change,
# explicitly out of scope here, not yet implemented.
const MYTHIC_MILESTONE_START_WAVE = 75
var _wave_guaranteed_mythic_used: bool = false
var campaign_data: Dictionary = {}
var active_enemies: int = 0
var garage_timer: float = 90.0
# Wave spawns spread across roughly this much of garage_timer's own 90s
# countdown (user: "90 per wave just for spawning, they spawn spread out
# over 90 seconds") instead of the old ~2-3s burst (a whole wave's worth
# of squads separated only by a fixed 0.12s anti-freeze beat, all landing
# in the first few seconds after wave start) - see _spawn_wave_async's own
# comment. Deliberately less than garage_timer's full 90.0 (WAVE_SPAWN_
# SAFETY_MARGIN_SECONDS below reserves the tail end) so the last spawned
# squad still has real time to matter before extraction opens, rather than
# walking in right as the marker appears.
const WAVE_SPAWN_SPREAD_SECONDS = 75.0
const WAVE_SPAWN_SAFETY_MARGIN_SECONDS = 8.0
# Used only to ESTIMATE how many squads remain (for interval pacing) -
# real squad sizes vary 3-5 per SquadTemplate.required_roles; the interval
# recomputes every squad against the actual remaining enemy count, so this
# only needs to be roughly right, not exact.
const WAVE_SPAWN_AVG_SQUAD_SIZE_ESTIMATE = 4.0

# Tournament mode bracket (see the current_wave % 1 dispatch below): the
# 15 Regulars, then whichever Elite Four champions this save has already
# beaten via normal play, then Frank as a twist-finale capstone if and only
# if all 4 champions made the cut. Built once at wave 1 of a Tournament run
# (save state doesn't change mid-run) so per-wave dispatch is a simple index
# instead of re-deriving variable-length champion eligibility every wave.
var _tournament_bracket: Array = []

# Per-run map rotation (design ruling, see _setup_environment) - Tabletop is
# weighted double since it's the game's eventual identity.
const MAP_ROTATION_TYPES = ["Tabletop", "Tabletop", "Normal", "Open Field", "Forest", "Desert", "Tundra", "Volcano", "Dungeon", "Water", "FightShovel"]

# Per the user: "in campaign mode, the map should change every ten waves, or
# every 3 minutes, whichever is faster. (I'd like to be able to tune that
# later because I don't know how 3m actually feels)" - two independent
# triggers, whichever fires first regenerates the terrain (see
# _should_rotate_map/_rotate_campaign_map). Kept as plain top-of-file
# constants rather than buried in a config resource - the whole point was
# "so I can tune it," and this is the fastest place to find and change them.
const MAP_ROTATION_MAX_WAVES = 10
const MAP_ROTATION_MAX_SECONDS = 180.0
var _map_rotation_wave_start: int = 1
var _map_rotation_elapsed: float = 0.0

var map: MapGenerator
var garage_ui: CanvasLayer
var player: Mech
var player_inventory: Array = []
var player_component_inventory: Array = []
var player_scrap: int = 0
# Extracted stat modifiers waiting to be equipped onto a part (feature 5).
# Each entry: {"traits": Array[{"stat": String, "value": float}]} (task:
# Chip Splicing) - a plain chip has 1 trait, a Corrupted (spliced) chip
# has 2+, unbounded. Managed by GarageMenu/TileActionMenu.gd.
var player_modifier_chips: Array = []

# Corporate Sponsorships (task #17, BrandRegistry.gd) - "" means Free Agent
# (no sponsorship, the always-valid default). Selectable from wave 125
# onward, freely re-selectable later with no penalty - see BrandRegistry's
# header for the full design. Read by LootManager.generate_loot_for_mech()
# for the sponsor drip-feed bonus drop.
var player_sponsorship: String = ""

# Cosmetic hero paint color, stored as an HTML hex string (JSON save files
# have no native Color type - see SaveManager.save_game/load_game). Empty
# means "not rolled yet" - _setup_player() below rolls one from
# PLAYER_PAINT_PALETTE for a brand-new game, or for a save file saved
# before this feature existed. Curated rather than random RGB so every
# result reads as a deliberate hero color instead of a muddy roll - the
# same list the planned Paint Rack Garage tab will offer as swatches.
var player_paint_color: String = ""
const PLAYER_PAINT_PALETTE: Array[Color] = [
	Color(0.85, 0.15, 0.15), # the original hardcoded hero red - kept as an option, not just a fallback
	Color(0.15, 0.4, 0.85),  # cobalt blue
	Color(0.15, 0.65, 0.25), # racing green
	Color(0.9, 0.55, 0.1),   # sponsor orange
	Color(0.55, 0.15, 0.75), # royal purple
	Color(0.15, 0.75, 0.75), # cyan
	Color(0.9, 0.8, 0.15),   # gold
	Color(0.9, 0.3, 0.6),    # magenta
	Color(0.2, 0.2, 0.25),   # stealth black
	Color(0.9, 0.9, 0.9),    # arctic white
]


var hud_canvas: CanvasLayer
var wave_label: Label
var timer_label: Label
var extraction_marker: Node2D = null

var missile_charge_bg: ColorRect
var missile_charge_fg: ColorRect
var extraction_indicator: Polygon2D = null
# Jammers are no longer a full-screen dim (see JammerField.gd) - the
# player's Blind state is now "standing inside a hostile JammerField",
# checked continuously by _update_player_blind_state() below.
var player_is_blind: bool = false
var boss_health_bar_bg: ColorRect = null
var boss_health_bar_fg: ColorRect = null
var boss_health_label: Label = null
var dialogue_box: Panel = null
var dialogue_label: RichTextLabel = null
var dialogue_timer: float = 0.0

# The actual game world (map/mechs/projectiles/VFX) renders inside a small
# fixed-resolution SubViewport, then gets scaled up with nearest-neighbor
# filtering - this is what makes everything read as chunky pixel art
# instead of smooth vector shapes, no matter how coarse we snap individual
# polygon vertices. HUD/menus stay OUTSIDE this (added directly to Main)
# so text stays crisp and readable rather than also getting pixelated.
#
# The ground texture already looks chunky at basically any internal
# resolution because its "fat pixel" blocks are baked directly into the
# Image at generation time (see MapGenerator._paint_textured_tile) - that's
# NOT evidence the low-res viewport itself is pixelating things enough.
# Vector-drawn content (every mech) has no such baked-in chunkiness and is
# the honest test.
#
# IMPORTANT: SubViewportContainer.stretch = true makes the container drive
# the child SubViewport's actual render size to match the CONTAINER (i.e.
# the full window) - manually setting viewport.size gets silently
# overridden the moment stretch is enabled. That was the real bug behind
# the first two attempts at this: the viewport was rendering at native
# resolution the whole time, so changing the "size" constant did nothing.
# The actual documented mechanism for low-res pixel art is stretch_shrink,
# an integer divisor: the container renders its viewport at
# (container_size / stretch_shrink) and upscales by that same factor. This
# also adapts automatically to window resizing, which a fixed size wouldn't.
# Higher = chunkier/more pixelated, lower = closer to native/smoother.
#
# Mechs now bake their OWN genuine pixel grid directly (see
# MechPartRenderer.gd - real Image rasterization, not vector-then-downscale)
# at CELL_SIZE=3 world-units-per-cell. That means this viewport-level
# downscale is no longer the primary source of chunkiness for mechs - it's
# now a second, independent pixel grid layered on top of an already-baked
# one. If this factor pushes the viewport's own effective world-units-per-
# pixel finer than the mech sprites' baked CELL_SIZE, the viewport ends up
# re-quantizing already-crisp pixel art onto a second, misaligned grid,
# which can look worse, not better (a subtle jitter/moire rather than clean
# pixels). Keeping this modest avoids fighting the baked sprites, while
# still giving projectiles/particles/VFX (which are NOT baked pixel art)
# some benefit. If mechs ever stop baking their own pixels, this is the
# dial to push back up for the ground/world overall.
const PIXEL_SHRINK_FACTOR = 2
var world: Node2D

# Live-combat batch pool (2026-08-11 cutover) - always created once per
# battle (cheap: flat PackedArrays, no per-shot Nodes, nothing runs until
# something actually calls spawn()) and handed to ProjectileManager so
# HexTile._fire_combined_projectile can reach it without a new Main-
# specific getter. Whether anything actually FIRES through it is gated
# entirely by SaveManager.batch_renderer_in_combat (default off) via
# ProjectileManager.should_use_batch_pool() - this reference existing is
# not the same as it being in use.
const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
var _live_batch_pool: Node = null

# Battle camera zoom lives entirely in CameraShake.gd now (single owner of
# camera.zoom) - a second wheel-zoom system briefly lived here and fought
# the camera's own one every frame, causing the "pops back in" rubber-band.

func _ready():
	_setup_pixel_viewport()
	_load_campaign()
	_setup_environment()
	_setup_live_batch_pool()
	_setup_player()
	# _setup_player() may have just overwritten current_wave from a loaded
	# save - anchor the map-rotation wave counter to wherever the run
	# actually starts, not always wave 1.
	_map_rotation_wave_start = current_wave

	_setup_hud()

	# War Room (TAB) - the window into the AI director's learning loop.
	# Minimap (U) - drag to move, wheel to zoom, corner grip to resize.
	# NOTE: DebugMenu is NOT added here - it's already an autoload in
	# project.godot (adding it here too created a stacked double menu).
	add_child(load("res://scripts/ui/WarRoomMenu.gd").new())
	add_child(load("res://scripts/ui/MinimapOverlay.gd").new())
	# First-run onboarding (tutorial.json) - dormant after the player
	# completes or skips it once (user://tutorial_completed.flag).
	add_child(load("res://scripts/ui/TutorialManager.gd").new())
	# Centralized Esc-to-pause handling that works whether or not the tree
	# is currently paused (Garage/death) - see GlobalPauseHandler.gd's own
	# comment for why this replaced the old Main._unhandled_input +
	# GarageMenu._input dual-handler approach.
	add_child(load("res://scripts/ui/GlobalPauseHandler.gd").new())

	# Register gameplay actions that have no [input] section entry. The
	# cloak generator gates on InputMap.has_action("cloak") - without this
	# the action never existed, so AI ambushers could cloak and the PLAYER
	# never could (playtest: "how do I use my cloak generator?").
	# Hold C to cloak. Runtime-registered actions are rebindable through
	# the same InputMap the settings menu edits.
	if not InputMap.has_action("cloak"):
		InputMap.add_action("cloak")
		var cloak_key = InputEventKey.new()
		cloak_key.physical_keycode = KEY_C
		InputMap.action_add_event("cloak", cloak_key)
	# Heal Beacon pulse (module-keybind ruling: every active module gets a
	# button; shields stay passive). Press H when charged - see
	# Mech._update_healer's player branch.
	if not InputMap.has_action("heal_pulse"):
		InputMap.add_action("heal_pulse")
		var heal_key = InputEventKey.new()
		heal_key.physical_keycode = KEY_H
		InputMap.action_add_event("heal_pulse", heal_key)
	# Synergy jam pulse (J) - see Mech's SYNERGY jammer player branch.
	if not InputMap.has_action("jam_pulse"):
		InputMap.add_action("jam_pulse")
		var jam_key = InputEventKey.new()
		jam_key.physical_keycode = KEY_J
		InputMap.action_add_event("jam_pulse", jam_key)
	# Smoke Grenade (Ctrl, held) - per the user's design, Ctrl also triggers
	# Cloak at the same time if a Cloak Generator is equipped (see
	# CloakSystem.tick()'s wants_cloak, which ORs this action in alongside
	# the existing "cloak" action). See Mech.try_drop_smoke_grenade().
	if not InputMap.has_action("smoke_grenade"):
		InputMap.add_action("smoke_grenade")
		var smoke_key = InputEventKey.new()
		smoke_key.physical_keycode = KEY_CTRL
		InputMap.action_add_event("smoke_grenade", smoke_key)
	# toggle_war_room (Tab) registration moved into WarRoomMenu._ready()
	# itself - registering it only here meant the action never existed for
	# a War Room opened from the MAIN MENU scene (its "War Room" button
	# instantiates WarRoomMenu directly, Main.gd never runs), so Tab
	# silently did nothing there while Esc (built-in ui_cancel) worked -
	# playtest: "it says push tab to close the war room, but that doesn't
	# work. esc does, tab does not."

	# Per the user: every game start (new game or loaded save) should land in
	# the Garage first, not straight into combat - the player deploys
	# explicitly via "Deploy to Battlefield ->". _close_garage() already
	# handles kicking off the first wave's countdown on that initial
	# deploy (its "if active_enemies <= 0: _show_countdown()" - active_enemies
	# is still 0 at this point since nothing has spawned yet), so nothing
	# else needs to change for wave 1 to start correctly once the player
	# actually deploys.
	_open_garage()

func _setup_pixel_viewport():
	# A Control anchored PRESET_FULL_RECT under a bare Node2D (Main) doesn't
	# reliably inherit the window's rect - Godot's anchor system needs a
	# Control/CanvasLayer basis to size against, and a plain Node2D doesn't
	# provide one. hud_canvas (below, in _setup_hud) already proves the
	# CanvasLayer -> Control pattern works correctly in this exact project,
	# so the pixel viewport uses the same structure instead of relying on
	# anchor behavior under a Node2D parent that isn't guaranteed to resize
	# the container (the failure mode is a correctly-running but invisible/
	# zero-sized viewport - exactly a blank screen with only the HUD showing).
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "PixelViewportLayer"
	canvas_layer.layer = 0 # Below hud_canvas (layer 5), so HUD draws on top
	add_child(canvas_layer)

	var container = SubViewportContainer.new()
	container.name = "PixelViewportContainer"
	container.stretch = true
	container.stretch_shrink = PIXEL_SHRINK_FACTOR
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Deliberately leaving mouse_filter at its default (STOP) - the
	# SubViewportContainer needs to actively receive mouse events so it can
	# forward them into the SubViewport for player aiming.

	# Tabletop Diorama Shader (AAA Polish Roadmap Priority 2): applied here,
	# directly on the container that already presents the game world as its
	# own texture, rather than a separate fullscreen overlay - one layer
	# below hud_canvas, so this only ever touches the diegetic battlefield,
	# never HUD text. See the shader file's header for the full rationale.
	var diorama_shader = ShaderMaterial.new()
	diorama_shader.shader = load("res://scripts/shaders/diorama_tilt_shift.gdshader")
	container.material = diorama_shader

	canvas_layer.add_child(container)

	var viewport = SubViewport.new()
	viewport.name = "PixelViewport"
	# No explicit size - with stretch_shrink active, the container manages
	# the viewport's render size automatically (container.size / shrink),
	# continuously, including on window resize.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	world = Node2D.new()
	world.name = "World"
	viewport.add_child(world)

	# AAA Polish Roadmap Phase 1: HDR Bloom. Added as code (like the rest of
	# this function) rather than hand-edited into main.tscn - a malformed
	# .tscn edit risks the whole scene failing to load, while a WorldEnvironment
	# built here is just another node in the same programmatic setup this
	# function already does. Lives inside PixelViewport (sibling of `world`)
	# so it only ever affects the battlefield render, never the HUD layer
	# above it. Conservative defaults per the roadmap spec - glow is inert
	# (no visible bloom) on any color that never exceeds 1.0 in a channel,
	# so this is safe by construction even before anything in the game
	# actually pushes HDR-range colors; wiring specific projectile/packet
	# colors above 1.0 to actually trigger it is a separate follow-up.
	var world_env = WorldEnvironment.new()
	world_env.name = "PixelViewportEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	viewport.add_child(world_env)

func _setup_hud():
	hud_canvas = CanvasLayer.new()
	hud_canvas.layer = 5
	
	# Legibility pass (Status.md HUD/UX backlog): these two sit directly over
	# the battlefield with no background panel behind them (unlike the boss
	# health bar / dialogue box below, which both get one) - a black outline
	# keeps the text readable against bright tiles, explosions, and pixel-art
	# terrain instead of washing out to illegible white-on-white.
	wave_label = Label.new()
	wave_label.add_theme_font_size_override("font_size", 32)
	wave_label.add_theme_constant_override("outline_size", 6)
	wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	wave_label.position = Vector2(20, 20)
	hud_canvas.add_child(wave_label)

	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.add_theme_constant_override("outline_size", 5)
	timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	timer_label.position = Vector2(20, 60)
	hud_canvas.add_child(timer_label)
	
	# Simple arrow indicator
	extraction_indicator = Polygon2D.new()
	var pts = PackedVector2Array([Vector2(20, 0), Vector2(-20, 15), Vector2(-10, 0), Vector2(-20, -15)])
	extraction_indicator.polygon = pts
	extraction_indicator.color = Color(0.2, 1.0, 0.4)
	extraction_indicator.visible = false
	hud_canvas.add_child(extraction_indicator)

	# Missile Rack HUD element
	missile_charge_bg = ColorRect.new()
	missile_charge_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	missile_charge_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	missile_charge_bg.size = Vector2(20, 200)
	missile_charge_bg.position = Vector2(20, 720 - 200 - 20)
	missile_charge_bg.visible = false
	hud_canvas.add_child(missile_charge_bg)

	missile_charge_fg = ColorRect.new()
	missile_charge_fg.color = Color(1.0, 0.6, 0.1, 1.0) # High contrast orange
	missile_charge_fg.size = Vector2(16, 196)
	missile_charge_fg.position = Vector2(2, 2)
	missile_charge_bg.add_child(missile_charge_fg)

	# Boss UI
	var b_width = 400
	var b_height = 30
	var b_margin = 16
	boss_health_bar_bg = ColorRect.new()
	boss_health_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	boss_health_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss_health_bar_bg.position = Vector2((1280 - b_width) / 2, 720 - b_height - b_margin)
	boss_health_bar_bg.size = Vector2(b_width, b_height)
	boss_health_bar_bg.visible = false
	hud_canvas.add_child(boss_health_bar_bg)
	
	boss_health_bar_fg = ColorRect.new()
	boss_health_bar_fg.color = Color(0.8, 0.1, 0.1, 1.0)
	boss_health_bar_fg.position = Vector2(2, 2)
	boss_health_bar_fg.size = Vector2(b_width - 4, b_height - 4)
	boss_health_bar_bg.add_child(boss_health_bar_fg)
	
	boss_health_label = Label.new()
	boss_health_label.add_theme_font_size_override("font_size", 24)
	boss_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_health_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_health_bar_bg.add_child(boss_health_label)

	# Dialogue UI
	dialogue_box = Panel.new()
	# Centered purely via anchor offsets, not a one-time get_viewport() read
	# (user report + screenshot: a Shopkeeper line rendered pinned at the far
	# right edge, text running off-screen, on a maximized wide window). The
	# previous fix already diagnosed a hardcoded-offset version of this same
	# bug, but its own replacement still manually computed dialogue_box.position
	# from get_viewport().get_visible_rect().size.x BEFORE hud_canvas (this
	# node's real parent) was actually added to the tree a few lines below -
	# anchor-relative offset math has no real, correctly-sized parent rect to
	# compute against yet at that point, so the resulting position was
	# unreliable. Symmetric offsets around a center anchor need no viewport
	# query at all and stay correct on any window size, including a later
	# resize, since Godot recomputes them from the anchor every time the
	# parent rect changes - no one-time calculation to go stale.
	dialogue_box.anchor_left = 0.5
	dialogue_box.anchor_right = 0.5
	dialogue_box.anchor_top = 0.0
	dialogue_box.anchor_bottom = 0.0
	dialogue_box.offset_left = -400
	dialogue_box.offset_right = 400
	dialogue_box.offset_top = 100
	dialogue_box.offset_bottom = 220
	dialogue_box.visible = false
	# ALWAYS, not the HUD's default PAUSABLE - the 3-loss game-over line
	# ("I have to pull your tournament registration...") shows while the
	# tree is paused for the death-triggered Garage reopen, and a PAUSABLE
	# dialogue is completely input-frozen there: the RichTextLabel's own
	# scrollbar exists but never responds ("cannot scroll in the death
	# window").
	dialogue_box.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_canvas.add_child(dialogue_box)

	dialogue_label = RichTextLabel.new()
	dialogue_label.bbcode_enabled = true
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue_label.offset_left = 16
	dialogue_label.offset_top = 16
	dialogue_label.offset_right = -16
	dialogue_label.offset_bottom = -16
	dialogue_label.add_theme_font_size_override("normal_font_size", 20)
	dialogue_label.add_theme_font_size_override("bold_font_size", 22)
	dialogue_box.add_child(dialogue_label)

	add_child(hud_canvas)
	_update_hud()

func show_dialogue(speaker: String, text: String, color: Color = Color(1.0, 0.85, 0.2), duration: float = 6.0):
	if text == "": return
	dialogue_box.visible = true
	# Long monologues (rival intros, the 3-loss game-over speech) overflow
	# the fixed 120px box with most of the text unreachable - grow the box
	# with the content up to a cap; past the cap the RichTextLabel's own
	# scrollbar takes over (and actually works now, see the ALWAYS
	# process_mode in _setup_hud).
	var estimated_lines = ceil(text.length() / 70.0) + 1.0
	dialogue_box.size.y = clamp(60.0 + estimated_lines * 28.0, 120.0, 320.0)
	var hex_color = color.to_html(false)
	dialogue_label.text = "[b][color=#%s]%s[/color][/b]\n%s" % [hex_color, speaker, text]
	dialogue_timer = duration

# Continuously re-evaluated (not a timer) - the player is Blind exactly
# while standing inside a hostile JammerField's live boundary, and un-blind
# the instant they leave or its owner dies. The jammer_field scan itself
# stays unconditional every frame (that group is small, 1-3 active fields
# at once, and needs the real-time boundary check), but the "enemy" group -
# up to 80 members - only gets its .visible toggled on an actual blind-state
# TRANSITION, not every single frame regardless of change. This was walking
# and writing .visible on the whole enemy roster 60x/sec even while nothing
# changed - a genuine per-frame O(enemy count) cost for a state that only
# actually flips a few times per encounter. Since this loop no longer runs
# every frame, a freshly-spawned enemy while the player is ALREADY blind
# (no transition to trigger this loop) needs its own one-time correction at
# spawn time instead - see SquadDirector._spawn_bot_for_role's visibility
# sync right after add_child(bot).
var _was_player_blind: bool = false

func _update_player_blind_state():
	if not player or not is_instance_valid(player):
		return
	var blind = false
	# Corporate Sponsorships: Keeneye Sensing's Counter-Jammer tile - see
	# SensorTile.gd's header.
	if not player.get("has_jammer_immunity"):
		for f in EntityCache.get_group("jammer_field"):
			if is_instance_valid(f) and not f.owner_is_player and f.is_point_inside(player.global_position):
				blind = true
				f.report_jam_contact(player.global_position)
				break
	player_is_blind = blind
	if blind == _was_player_blind:
		return
	_was_player_blind = blind
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.visible = not blind

func _update_hud():
	if wave_label:
		wave_label.text = "Wave: " + str(current_wave) + "  |  Lives: " + str(player_lives_remaining)
	if timer_label:
		if garage_timer > 0:
			timer_label.text = "Extraction in: " + str(int(garage_timer)) + "s"
			timer_label.modulate = Color.WHITE
		else:
			timer_label.text = "Extraction Ready! Follow indicator."
			timer_label.modulate = Color(0.2, 1.0, 0.4)
	
	if player and is_instance_valid(player):
		var max_charge = 0.0
		var current = 0.0
		for data in player.precalculated_weapons:
			if data.mount and data.mount.tile_type == "Missile Rack":
				if data.packet.charge_required > max_charge:
					max_charge = data.packet.charge_required
					current = data.mount.current_charge
		if max_charge > 0.0:
			missile_charge_bg.visible = true
			var ratio = clamp(current / max_charge, 0.0, 1.0)
			missile_charge_fg.size.y = 196.0 * ratio
			missile_charge_fg.position.y = 2 + 196.0 * (1.0 - ratio)
		else:
			missile_charge_bg.visible = false


func _process(delta: float):
	# Live-combat batch pool target sync (2026-08-11 cutover) - only when
	# the setting's actually on, so this costs nothing for the vast
	# majority of players who never touch the toggle. See
	# ProjectileBatchPool.sync_targets_from_groups()'s own header for why
	# this pulls fresh from EntityCache every frame instead of manual
	# register/unregister bookkeeping.
	if ProjectileManager.should_use_batch_pool():
		_live_batch_pool.sync_targets_from_groups()

	if SaveManager.current_game_mode == "campaign":
		_map_rotation_elapsed += delta

	if garage_timer > 0:
		garage_timer -= delta
		_update_hud()
		if garage_timer <= 0:
			_spawn_extraction_marker()
			_update_hud()

	# Self-heal a wedged _spawning_wave without waiting for the player to
	# cycle Garage - see the watchdog comment on _start_wave()'s re-entrancy
	# guard above for why this can get stuck. A stuck player standing on an
	# empty battlefield with no enemies left to fight may not think to walk
	# all the way back to the extraction marker just to retry - recover on
	# our own instead. Self-limiting: _start_wave() sets _spawning_wave (and
	# its timestamp) true again almost immediately, so this can't refire
	# faster than once per stuck 10s window.
	if _spawning_wave and Time.get_ticks_msec() - _spawning_wave_started_at >= 10000:
		push_warning("[Main] _spawning_wave wedged for 10s+ (wave %d, active_enemies %d) - self-healing without a Garage cycle" % [current_wave, active_enemies])
		_spawning_wave = false
		_clear_stale_wave_enemies()
		_start_wave()

	# Separate self-heal for a DIFFERENT failure mode (user report 2026-08-05,
	# wave 73, an all-water map: _spawning_wave false, active_enemies stuck
	# at 1, but the F3 overlay's live EntityCache "enemy" group count already
	# read 0 - a real bookkeeping drift, not a spawn-loop stall the watchdog
	# above covers. Exact trigger unconfirmed (a flee/wild-bot credit-back
	# edge case and a water-related death path are both plausible, but
	# neither was pinned down with certainty) - rather than guess at the one
	# true cause, reconcile against reality directly: if there are truly no
	# live enemies left but active_enemies hasn't caught up, something's
	# wedged regardless of why, and no future kill is ever coming to fix it.
	# 3s grace (not instant) so this can't misfire on the ordinary one-frame
	# gap between a real kill and its node actually leaving the group.
	if not _spawning_wave and active_enemies > 0:
		if EntityCache.get_group("enemy").is_empty():
			_active_enemies_drift_timer += delta
			if _active_enemies_drift_timer >= 3.0:
				push_warning("[Main] active_enemies stuck at %d with 0 live enemies (wave %d) - resyncing" % [active_enemies, current_wave])
				active_enemies = 0
				_active_enemies_drift_timer = 0.0
				_on_wave_cleared()
		else:
			_active_enemies_drift_timer = 0.0
	else:
		_active_enemies_drift_timer = 0.0

	if is_instance_valid(extraction_marker) and extraction_indicator and player:
		extraction_indicator.visible = true
		var viewport_rect = get_viewport_rect()
		var center = viewport_rect.size / 2.0
		var dir = (extraction_marker.global_position - player.global_position).normalized()
		extraction_indicator.position = center + dir * (min(viewport_rect.size.x, viewport_rect.size.y) / 2.0 - 50)
		extraction_indicator.rotation = dir.angle()
	elif extraction_indicator:
		extraction_indicator.visible = false

	if not _drone_respawn_timers.is_empty():
		var ready_bays = []
		for bay_id in _drone_respawn_timers.keys():
			_drone_respawn_timers[bay_id] -= delta
			if _drone_respawn_timers[bay_id] <= 0.0:
				ready_bays.append(bay_id)
		for bay_id in ready_bays:
			_drone_respawn_timers.erase(bay_id)
		if not ready_bays.is_empty():
			_spawn_drones_if_needed()

	if dialogue_timer > 0:
		dialogue_timer -= delta
		if dialogue_timer <= 0:
			dialogue_box.visible = false

	_update_player_blind_state()

# Spawns a companion Drone for every Drone Bay tile installed anywhere in
# ANY of the player's equipped components (not just the Backpack - nothing
# actually restricts where a Drone Bay can be placed, see DroneBayTile.
# find_all_in_mech) that doesn't already have a live drone and isn't on
# respawn cooldown - called on every deploy (_close_garage) and again
# whenever an individual bay's respawn cooldown elapses following a
# mid-combat drone death (see _on_drone_died).
func _spawn_drones_if_needed():
	if not player:
		return
	var bays = DroneBayTile.find_all_in_mech(player.components)
	for i in range(bays.size()):
		var drone_bay = bays[i]
		var bay_id = drone_bay.get_instance_id()
		if drone_nodes.has(bay_id) and is_instance_valid(drone_nodes[bay_id]):
			continue
		if _drone_respawn_timers.has(bay_id):
			continue

		var drone = load("res://scripts/entities/Drone.gd").new()
		var loadout = drone_bay.get_or_build_loadout() # also assigns visual_class if unset - must run before reading it below
		drone.setup(player, loadout, drone_bay.rarity, drone_bay.visual_class)
		# Spread multiple drones' starting positions out (and their
		# _orbit_angle, randomized independently in Drone.gd's setup) so a
		# multi-bay build doesn't spawn every drone stacked on the same point.
		var spread_angle = (TAU / max(1, bays.size())) * i
		drone.global_position = player.global_position + Vector2(cos(spread_angle), sin(spread_angle)) * 70.0
		drone.drone_died.connect(_on_drone_died.bind(bay_id))
		world.add_child(drone)
		drone_nodes[bay_id] = drone

func _on_drone_died(_rarity: int, bay_id: int):
	drone_nodes.erase(bay_id)
	_drone_respawn_timers[bay_id] = DRONE_RESPAWN_DELAY

# Garage state is a hard reset point for the drones same as everything else
# about the run (see _open_garage's full-heal) - simpler and more robust than
# trying to keep live drones correctly paused/hidden through the Garage UI.
# Fresh ones spawn right back on deploy (_close_garage).
func _despawn_all_drones():
	for bay_id in drone_nodes.keys():
		if is_instance_valid(drone_nodes[bay_id]):
			drone_nodes[bay_id].queue_free()
	drone_nodes.clear()
	_drone_respawn_timers.clear()

func _spawn_extraction_marker():
	var marker_class = load("res://scripts/entities/ExtractionMarker.gd")
	if marker_class:
		extraction_marker = marker_class.new()
		var offset = Vector2(randf_range(600, 1500), randf_range(600, 1500))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1

		if player:
			var target_pos = player.global_position + offset
			# Hard-clamp inside the walls BEFORE the valid-position search -
			# same fix as _spawn_wave_async's identical hazard. A player
			# standing anywhere near a map edge could otherwise push this
			# random 600-1500px offset genuinely off the map, and
			# get_valid_spawn_position's spiral search (which used to
			# collapse to nothing from an already-out-of-bounds origin)
			# would hand the marker right back there - "Follow indicator"
			# then leads the player off the map, with chasing enemies in
			# tow (the actual source of the "enemies off map" report).
			if map:
				var inset = 96.0
				var map_w = map.width * map.tile_size
				var map_h = map.height * map.tile_size
				target_pos.x = clamp(target_pos.x, inset, map_w - inset)
				target_pos.y = clamp(target_pos.y, inset, map_h - inset)
				target_pos = map.get_valid_spawn_position(target_pos)
			extraction_marker.global_position = target_pos
		world.add_child(extraction_marker)


# Esc/ui_cancel handling moved to GlobalPauseHandler.gd (added in _ready())
# - it needs to work whether or not the tree is paused, which this
# function couldn't do since Main itself isn't PROCESS_MODE_ALWAYS.

func _load_campaign():
	var file = FileAccess.open("res://config/campaign.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var json = JSON.new()
		if json.parse(text) == OK:
			campaign_data = json.data

func _setup_environment():
	map = MapGenerator.new()
	# Long-term every biome here becomes a themed tabletop mat (grass mat,
	# tundra mat...) rather than "terrain".
	var pool = _water_eligible_map_types()
	map.map_type = pool[randi() % pool.size()]
	map.name = "GameMap"
	world.add_child(map)

# Per the user: "the water map should be pushed later since default player
# builds don't include jumpjets yet (and jumpjets should be provided to the
# player prior to a water level)" - a mech with no jumpjets equipped drowns
# on contact with water (Mech._check_drowning/_has_jumpjets), and nothing in
# the starter inventory/auto-equip/demo-build path guarantees a Jumpjet tile
# actually ends up EQUIPPED (as opposed to just sitting unplaced in
# inventory) by the time a Water map could be rolled. Excludes "Water" from
# the pool unless `player` exists AND its live _has_jumpjets() check passes
# - reuses the mech's own real drowning-check logic rather than duplicating
# it. `player` is still null when this is called from _setup_environment()
# (which runs before _setup_player() in _ready()), so the very first map of
# any run naturally falls through to "no Water" too - exactly the "pushed
# later" the user asked for, with no separate first-map special case needed.
func _water_eligible_map_types() -> Array:
	if player and player.has_method("_has_jumpjets") and player._has_jumpjets():
		return MAP_ROTATION_TYPES
	return MAP_ROTATION_TYPES.filter(func(t): return t != "Water")

func _setup_live_batch_pool():
	_live_batch_pool = ProjectileBatchPoolScript.new()
	_live_batch_pool.name = "LiveProjectileBatchPool"
	world.add_child(_live_batch_pool)
	ProjectileManager.live_batch_pool = _live_batch_pool

func _setup_player():
	player = Mech.new()
	player.is_player = true
	player.name = "PlayerMech"
	
	# Player is Layer 4 (bit 3). 
	player.collision_layer = 8
	player.collision_mask = 1 | 2 | 4 | 32 # environment, water, enemies, obstacles
	
	player.global_position = map.get_valid_spawn_position(Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0))

	world.add_child(player)
	player.add_to_group("player")
	player.died.connect(_on_player_died)

	if SaveManager.save_to_load != "":
		var load_data = SaveManager.load_game(SaveManager.save_to_load)
		if load_data.has("components") and not load_data["components"].is_empty():
			for slot in player.components.keys():
				player.components[slot].queue_free()
			player.components.clear()
			for slot in load_data["components"].keys():
				player.equip_component(load_data["components"][slot])
				
		if load_data.has("inventory"):
			player_inventory = load_data["inventory"]
		if load_data.has("component_inventory"):
			player_component_inventory = load_data["component_inventory"]
		if load_data.has("scrap"):
			player_scrap = load_data["scrap"]
		if load_data.has("modifier_chips"):
			player_modifier_chips = load_data["modifier_chips"]
		# Resume the RUN, not just the gear - the wave counter was never in
		# the save format (play report: "game save is still not saving
		# wave"), so every load silently restarted at wave 1.
		if load_data.has("current_wave"):
			current_wave = max(1, int(load_data["current_wave"]))
			last_garage_wave = current_wave
		# Tournament is its own circuit, not a continuation of the
		# campaign's wave count - a save picked from TournamentMenu is
		# guaranteed max_wave_reached >= 100, so without this the bracket
		# dispatch below would see current_wave already deep past the
		# whole bracket's length and skip straight to Endless Mega
		# Bosses, never fighting a single bracket match.
		if SaveManager.current_game_mode == "tournament":
			current_wave = 1
			last_garage_wave = current_wave
		if load_data.has("player_sponsorship"):
			player_sponsorship = str(load_data["player_sponsorship"])
		if load_data.has("player_paint_color"):
			player_paint_color = str(load_data["player_paint_color"])
	else:

		_initialize_starter_inventory()

	# Roll a hero paint color if this run doesn't have one yet - either a
	# brand-new game, or a save file from before this feature existed.
	if player_paint_color == "":
		player_paint_color = PLAYER_PAINT_PALETTE.pick_random().to_html(false)
	player.paint_color = Color(player_paint_color)
	player.refresh_visuals()

	var camera = Camera2D.new()
	camera.set_script(load("res://scripts/core/CameraShake.gd"))
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	# Camera2D.zoom is relative to the viewport it's actually rendering
	# into, not the window - since that's now the small internal
	# PixelViewport (container_size / PIXEL_SHRINK_FACTOR), the old zoom of
	# 1.5 (tuned for native rendering) made the camera capture 1/Nth the
	# world area it used to, which is why everything rendered N times too
	# big AND paradoxically too smooth (more internal pixels ended up spent
	# per mech than intended). Dividing by the shrink factor here keeps the
	# on-screen framing where it was while still getting the low-res pass.
	camera.zoom = Vector2(1.5, 1.5) / PIXEL_SHRINK_FACTOR
	camera.set("base_zoom", 1.5 / PIXEL_SHRINK_FACTOR) # CameraShake owns zoom from here
	camera.add_to_group("camera")
	player.add_child(camera)
	
	# Pre-calculate weapons so the first shot doesn't freeze the game
	player._recalculate_grid()

## Starter inventory curve (Status.md "God-Class Aftercare"-adjacent backlog
## item, tuned 2026-07-16): the original grant was 20 debug-leftover
## Legendary Splitters stacked on top of an already-generous full COMMON-
## through-LEGENDARY spread of every core tile - a fresh save started with
## more high-rarity routing tiles than LootManager's DROP_RATES (2% for
## LEGENDARY, wave-scaled ~0.5-8% for MYTHIC) intend a player to see for
## many waves of actual play. Replaced with a real taper: COMMON-heavy,
## a taste of UNCOMMON/RARE, and zero free LEGENDARY/MYTHIC - those stay
## something the loot economy and Garage Market actually have to earn.
## New players still get a full working demo build separately (see
## GarageMenu.gd's _apply_demo_build) - this loose inventory is spare
## crafting/customization material on top of that, not the only path to
## a functioning mech.
func _initialize_starter_inventory():
	player_inventory.clear()
	player_component_inventory.clear()

	var taper = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE]
	var taper_counts = {HexTile.Rarity.COMMON: 5, HexTile.Rarity.UNCOMMON: 3, HexTile.Rarity.RARE: 1}
	var classes = [
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/AmplifierTile.gd")
	]

	# Splitter, Reflector, Amplifier: 5 Common / 3 Uncommon / 1 Rare each
	for r in taper:
		for c in classes:
			for i in range(taper_counts[r]):
				var tile = c.new()
				tile.rarity = r
				player_inventory.append(tile)

	# Magnets and Shields: 3 Common / 2 Uncommon / 1 Rare each
	var defense_counts = {HexTile.Rarity.COMMON: 3, HexTile.Rarity.UNCOMMON: 2, HexTile.Rarity.RARE: 1}
	for r in taper:
		for i in range(defense_counts[r]):
			var tile = load("res://scripts/tiles/MagnetTile.gd").new()
			tile.rarity = r
			player_inventory.append(tile)

			var shield = load("res://scripts/tiles/ShieldTile.gd").new()
			shield.rarity = r
			player_inventory.append(shield)

	# Add Infusers (enum values, not magic ints - the old literal `3` here
	# was commented POISON but is actually LIGHTNING in SynergyType order,
	# so the starter "poison" infuser had been infusing lightning)
	var poison_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	poison_infuser.rarity = HexTile.Rarity.UNCOMMON
	poison_infuser.secondary_synergy = EnergyPacket.SynergyType.POISON
	player_inventory.append(poison_infuser)

	var fire_infuser = load("res://scripts/tiles/InfuserTile.gd").new()
	fire_infuser.rarity = HexTile.Rarity.UNCOMMON
	fire_infuser.secondary_synergy = EnergyPacket.SynergyType.FIRE
	player_inventory.append(fire_infuser)

	# Add Catalyst - Rare, not Legendary; a starter taste, not a free BiS tile
	var starter_cat = load("res://scripts/tiles/CatalystTile.gd").new()
	starter_cat.rarity = HexTile.Rarity.RARE
	player_inventory.append(starter_cat)

	# Add Jumpjets for Water Traversal - functional necessity, not a power
	# spike, so this stays as-is rather than tapering down further.
	for i in range(2):
		var jj = load("res://scripts/tiles/JumpjetTile.gd").new()
		jj.rarity = HexTile.Rarity.UNCOMMON
		player_inventory.append(jj)

	# Mark every starter tile type as already-discovered, silently - a brand
	# new player shouldn't get hit with a wall of "new tile!" cards before
	# they've even opened the garage (see TileDiscoveryPopup.gd).
	for tile in player_inventory:
		SaveManager.note_tile_discovered(tile.tile_type)

func _start_intermission():
	show_dialogue("Shopkeeper", DialogueManager.get_intermission_quip(), Color(0.7, 0.85, 1.0), 5.0)
	_show_countdown()

func _show_countdown():
	print("--- Wave ", current_wave, " starting in 5 seconds! ---")
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.timeout.connect(_start_wave)
	add_child(timer)
	timer.start()

# Real root cause of the wave-65/76 stuck-and-then-corrupted reports found
# 2026-08-05 from the user's actual console output (LootManager.gd:94 was
# calling Node.get() with a default-value 2nd argument - only Dictionary.get
# supports that; Object.get() takes exactly 1 arg and throws - now fixed).
# The watchdog below still earns its keep as a second line of defense: if a
# wave's spawn ever wedges again for any other reason, forcing a bare
# _start_wave() retry without this cleanup left the PREVIOUS wave's still-
# alive mechs wandering the map with died still connected to
# _on_enemy_died - their eventual deaths then decremented the NEW wave's
# freshly-reset active_enemies counter for a wave they were never part of,
# observed dragging it to -24 by wave 76. Mirrors the same "Clear all
# active enemies" pattern _on_player_died's Garage-kick-back already uses
# a few hundred lines below.
func _clear_stale_wave_enemies():
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		# Disconnect every died listener, not just _on_enemy_died - bosses/
		# rivals/champions route through their own handler (_on_boss_died etc.)
		# which itself calls _on_enemy_died() internally, so any of them left
		# connected would still decrement the fresh counter below if a
		# same-frame hit resolves before this queue_free() actually takes
		# effect at end of frame. Same "walk the real connections" approach
		# SquadDirector._merge_squads uses for dealt_damage/took_damage.
		for conn in enemy.died.get_connections():
			enemy.died.disconnect(conn.callable)
		enemy.queue_free()
	active_enemies = 0

func _start_wave():
	# Re-entrancy guard (user report 2026-08-05: stuck on wave 65, killing
	# everything spawned after a Garage visit never advanced it). Extraction
	# is player-voluntary and NOT gated on the current wave having cleared -
	# garage_timer counts down independent of active_enemies (_process
	# above), so walking into the ExtractionMarker and redeploying can
	# re-trigger this function while a PREVIOUS call's _spawn_wave_async is
	# still mid-flight (staggered one squad per 0.12s beat - real wall-clock
	# time this function is not done spawning for). A second concurrent
	# call would reset active_enemies to 0, re-run the boss/rival dispatch,
	# and race the first call's still-running loop over the same
	# active_enemies/_spawning_wave state with no mutual exclusion at all.
	#
	# WATCHDOG (added same day, after the plain guard above shipped as
	# v1.1.7.5 and the user was STILL stuck - F3 overlay then showed
	# active_enemies 0, spawning true, permanently): _spawning_wave is
	# supposed to always clear on its own once _spawn_wave_async reaches its
	# own end, but if that coroutine hits a runtime script error partway
	# through its awaited chain (director.spawn_squad -> _assemble_squad),
	# GDScript has no unwind/finally - execution just halts there and the
	# flag never clears, wedging the plain guard above shut forever. Rather
	# than trust that _spawn_wave_async always reaches its reset line, treat
	# a flag that's been true too long as proof it didn't: recover instead
	# of trusting it. 10s is generous headroom over the ~2-3s a legitimate
	# 50-squad-max, 0.12s-per-beat spawn should ever take.
	if _spawning_wave:
		# Watchdog threshold raised alongside the spawn-pacing change below
		# (see _spawn_wave_async's own comment) - spawning a full wave now
		# legitimately takes up to ~garage_timer's own duration (spread
		# across it, not a 2-3s burst), so the old 10s "must be stuck"
		# assumption would false-positive on every normal wave. Generous
		# headroom over WAVE_SPAWN_SPREAD_SECONDS + the safety margin.
		if Time.get_ticks_msec() - _spawning_wave_started_at < int((WAVE_SPAWN_SPREAD_SECONDS + 20.0) * 1000.0):
			return
		push_warning("[Main] _spawning_wave was stuck true for %ds+ (wave %d) - forcing recovery" % [int(WAVE_SPAWN_SPREAD_SECONDS + 20.0), current_wave])
		_spawning_wave = false
		_clear_stale_wave_enemies()
	_update_hud()
	print("--- WAVE ", current_wave, " COMMENCING ---")
	LootManager.current_wave = current_wave
	_wave_guaranteed_mythic_used = false
	# Reactive music: combat loop (faster arps + drums) for the wave.
	AudioManager.set_combat_state(true)

	# Spawn Squad Director if it doesn't exist
	var director = world.get_node_or_null("SquadDirector")
	if not director:
		director = load("res://scripts/ai/SquadDirector.gd").new()
		director.name = "SquadDirector"
		world.add_child(director)
		
		# New Diverse Templates
		var t_sniper = load("res://scripts/ai/SquadTemplate.gd").new("Sniper Team", {"sniper": 2, "brawler": 1})
		director.register_template(t_sniper)
		
		var t_recon = load("res://scripts/ai/SquadTemplate.gd").new("Recon", {"scout": 3})
		t_recon.spawn_weight = 120.0
		director.register_template(t_recon)
		
		var t_assault = load("res://scripts/ai/SquadTemplate.gd").new("Assault", {"brawler": 2, "flamethrower": 1})
		t_assault.has_shields = true
		director.register_template(t_assault)
		
		var t_ambush = load("res://scripts/ai/SquadTemplate.gd").new("Ambushers", {"ambusher": 3})
		director.register_template(t_ambush)
		
		var t_jammer = load("res://scripts/ai/SquadTemplate.gd").new("Jammer Escort", {"jammer": 1, "brawler": 2, "sniper": 1})
		t_jammer.has_shields = true
		t_jammer.spawn_weight = 80.0
		director.register_template(t_jammer)

		var t_support = load("res://scripts/ai/SquadTemplate.gd").new("Support Detachment", {"support": 1, "brawler": 2})
		t_support.spawn_weight = 70.0
		director.register_template(t_support)

		# Per the user: "make sure the commanders have enough support to be
		# able to make a difference in a pitched battle" - a Command Escort
		# used to ship with zero healing/jamming/execute-immunity backup at
		# all (just brawler/sniper muscle). A dedicated support slot means
		# every Commander encounter now has real backline sustain.
		# anti_missile added here too (not just Flak Screen below): the
		# Commander is the squad's single highest-value target and now
		# carries a Missile Rack of its own (Mech.build_loadout_for_role) -
		# worth a dedicated point-defense escort on top of its existing
		# support slot.
		var t_command = load("res://scripts/ai/SquadTemplate.gd").new("Command Escort", {"commander": 1, "support": 1, "anti_missile": 1, "brawler": 1, "sniper": 1})
		t_command.has_shields = true
		t_command.spawn_weight = 55.0 # rare-ish: a Commander on the field should feel like an event
		director.register_template(t_command)

		# Support's execute-immunity aura (see SupportMech.gd) is the whole
		# value here - pair it with roles a pierce-execute player would
		# normally love shredding (brawler/ambusher, both squishy-ish
		# melee-range targets) so the counterplay is legible.
		var t_support_escort = load("res://scripts/ai/SquadTemplate.gd").new("Support Escort", {"support": 1, "brawler": 1, "ambusher": 1})
		t_support_escort.spawn_weight = 45.0 # baseline rare-ish; SquadDirector up-weights hard once PIERCE-execution share is detected
		director.register_template(t_support_escort)

		# A second remediation exposure point alongside Hazmat Detail below -
		# a support-flavored squad that keeps its own brawler clear of
		# missile residue rather than pushing through it.
		var t_cleanup_escort = load("res://scripts/ai/SquadTemplate.gd").new("Cleanup Escort", {"support": 1, "remediation": 1, "brawler": 1})
		t_cleanup_escort.spawn_weight = 40.0
		director.register_template(t_cleanup_escort)

		# Divers flank through water other roles have to route around -
		# paired with a scout for the same "hit-and-fade" playstyle rather
		# than a tanky escort, since the whole point is terrain, not brawn.
		var t_recon_amphib = load("res://scripts/ai/SquadTemplate.gd").new("Amphibious Recon", {"diver": 2, "scout": 1})
		t_recon_amphib.spawn_weight = 60.0
		director.register_template(t_recon_amphib)

		# anti_missile/remediation are kept out of SquadTemplateMutator.
		# ALL_ROLES (same precedent as "diver" - see that role's own comment
		# above) so they don't dilute the generic role-mutation pool; they
		# enter play only via explicit seed templates instead, same as
		# Amphibious Recon does for diver - these two are their dedicated
		# showcases, Command Escort and Cleanup Escort above are additional
		# exposure points.
		var t_flak_screen = load("res://scripts/ai/SquadTemplate.gd").new("Flak Screen", {"anti_missile": 1, "sniper": 2})
		t_flak_screen.spawn_weight = 50.0
		director.register_template(t_flak_screen)

		var t_hazmat_detail = load("res://scripts/ai/SquadTemplate.gd").new("Hazmat Detail", {"remediation": 1, "brawler": 2})
		t_hazmat_detail.spawn_weight = 50.0
		director.register_template(t_hazmat_detail)

		# Restore learned weights/fitness onto the defaults just registered,
		# plus any evolved compositions and solver profiles from previous
		# sessions. Must run AFTER the defaults exist so the merge-by-name
		# updates them in place instead of duplicating them.
		director.load_learned_state()

	# Director tells (see SquadDirector.get_intel_line): Frank tips the player
	# off when the learning loop is genuinely reacting to them. Skipped in
	# Boss Rush and Tournament, which run their own intro dialogue on the
	# same channel.
	director.note_wave_started()
	if SaveManager.current_game_mode != "boss_rush" and SaveManager.current_game_mode != "tournament":
		var intel = director.get_intel_line(current_wave)
		if intel != "":
			show_dialogue("Frank", intel, Color(0.7, 0.9, 1.0), 6.0)

	# Periodically let the director try out a new experimental squad
	# composition (mutation or fresh random template). Not every wave, so
	# each trial gets a few waves to actually accumulate deployments before
	# the next one shows up. Was every 2 waves - widened to 3 so each new
	# template identity (a fresh StockBuildEvolution/AutoEquipSolver cache
	# key) gets more real playtime before the roster potentially churns
	# again, favoring reuse of what's already registered over constantly
	# minting new ones.
	if current_wave % 3 == 0:
		director.maybe_introduce_experimental_template()
	if current_wave % 3 == 0:
		director.maybe_introduce_experimental_profile()
	if current_wave % 4 == 0:
		director.maybe_introduce_experimental_boss_profile()

	active_enemies = 0
	
	# Boss Rush Mode Logic
	if SaveManager.current_game_mode == "boss_rush":
		if current_wave <= 15:
			# Sequence the 15 Regulars at Mythic tier. Was indexing
			# director.all_rival_profiles.keys() directly, which silently
			# broke once RivalProfilesFactory grew the Elite Four + Frank
			# into that same dictionary (dictionary order put Hrothgar at
			# index 14, i.e. wave 15) - pin explicitly to the Regulars-only
			# list instead so Boss Rush keeps meaning exactly what it always
			# meant, regardless of what else gets added to the roster.
			var r_name = ""
			if current_wave - 1 < SaveManager.REGULAR_RIVAL_NAMES.size():
				r_name = SaveManager.REGULAR_RIVAL_NAMES[current_wave - 1]
			else:
				r_name = director.get_next_rival()
			if current_wave == 1:
				# show_dialogue() doesn't queue - it just overwrites the label -
				# so spawning the rival (which shows its own intro line) in the
				# same call would clobber this banner before it's ever seen.
				# Delay the spawn a few seconds so the gauntlet intro actually
				# gets read first.
				show_dialogue("Shopkeeper", DialogueManager.get_boss_rush_intro(), Color(1.0, 0.7, 0.3), 8.0)
				var intro_timer = Timer.new()
				intro_timer.wait_time = 3.0
				intro_timer.one_shot = true
				intro_timer.timeout.connect(func(): _spawn_rival(director, HexTile.Rarity.MYTHIC, r_name))
				add_child(intro_timer)
				intro_timer.start()
			else:
				_spawn_rival(director, HexTile.Rarity.MYTHIC, r_name)
		else:
			if current_wave == 16:
				# Same clobbering concern as the intro banner above - _spawn_boss
				# can show its own "first boss" dialogue in the rare case a Boss
				# Rush save somehow never triggered it in the campaign proper.
				show_dialogue("Shopkeeper", DialogueManager.get_boss_rush_completion(), Color(1.0, 0.7, 0.3), 8.0)
				var completion_timer = Timer.new()
				completion_timer.wait_time = 3.0
				completion_timer.one_shot = true
				completion_timer.timeout.connect(func(): _spawn_boss(director, true))
				add_child(completion_timer)
				completion_timer.start()
			else:
				# Endless Mega Bosses
				_spawn_boss(director, true)
		return

	# Tournament Mode Logic (the user: "Tournament mode is rounds of fights
	# against the other players and the four champions. The four champions
	# unlock as they are defeated through normal play.") Bracket built once
	# at wave 1, then indexed per-wave; falls to Endless Mega Bosses once
	# exhausted, same shape as Boss Rush above.
	if SaveManager.current_game_mode == "tournament":
		if current_wave == 1 or _tournament_bracket.is_empty():
			_tournament_bracket = SaveManager.REGULAR_RIVAL_NAMES.duplicate()
			for champ_name in SaveManager.ELITE_FOUR_NAMES:
				if SaveManager.defeated_rivals.get(champ_name, false):
					_tournament_bracket.append(champ_name)
			var champs_in_bracket = _tournament_bracket.size() - SaveManager.REGULAR_RIVAL_NAMES.size()
			if champs_in_bracket >= SaveManager.ELITE_FOUR_NAMES.size():
				_tournament_bracket.append("Frank")

		var bracket_index = current_wave - 1
		if bracket_index < _tournament_bracket.size():
			var r_name = _tournament_bracket[bracket_index]
			if current_wave == 1:
				# Same clobbering concern as Boss Rush's own intro banner -
				# delay the spawn so the gauntlet intro actually gets read.
				show_dialogue("Shopkeeper", DialogueManager.get_boss_rush_intro(), Color(1.0, 0.7, 0.3), 8.0)
				var intro_timer = Timer.new()
				intro_timer.wait_time = 3.0
				intro_timer.one_shot = true
				intro_timer.timeout.connect(func(): _spawn_rival(director, HexTile.Rarity.MYTHIC, r_name))
				add_child(intro_timer)
				intro_timer.start()
			elif r_name == "Frank":
				# "No more shopkeeper. No more nice guy behind the counter."
				show_dialogue("Shopkeeper", DialogueManager.get_boss_rush_completion(), Color(1.0, 0.7, 0.3), 8.0)
				var frank_timer = Timer.new()
				frank_timer.wait_time = 3.0
				frank_timer.one_shot = true
				frank_timer.timeout.connect(func(): _spawn_rival(director, HexTile.Rarity.MYTHIC, r_name))
				add_child(frank_timer)
				frank_timer.start()
			else:
				_spawn_rival(director, HexTile.Rarity.MYTHIC, r_name)
		else:
			# Endless Mega Bosses once the bracket's exhausted.
			_spawn_boss(director, true)
		return

	# Nemesis Bounty (every 20 waves) - checked first so it preempts whatever
	# a plain Megaboss/Rival/Boss wave would have been that round. Unlike
	# those, this is a one-off boss built specifically to counter the
	# player's own damage log (see SquadDirector.build_nemesis_profile /
	# _spawn_nemesis below), not a fitness-evolving pool pick.
	if current_wave > 0 and current_wave % NEMESIS_BOUNTY_WAVE_INTERVAL == 0:
		_spawn_nemesis(director)
	# Megaboss Wave Check (Every 25 waves)
	elif current_wave > 0 and current_wave % 25 == 0:
		_spawn_boss(director, true)
	# Rival Challenge (every 10 waves)
	elif current_wave > 0 and current_wave % 10 == 0:
		_spawn_rival(director)
	# Boss Wave Check (Every 5 waves)
	elif current_wave > 0 and current_wave % 5 == 0:
		_spawn_boss(director, false)
	# Traveling Champion (PvP ghost): on ordinary waves, an imported
	# champion sometimes shows up at the shop to challenge you - "counted
	# like any game-shop challenger" per the design ruling. Story-wise it's
	# a visiting player; mechanically it's their exact exported build.
	elif current_wave >= 3 and randf() < 0.12:
		var ghosts = ChampionCardScript.list_ghosts()
		if not ghosts.is_empty():
			_spawn_traveling_champion(ghosts[randi() % ghosts.size()])

	# Difficulty scales how MANY as well as how strong (SquadDirector
	# handles per-bot strength; near-peer stat scaling lives there too).
	var count_mult = SaveManager.DIFFICULTY_COUNT_MULT[SaveManager.difficulty]
	# Map-area density scaling: the Tabletop (64x32) is ~1/50th the default
	# map's area - the same 80-cap there is a mosh pit, not a battle. sqrt
	# keeps small maps busy-but-breathable (Tabletop lands around x0.23).
	var area_ratio = float(map.width * map.height) / float(400 * 250)
	var density_mult = clamp(sqrt(area_ratio), 0.15, 1.0)
	var target_enemy_count = min(80, int((5 + int((current_wave - 1) / 4) * 20) * count_mult * density_mult))
	target_enemy_count = max(3, target_enemy_count)

	# Wave archetype shaping - deliberately narrows which squad templates are
	# eligible on certain waves, so a heavy wave needs far fewer distinct
	# enemy loadouts solved/replayed (complements StockBuildEvolution's
	# per-template build cache: fewer active templates this wave = fewer
	# (template, role) keys in play at once). Independent of the boss/rival/
	# megaboss/champion elif chain above - those are entity spawns, this is
	# squad composition, resolved regardless of which branch above fired.
	# Non-conflicting moduli, most-restrictive checked first.
	var allowed_templates: Array = []
	if current_wave > 0 and current_wave % 7 == 0:
		# "Gang Up": only the templates that have lately been most effective
		# against the player, nothing else.
		allowed_templates = director.top_n_by_recent_effectiveness(3)
	elif current_wave > 0 and current_wave % 4 == 0:
		var role = SquadTemplateMutatorScript.ALL_ROLES[randi() % SquadTemplateMutatorScript.ALL_ROLES.size()]
		for t in director.templates:
			if t.required_roles.has(role):
				allowed_templates.append(t)
	elif current_wave > 0 and current_wave % 3 == 0:
		for t in director.templates:
			if t.required_roles.has("scout"):
				allowed_templates.append(t)

	# Staggered deployment (fire-and-forget async) - see _spawn_wave_async.
	_spawn_wave_async(director, target_enemy_count, allowed_templates)

# True while a wave is still trickling in - guards _on_enemy_died from
# declaring a premature wave-clear when the player kills the first squads
# before the rest have deployed.
var _spawning_wave: bool = false
# Set alongside _spawning_wave = true - lets the watchdog in _start_wave()'s
# guard (and _process()'s self-heal below) tell "still legitimately
# spawning" apart from "stuck forever" without needing to know why it's
# stuck, just how long.
var _spawning_wave_started_at: int = 0
var _wave_spawned_any: bool = false
# How long active_enemies > 0 has read against a truly-empty "enemy" group -
# see _process()'s reconciliation self-heal.
var _active_enemies_drift_timer: float = 0.0

# Spawning a full wave used to happen synchronously: up to ~16 squads x 5
# mechs, each running the grid solver AND baking six pixel-art parts, all
# in one frame - the "game freezes when a wave spawns" hitch. Now ONE
# squad deploys per beat, spreading that cost across frames. It also reads
# better: squads arrive in the central region one handful at a time, like
# minis being set down mid-table rather than marched in from the edges
# (see _pick_spawn_anchor).
# Adaptive inter-squad wait (user: "90 per wave just for spawning, they
# spawn spread out over 90 seconds" - see WAVE_SPAWN_SPREAD_SECONDS' own
# field comment): spreads the REMAINING squads across whatever's left of
# the spread window, recomputed after every squad (not a fixed pre-
# computed total) since real squad sizes vary 3-5, not a fixed count -
# this keeps the pacing accurate rather than drifting off an initial
# estimate. Falls back to the old fast 0.12s anti-freeze beat once
# garage_timer drops into the safety-margin tail, or once there's nothing
# left to spawn, so a wave still finishes promptly rather than idling.
# Pulled out of _spawn_wave_async's loop into its own pure function so it
# can be tested directly without driving the full spawn coroutine.
func _compute_spawn_interval(target_enemy_count: int, wave_start_garage_timer: float) -> float:
	var remaining_enemies = max(0, target_enemy_count - active_enemies)
	if remaining_enemies <= 0 or garage_timer <= WAVE_SPAWN_SAFETY_MARGIN_SECONDS:
		return 0.12
	var elapsed_wave_time = wave_start_garage_timer - garage_timer
	var remaining_spread_time = max(0.0, WAVE_SPAWN_SPREAD_SECONDS - elapsed_wave_time)
	var estimated_remaining_squads = max(1.0, ceil(remaining_enemies / WAVE_SPAWN_AVG_SQUAD_SIZE_ESTIMATE))
	return max(0.12, remaining_spread_time / estimated_remaining_squads)

func _spawn_wave_async(director, target_enemy_count: int, allowed_templates: Array = []) -> void:
	_spawning_wave = true
	_spawning_wave_started_at = Time.get_ticks_msec()
	# Captured once, rather than assuming garage_timer always starts at
	# exactly 90.0 - it's whatever garage_timer actually reads the moment
	# this wave's spawning begins, so elapsed-time math below stays correct
	# even if some other code path changes garage_timer's starting value.
	var wave_start_garage_timer = garage_timer
	var safety_break = 0
	while active_enemies < target_enemy_count and safety_break < 50:
		safety_break += 1
		if not is_instance_valid(director) or not is_instance_valid(player) or not is_inside_tree():
			break

		var squad = await director.spawn_squad(allowed_templates)
		if not squad:
			break

		# Squads enter from the table's edges or from behind large
		# obstacles - not from a fixed ring around the player.
		var center_spawn = _pick_spawn_anchor()
		var inset = 96.0
		var map_w = map.width * map.tile_size
		var map_h = map.height * map.tile_size

		for mech in squad.members:
			var raw_pos = center_spawn + Vector2(randf_range(-200, 200), randf_range(-200, 200))
			# Hard-clamp inside the walls BEFORE the valid-position search:
			# get_valid_spawn_position returns its input unchanged when it
			# can't find a clear tile, which let edge-anchored spawns with
			# unlucky offsets end up outside the map entirely.
			raw_pos.x = clamp(raw_pos.x, inset, map_w - inset)
			raw_pos.y = clamp(raw_pos.y, inset, map_h - inset)
			mech.global_position = map.get_valid_spawn_position(raw_pos)
			mech.target = player
			mech.died.connect(_on_enemy_died)
			mech.collision_layer = 4 # Enemies are Layer 3 (bit 2)
			mech.collision_mask = 1 | 2 | 8 | 32 # Hit env, water, player, obstacles
			active_enemies += 1
			_wave_spawned_any = true

		# Adaptive pacing - see _compute_spawn_interval's own comment.
		var interval = _compute_spawn_interval(target_enemy_count, wave_start_garage_timer)
		await get_tree().create_timer(interval).timeout

	_spawning_wave = false

	# Player killed the whole trickle before deployment finished: that IS
	# a wave clear, not a spawn failure.
	if active_enemies <= 0 and safety_break > 0 and _wave_spawned_any:
		_wave_spawned_any = false
		_on_wave_cleared()
		return
	_wave_spawned_any = false

	if active_enemies <= 0:
		# Fallback if assembly fails entirely
		active_enemies = 3
		var wave_multiplier = SaveManager.wave_hp_multiplier(SaveManager.difficulty, current_wave)
		for i in range(3):
			var m = load("res://scripts/entities/Mech.gd").new()
			m.max_hp = 100.0 * wave_multiplier
			m.hp = m.max_hp
			m.global_position = map.get_valid_spawn_position(Vector2(1600 + i * 50, 1600))
			m.died.connect(_on_enemy_died)
			m.target = player
			world.add_child(m)

# Spawn anchor selection: candidates are points just inside the four
# walls plus points beside big obstacles (cover). Prefers anchors a
# comfortable distance from the player; if everything is close (small
# Tabletop maps), takes the farthest available rather than giving up.
func _pick_spawn_anchor() -> Vector2:
	# Playtest ruling: squads spawn NEAR THE MIDDLE of the map rather than
	# marching in from the table edges - anchors sample the central region
	# (a band around the map middle) plus behind-obstacle ambush points,
	# still keeping a comfortable standoff from the player.
	var map_w = map.width * map.tile_size
	var map_h = map.height * map.tile_size
	var candidates: Array = []

	for i in range(4):
		candidates.append(Vector2(
			randf_range(map_w * 0.25, map_w * 0.75),
			randf_range(map_h * 0.25, map_h * 0.75)
		))

	if map.obstacles.size() > 0:
		var obstacle_keys = map.obstacles.keys()
		for i in range(3):
			var k = obstacle_keys[randi() % obstacle_keys.size()]
			candidates.append(Vector2(k.x * map.tile_size, k.y * map.tile_size) + Vector2(randf_range(-64, 64), randf_range(-64, 64)))

	var comfortable: Array = candidates.filter(func(c): return c.distance_to(player.global_position) > 700.0)
	if comfortable.size() > 0:
		return comfortable[randi() % comfortable.size()]
	var best = candidates[0]
	for c in candidates:
		if c.distance_to(player.global_position) > best.distance_to(player.global_position):
			best = c
	return best

# Bosses used to be a scaled-up Brawler, no exceptions, then a flat const
# array of 6 hand-picked archetypes. Now they're spawned from a BossProfile
# pulled off SquadDirector's evolving, fitness-weighted pool (see
# SquadDirector._register_default_boss_profiles/get_active_boss_profile) -
# the same 6 starting kits, but mutation grows real variety over time
# (different enrage styles, ability combos, even different underlying
# roles), same as squad templates and solver profiles already do.
#
# hp_mult exists because the underlying roles' base_hp varies wildly
# (60-350) for balance reasons that have nothing to do with "is this a
# boss" - it roughly levels every archetype back to a comparable HP band
# (regular ~750, mega ~3750) so difficulty stays comparable across profiles
# while still leaving each one a bit squishier or tankier to match its
# flavor. First-pass numbers, not measured against real playtesting.
func _spawn_boss(director, is_mega: bool):
	var profile = director.get_active_boss_profile()
	# Per the user: once the wave-75 Mythic milestone hits, EVERY boss from
	# then on gets guaranteed Mythic-tier hexes, not just a once-per-wave
	# grunt chance - passed as the rarity FLOOR (p_rarity), same pattern
	# Nemesis Bounties/forced-Mythic rivals already use, so difficulty-
	# scaling/gear-parity inside _spawn_bot_for_role can only push it UP
	# from Mythic (a no-op, already at the ceiling), never override it down.
	var boss_rarity_floor = HexTile.Rarity.MYTHIC if current_wave >= MYTHIC_MILESTONE_START_WAVE else 0
	var boss = director._spawn_bot_for_role(profile.base_role, false, boss_rarity_floor)
	boss.boss_profile = profile
	var hp_mult = profile.hp_mult
	if is_mega:
		boss.scale = Vector2(3.0, 3.0)
		boss.max_hp *= 25.0 * hp_mult
		boss.is_boss = true
		boss.set_meta("boss_drop", "mega")
	else:
		boss.scale = Vector2(2.0, 2.0)
		boss.max_hp *= 5.0 * hp_mult
		boss.is_boss = true
		var backpacks = ["shield", "jetpack", "missile", "drone"]
		boss.set_meta("boss_drop", backpacks.pick_random())

	# Corporate Sponsorships (task #17): every boss from wave 100+ reps a
	# random brand - its kill drops one of that brand's tiles (see
	# LootManager.generate_loot_for_mech), regardless of the player's own
	# sponsorship. This is how an unaligned or differently-sponsored player
	# can still eventually get any brand's gear.
	if current_wave >= 100:
		boss.brand_affiliation = BrandRegistry.random_brand()

	# is_boss/boss_profile are set above, AFTER _spawn_bot_for_role's
	# add_child already triggered _ready() and built the visual once with
	# is_boss still false - so the boss-only silhouette accents (spike-crown,
	# cloak-fin, satellite dish, etc. - see MechRenderer.gd) never showed up
	# without an explicit rebuild here.
	if boss.has_method("refresh_boss_visuals"):
		boss.refresh_boss_visuals()

	boss.hp = boss.max_hp
	_equip_enemy_chips(boss)
	var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
	if randf() > 0.5: offset.x *= -1
	if randf() > 0.5: offset.y *= -1
	var center_spawn = player.global_position + offset

	boss.global_position = map.get_valid_spawn_position(center_spawn)
	boss.target = player
	boss.died.connect(_on_boss_died.bind(boss))
	boss.collision_layer = 4
	boss.collision_mask = 1 | 2 | 8 | 32
	active_enemies += 1
	# NOT world.add_child(boss) - director._spawn_bot_for_role() already
	# parented it under SquadDirector (which itself lives under world), same
	# as every regular squad member. A second add_child here throws "already
	# has a parent" (see the identical fix in _spawn_rival below).

	# One-time "First boss" dialogue pair (STORY_SCRIPT.md) instead of the
	# regular rotating boss_defeats line - see first_boss_encountered's own
	# comment in SaveManager.gd. Tag the boss now so _on_boss_died knows which
	# defeat line to show without re-checking the (by-then-flipped) flag.
	boss.set_meta("is_first_boss", not SaveManager.first_boss_encountered)
	if not SaveManager.first_boss_encountered:
		show_dialogue("Shopkeeper", DialogueManager.get_first_boss_intro(), Color(1.0, 0.6, 0.2), 8.0)

# Chip Splicing: only Elite Four rivals and bosses carry real equipped Mod
# Chips (called from _spawn_boss/_spawn_rival) - rank-and-file wave enemies
# use a simplified procedural loadout with no real ComponentEquipment/chip
# concept at all, so they never call this and their equipped_chips stays
# empty. Magnitude is meant to feel like real, worthwhile power - these
# enemies should be able to hit hard enough that losing to one, or working
# to beat one, feels like it mattered. Always produces PLAIN (single-trait)
# chips via the 2-arg equip_chip() - this is also what makes "only plain
# chips drop on death" (LootManager.generate_loot_for_mech) trivially
# correct for every enemy that ISN'T a rival/boss: they never get chips at
# all, so the death-drop loop is a no-op for them with no extra gating.
const ENEMY_CHIP_MIN_BONUS = 0.15
const ENEMY_CHIP_MAX_BONUS = 0.35
const ENEMY_CHIP_COUNT_MIN = 1
const ENEMY_CHIP_COUNT_MAX = 3

func _equip_enemy_chips(mech: Node):
	if not "components" in mech or mech.components.is_empty():
		return
	var count = randi_range(ENEMY_CHIP_COUNT_MIN, ENEMY_CHIP_COUNT_MAX)
	var slots = mech.components.keys()
	for i in range(count):
		var stat = ComponentEquipmentScript.CHIP_STAT_POOL.pick_random()
		var value = round((1.0 + randf_range(ENEMY_CHIP_MIN_BONUS, ENEMY_CHIP_MAX_BONUS)) * 100.0) / 100.0
		var shuffled = slots.duplicate()
		shuffled.shuffle()
		for slot in shuffled:
			if mech.components[slot].equip_chip(stat, value):
				break
	mech._recalculate_grid()

func _on_boss_died(boss):
	# Feed the fight's outcome back into the boss profile's fitness (same
	# reinforcement loop as squad templates/solver profiles) BEFORE the
	# fixed loot-drop handling below, since that part is unrelated and
	# shouldn't be gated on the profile existing.
	if "boss_profile" in boss and boss.boss_profile and boss.has_method("get_boss_fitness"):
		var director = world.get_node_or_null("SquadDirector") if world else null
		if director:
			director._on_boss_defeated(boss.boss_profile, boss.get_boss_fitness())

	if boss.get_meta("is_first_boss", false):
		show_dialogue("Shopkeeper", DialogueManager.get_first_boss_defeat(), Color(1.0, 0.6, 0.2), 8.0)
		SaveManager.first_boss_encountered = true
		SaveManager.save_game("autosave", player, player_inventory)
	else:
		show_dialogue("Shopkeeper", DialogueManager.get_boss_defeat(), Color(1.0, 0.6, 0.2), 6.0)

	# NOTE: the actual guaranteed component drop (shield/jetpack/missile/
	# drone backpack, keyed off this same "boss_drop" meta) already happened
	# in Mech.die() via LootManager.generate_loot_for_mech() BEFORE the
	# died signal that triggers this handler fired (see that function's own
	# "LootManager is an autoload singleton... instead of instantiating a
	# throwaway copy" comment - it was migrated to be the one canonical
	# source). This used to ALSO build a second, independent shield/jetpack/
	# missile/drone drop right here from the exact same meta - a confusing
	# duplicate pickup on top of the real one at best, and its tile-scatter
	# neighbor below was actively broken (see tile_data's own note). Removed;
	# the guaranteed scattered-tiles bonus is the one thing this function
	# still uniquely contributes (LootManager only ever rolls drops from the
	# boss's OWN equipped tiles, never fresh random ones).
	var drop_type = boss.get_meta("boss_drop", "shield")

	if drop_type == "mega":
		# Megaboss guaranteed Legendary Drop
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.global_position = boss.global_position

		# Generate a legendary tile
		var legend_tile = _generate_random_tile()
		legend_tile.rarity = HexTile.Rarity.LEGENDARY
		# LootPickup's field is `tile_data`, not `item_data` (no such
		# property exists) - was silently creating pickups that could never
		# actually be collected (neither the equipment_data nor tile_data
		# branch in LootPickup._on_body_entered ever matched).
		pickup.tile_data = legend_tile
		world.add_child(pickup)

	# NEW: Guarantee 3-5 scattered tiles for any Boss
	var drop_rarity = HexTile.Rarity.LEGENDARY if drop_type == "mega" else HexTile.Rarity.RARE
	_scatter_random_tiles(boss.global_position, randi_range(3, 5), drop_rarity)
		
	_on_enemy_died()

func _generate_random_tile() -> HexTile:
	var tile_types = [
		preload("res://scripts/tiles/WeaponMountTile.gd"),
		preload("res://scripts/tiles/AccumulatorTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/CatalystTile.gd"),
		preload("res://scripts/tiles/MagnetTile.gd"),
		preload("res://scripts/tiles/ShieldTile.gd")
	]
	return tile_types.pick_random().new()

func _scatter_random_tiles(origin: Vector2, count: int, rarity: int):
	for i in range(count):
		var tile = _generate_random_tile()
		tile.rarity = rarity
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		# LootPickup's field is `tile_data`, not `item_data` (no such
		# property exists) - was silently spawning pickups that could never
		# actually be collected.
		pickup.tile_data = tile
		pickup.global_position = origin + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		world.call_deferred("add_child", pickup)

# --- Nemesis Bounties --------------------------------------------------------
# "I'm down for you to hit the nemesis bounties" - a one-off, deliberately
# built boss that reads the player's real damage log (SquadDirector.
# player_element_usage/total_damage_taken/dominant_shield_synergy) and
# commits, guaranteed rather than the usual COUNTER_BUILD_CHANCE wobble, to
# countering it: retargeted Microcore output faces PLUS real amplification
# hardware to feed them (see Mech.build_loadout_for_role's is_nemesis branch -
# the user: "the microcores don't have enough output on their own to be a
# threat, they need amplifiers"). Not part of the evolving boss_profiles
# pool - see BossEvolution.build_nemesis_profile's own header comment.
const NEMESIS_BOUNTY_WAVE_INTERVAL = 20
const NEMESIS_HP_FLAT_MULT = 10.0 # between a regular boss's 5.0 and a mega's 25.0 flat factor

func _spawn_nemesis(director):
	var profile = director.build_nemesis_profile()
	# force_full_counter=true is the whole point of a Nemesis - see
	# SquadDirector._spawn_bot_for_role's own comment on that parameter.
	var boss = director._spawn_bot_for_role(profile.base_role, false, HexTile.Rarity.MYTHIC, "", true)
	boss.boss_profile = profile
	boss.is_boss = true
	boss.scale = Vector2(2.5, 2.5)
	boss.max_hp *= NEMESIS_HP_FLAT_MULT * profile.hp_mult
	# Distinct "marked target" tint - no regular boss/rival uses this color,
	# so a Nemesis reads as different on sight, not just on the War Room.
	boss.modulate = Color(0.95, 0.25, 0.5)
	boss.set_meta("boss_drop", "nemesis")

	if current_wave >= 100:
		boss.brand_affiliation = BrandRegistry.random_brand()

	if boss.has_method("refresh_boss_visuals"):
		boss.refresh_boss_visuals()

	boss.hp = boss.max_hp
	_equip_enemy_chips(boss)
	var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
	if randf() > 0.5: offset.x *= -1
	if randf() > 0.5: offset.y *= -1
	var center_spawn = player.global_position + offset

	boss.global_position = map.get_valid_spawn_position(center_spawn)
	boss.target = player
	boss.died.connect(_on_nemesis_died.bind(boss))
	boss.collision_layer = 4
	boss.collision_mask = 1 | 2 | 8 | 32
	active_enemies += 1
	# NOT world.add_child(boss) - same reason as _spawn_boss/_spawn_rival
	# above; director._spawn_bot_for_role() already parented it.

	# Plain mechanical announcement, not invented story text (see
	# get_intel_line's own header comment on why - that channel already fired
	# earlier this same _start_wave() call at line ~930 for the ordinary
	# per-wave Frank tell, so calling it again here would almost always just
	# hit its own repeat-line dedupe and return "").
	var intel = "Nemesis Bounty incoming, '%s' - it's built specifically to counter you." % profile.profile_name
	show_dialogue("Shopkeeper", intel, Color(0.95, 0.25, 0.5), 7.0)

func _on_nemesis_died(boss):
	if "boss_profile" in boss and boss.boss_profile and boss.has_method("get_boss_fitness"):
		var director = world.get_node_or_null("SquadDirector") if world else null
		if director:
			director._on_boss_defeated(boss.boss_profile, boss.get_boss_fitness())

	show_dialogue("Shopkeeper", DialogueManager.get_boss_defeat(), Color(0.95, 0.25, 0.5), 6.0)

	# Nemesis Part: a guaranteed Mythic Elemental Infuser pre-configured to
	# whichever real element (RAW excluded - it's not a build identity) the
	# player has used LEAST, by damage dealt. Deliberate build-diversification
	# incentive, not a random drop - the reward should point at the gap the
	# fight itself was built to expose.
	var director = world.get_node_or_null("SquadDirector") if world else null
	var least_element = EnergyPacket.SynergyType.FIRE
	if director and "player_element_usage" in director:
		var least_ratio = INF
		var total = max(1.0, float(director.total_damage_taken))
		for id in range(EnergyPacket.SynergyType.RAW + 1, EnergyPacket.SynergyType.size()):
			var elem_name = EnergyPacket.element_name(id)
			var used = float(director.player_element_usage.get(elem_name, 0.0)) / total
			if used < least_ratio:
				least_ratio = used
				least_element = id

	var reward = load("res://scripts/tiles/InfuserTile.gd").new()
	reward.rarity = HexTile.Rarity.MYTHIC
	reward.secondary_synergy = least_element
	var pickup = load("res://scripts/entities/LootPickup.gd").new()
	pickup.tile_data = reward
	pickup.global_position = boss.global_position
	world.add_child(pickup)

	_scatter_random_tiles(boss.global_position, randi_range(3, 5), HexTile.Rarity.LEGENDARY)
	_on_enemy_died()

# --- Rival Challenges (FEATURE_ROADMAP.md Story section) --------------------
# "Sometimes another player challenges you - a specialized match where the
# enemy mech is built to counter your play to date, directly or within
# +/-15% of directly." Locked cadence/tolerance per the user: every 10 waves,
# +/-15% of the player's own estimated power (SquadDirector._estimate_mech_power,
# the same yardstick the near-peer difficulty scaling already uses).

func _spawn_rival(director, force_rarity = -1, force_name = ""):
	var rival_rarity = director._player_dominant_rarity() if force_rarity == -1 else force_rarity
	
	var rival_name = force_name
	if rival_name == "":
		rival_name = director.get_next_rival()
		
	var profile: RivalProfile = null
	if director.all_rival_profiles.has(rival_name):
		profile = director.all_rival_profiles[rival_name]
		
	if profile:
		if profile.force_mythic_only:
			rival_rarity = HexTile.Rarity.MYTHIC
		elif profile.force_junk_only:
			rival_rarity = HexTile.Rarity.COMMON

	var role = "brawler"
	var mech_count = 1
	if profile:
		role = profile.base_role
		mech_count = profile.mech_count
		
	for i in range(mech_count):
		var role_to_spawn = role
		if rival_name == "Leo & Luna":
			role_to_spawn = "ambusher" if i == 0 else "sniper"

		var rival = director._spawn_bot_for_role(role_to_spawn, true, rival_rarity)
		rival.set_meta("is_rival", true)
		rival.set_meta("rival_name", rival_name)

		# Equivalent-budget constraint
		var player_power = director._estimate_mech_power(player)
		var rival_power = director._estimate_mech_power(rival)
		var target_power = player_power * randf_range(0.85, 1.15)
		var power_mult = clamp(target_power / max(1.0, rival_power), 0.4, 3.0)

		# If profile overrides HP, multiply
		if profile:
			power_mult *= profile.hp_mult

		rival.max_hp *= power_mult
		rival.hp = rival.max_hp
		if rival.max_shield_hp > 0:
			rival.max_shield_hp *= power_mult
			rival.shield_hp = rival.max_shield_hp
		rival.stat_modifiers["dmg_mult"] = rival.stat_modifiers.get("dmg_mult", 1.0) * power_mult
		_equip_enemy_chips(rival)

		rival.scale = Vector2(1.3, 1.3)
		var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
		if randf() > 0.5: offset.x *= -1
		if randf() > 0.5: offset.y *= -1
		var center_spawn = player.global_position + offset
		rival.global_position = map.get_valid_spawn_position(center_spawn)
		rival.target = player
		rival.died.connect(_on_rival_defeated.bind(rival))
		rival.collision_layer = 4
		rival.collision_mask = 1 | 2 | 8 | 32
		active_enemies += 1
		# NOT world.add_child(rival) - director._spawn_bot_for_role() already
		# parented it under SquadDirector (itself already inside world), same
		# as every regular squad member (Squad.add_member only tracks a
		# reference, never reparents). A second add_child here throws "Can't
		# add child ... already has a parent 'SquadDirector'" - this was a
		# real crash every Rival wave.

		# Chloe's swarm schtick (RivalProfile.drones_have_jammers +
		# drone_swarm_count): she carries a Jammer Module herself, EVERY
		# drone she fields gets one too, and her swarm is topped up to
		# "about twenty micro-bots" with clones of her bay loadout - each
		# projects its own VISION JammerField, and the fields' proximity
		# stacking compounds the cloud into one huge combined blanket.
		if profile and (profile.drones_have_jammers or profile.drone_swarm_count > 0):
			_apply_rival_drone_profile(rival, profile)

		if i == 0:
			if rival.has_method("_show_floating_text"):
				rival._show_floating_text("RIVAL: " + rival_name, Color(1.0, 0.85, 0.2))
			if profile and profile.dialogue_intro != "":
				show_dialogue(rival_name, profile.dialogue_intro, Color(1.0, 0.85, 0.2), 8.0)

# See the drone-schtick block in _spawn_rival above. Drone loadouts are
# SHARED object references between the DroneBayTile and any drone already
# spawned from it (Drone.setup stores and equips the same
# ComponentEquipment instance), so mutating the loadout grid + recalcing
# the live drone updates both the flying unit and any future respawn from
# the same bay in one pass. Swarm top-up drones get their own CLONES (see
# DroneBayTile.spawn_drone_swarm).
func _apply_rival_drone_profile(rival, profile):
	if profile.drones_have_jammers:
		# Her own kit: prefer the backpack (where support modules normally
		# live), fall back to any component with a free hex.
		var own_done = false
		if rival.components.has(HexTile.BodySlot.BACKPACK):
			own_done = JammerModuleTile.ensure_on_component(rival.components[HexTile.BodySlot.BACKPACK])
		if not own_done:
			for slot in rival.components:
				if JammerModuleTile.ensure_on_component(rival.components[slot]):
					break

		# Every drone bay's loadout, wherever it's installed.
		for bay in DroneBayTile.find_all_in_mech(rival.components):
			JammerModuleTile.ensure_on_component(bay.get_or_build_loadout())

	rival._recalculate_grid()
	# Drones for this rival were already spawned inside _spawn_bot_for_role
	# - their equipped component is the same loadout object just modified,
	# so a recalc picks the new jammer up immediately. Count them while
	# we're here so the swarm top-up knows how many are missing.
	var live_drones = 0
	var director = world.get_node_or_null("SquadDirector") if world else null
	if director:
		for child in director.get_children():
			if "drone_loadout_source" in child and child.get("owner_mech") == rival:
				child._recalculate_grid()
				live_drones += 1

	# Megaswarm top-up ("about twenty micro-bots"): clone the first bay's
	# loadout (jammer already ensured above) out to the profile's count.
	if profile.drone_swarm_count > live_drones and director:
		var bays = DroneBayTile.find_all_in_mech(rival.components)
		if not bays.is_empty():
			var bay = bays[0]
			DroneBayTile.spawn_drone_swarm(rival, director, bay.get_or_build_loadout(),
				profile.drone_swarm_count - live_drones, bay.rarity, bay.visual_class)

func _on_rival_defeated(rival):
	# Guaranteed decent-quality drop (matches the "earn merchandise" story
	# beat) - a component built at the same rarity the rival itself fought
	# at, so beating a Rival always feels worth the fight regardless of RNG.
	var rarity = rival.get("base_rarity") if "base_rarity" in rival else HexTile.Rarity.RARE
	
	if rival.has_meta("is_rival") and rival.has_meta("rival_name"):
		var r_name = rival.get_meta("rival_name")
		var director = world.get_node_or_null("SquadDirector")
		# Beating ANY rival breaks the losing streak and restores Tournament
		# eligibility if it had been pulled - see tournament_locked_out's
		# comment in SaveManager.gd. Also records the win for the Elite
		# Four's "unlock as they are defeated through normal play" gate
		# (SquadDirector.get_next_rival) and for the Tournament bracket
		# itself to know which champions this save can field.
		if director:
			director.consecutive_rival_losses = 0
		SaveManager.tournament_locked_out = false
		SaveManager.defeated_rivals[r_name] = true
		if director and director.all_rival_profiles.has(r_name):
			var prof = director.all_rival_profiles[r_name]
			var win_text = prof.dialogue_win
			if win_text == "":
				win_text = DialogueManager.get_generic_rival_win()
			show_dialogue("Shopkeeper", win_text, Color(0.8, 1.0, 0.8), 6.0)

	var drop = load("res://scripts/core/ComponentEquipment.gd").create_starter_backpack("brawler", max(rarity, HexTile.Rarity.RARE))
	if drop:
		var pickup = load("res://scripts/entities/LootPickup.gd").new()
		pickup.equipment_data = drop
		pickup.global_position = rival.global_position
		world.add_child(pickup)
		
	# NEW: Scatter 3-5 tiles
	_scatter_random_tiles(rival.global_position, randi_range(3, 5), rarity)

	_on_enemy_died()

# ---- PvP Traveling Champions (see scripts/pvp/ChampionCard.gd) -----------
# Spawns an imported ghost as a challenger fighting with the EXACT loadout
# it was exported with - no near-peer inflation (the whole point is meeting
# the other player's real build). HP scales from the ghost's OWN build
# power so a strong import is a strong fight and a junk import stays junk.
func _spawn_traveling_champion(ghost: Dictionary):
	var champ = Mech.new()
	champ.is_player = false
	champ.combat_role = "brawler"
	for slot_str in ghost.get("components", {}):
		var comp = SaveManager._deserialize_component(ghost["components"][slot_str])
		if comp:
			champ.equip_component(comp)
	var pilot = str(ghost.get("pilot_name", "Unknown Champion"))
	champ.set_meta("is_ghost", true)
	champ.set_meta("ghost_pilot", pilot)
	champ.set_meta("ghost_id", str(ghost.get("ghost_id", "")))
	champ.target = player
	champ.collision_layer = 4
	champ.collision_mask = 1 | 2 | 8 | 32

	var offset = Vector2(randf_range(500, 1000), randf_range(500, 1000))
	if randf() > 0.5: offset.x *= -1
	if randf() > 0.5: offset.y *= -1
	champ.global_position = map.get_valid_spawn_position(player.global_position + offset)
	world.add_child(champ)
	champ._recalculate_grid()

	var director = world.get_node_or_null("SquadDirector")
	if director:
		var own_power = director._estimate_mech_power(champ)
		champ.max_hp *= max(1.0, own_power / director.NEAR_PEER_BASELINE)
		champ.hp = champ.max_hp

	champ.died.connect(_on_champion_defeated.bind(champ))
	active_enemies += 1

	champ.scale = Vector2(1.3, 1.3)
	if champ.has_method("_show_floating_text"):
		champ._show_floating_text("CHAMPION: " + pilot, Color(0.6, 0.9, 1.0))
	# get_travelling_champion_data() - was calling the nonexistent
	# get_travelling_champion() before this autoload conversion; load().new()
	# on a dynamically-typed var meant GDScript never caught the bad method
	# name at parse time, so a travelling champion spawn would have thrown a
	# runtime "Invalid call" error every time this ran.
	var champ_dialogue = DialogueManager.get_travelling_champion_data()
	if champ_dialogue is Dictionary and champ_dialogue.get("intro", "") != "":
		show_dialogue(pilot, str(champ_dialogue["intro"]), Color(0.6, 0.9, 1.0), 8.0)

func _on_champion_defeated(champ):
	var ghost_id = str(champ.get_meta("ghost_id")) if champ.has_meta("ghost_id") else ""
	if ghost_id != "":
		ChampionCardScript.record_result(ghost_id, true) # player beat the ghost
	# Design ruling: a ghost ALWAYS drops a component + tiles biased by its
	# own equipped rarities. (Deliberately NOT counted toward the 10-boss
	# milestone - that counts regular wave bosses only.)
	LootManager.generate_ghost_loot(champ)
	if champ.has_meta("ghost_pilot"):
		show_dialogue("Shopkeeper", "%s's champion goes down! Their pilot will hear about this." % champ.get_meta("ghost_pilot"), Color(0.8, 1.0, 0.8), 6.0)
	_on_enemy_died()

func _on_enemy_died():
	active_enemies -= 1
	# <= 0, not == 0 - self-healing against any stray double-decrement
	# (e.g. two signals both firing "this bot left the wave" for the same
	# mech) permanently wedging the counter negative, which an exact ==0
	# check can never recover from: every further kill just goes MORE
	# negative, and _close_garage()'s own separate active_enemies <= 0
	# check keeps respawning fresh enemies onto that same negative baseline
	# forever - the wave never clears again for the rest of the run (user
	# report 2026-08-05: stuck on wave 65, killing everything spawned after
	# a Garage visit never advanced it).
	#
	# Not while the wave is still trickling in - killing the first squads
	# before the rest deploy must not count as clearing the wave.
	if active_enemies <= 0 and not _spawning_wave:
		_on_wave_cleared()

var last_garage_wave: int = 1

# Extra lives (playtest request: "so it isn't game over as soon as I get
# killed once", then "3 for casual, 2 for regular, 1 for hard, none for
# why are you doing this to yourself" - see SaveManager.DIFFICULTY_LIVES).
# Refilled on every _close_garage() deploy - same checkpoint last_garage_
# wave already uses, so a death always costs you back to your last garage
# visit at worst, not further. _on_player_died() consumes one and respawns
# in place (full heal, wave continues) instead of running the full death
# sequence until this hits zero - on the top difficulty tier (0 lives),
# that's immediately, matching the original single-life behavior exactly.
var player_lives_remaining: int = SaveManager.DIFFICULTY_LIVES[SaveManager.difficulty]

func _on_player_died():
	# Extra life: respawn in place instead of the full death sequence.
	# Lives = RESPAWNS REMAINING: any death while at least one remains
	# consumes it; only a death at 0 falls through to the real game over.
	# Was `> 1`, which game-overed while the HUD still showed "Lives: 1"
	# (playtest: "the death thing failed when I had two lives - I died, it
	# killed me/game over screened") AND made Hard (1 life) behave
	# identically to the top tier (0) - with `> 0`, every tier's number is
	# literally how many deaths you survive past.
	if player_lives_remaining > 0:
		player_lives_remaining -= 1
		_update_hud()
		player.is_dead = false
		player.hp = player.max_hp
		player.shield_hp = player.max_shield_hp
		if player.has_method("_show_floating_text"):
			player._show_floating_text("LIFE LOST - %d LEFT" % player_lives_remaining, Color(1.0, 0.5, 0.2))
		return

	print("!!! GAME OVER - MAGNIFICENT EXPLOSION !!!")
	# Dying with a Traveling Champion still on the field counts as losing
	# the challenge - the ghost takes the rank points home.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and enemy.has_meta("is_ghost") and not enemy.get("is_dead"):
			ChampionCardScript.record_result(str(enemy.get_meta("ghost_id")), false)
			break
	_despawn_all_drones()
	player.visible = false
	player.set_process(false)
	player.set_physics_process(false)

	# Snapshot the death report now, while player.recent_damage_log is still
	# populated - see Mech.gd's field comment. Per the user's request:
	# "what squad got me, what elements they used".
	# Record ONCE, here (current_wave is about to get reset to
	# last_garage_wave by the kick-back-to-garage timer further down) - the
	# War Room's death log (task #9). _show_death_report itself is invoked
	# exactly once, deferred, further down - it used to also fire
	# synchronously right here, spawning two overlapping report panels.
	SaveManager.record_death(current_wave, _top_damage_label(player.recent_damage_log))

	var explosion = load("res://scripts/visuals/DeathExplosion.gd").new()
	explosion.global_position = player.global_position
	world.add_child(explosion)

	var game_over_cinematic = load("res://scripts/visuals/GameOverCinematic.gd").new()
	game_over_cinematic.death_position = player.global_position
	world.add_child(game_over_cinematic)

	var director = world.get_node_or_null("SquadDirector")
	var loss_text_shown = false
	if director:
		# Check if player died to a rival to show loss text
		for mech in get_tree().get_nodes_in_group("enemy"):
			if mech.has_meta("is_rival") and mech.has_meta("rival_name"):
				director.consecutive_rival_losses += 1
				director.save_learned_state()
				
				if director.consecutive_rival_losses >= 3:
					# Temporary lockout, not permanent - see
					# tournament_locked_out's own comment in SaveManager.gd.
					# Cleared the next time the player beats a rival
					# (_on_rival_defeated below), matching the dialogue's
					# "take some time, build a new rig, and we'll try again
					# next season" framing.
					SaveManager.tournament_locked_out = true
					# Was a zero-arg call - save_game(save_name, mech, inventory)
					# requires all 3, so this threw and silently aborted the
					# rest of _on_player_died() every time, including the
					# 3-second "kick back to Garage" timer below. After a 3rd
					# straight Rival loss the game just hung - no dialogue, no
					# death report, no return to Garage. Matches Main.gd:1136's
					# existing autosave call for the same "player, player_inventory"
					# pattern used everywhere else in this file.
					SaveManager.save_game("autosave", player, player_inventory)
					show_dialogue("Shopkeeper", DialogueManager.get_game_over_3_loss(), Color(1.0, 0.5, 0.5), 10.0)
					loss_text_shown = true
				else:
					var r_name = mech.get_meta("rival_name")
					if director.all_rival_profiles.has(r_name):
						var prof = director.all_rival_profiles[r_name]
						var loss_text = prof.dialogue_loss
						if loss_text == "":
							loss_text = DialogueManager.get_generic_rival_loss()
						show_dialogue("Shopkeeper", loss_text, Color(1.0, 0.5, 0.5), 6.0)
						loss_text_shown = true
				break
	
	if not loss_text_shown:
		var footer = DialogueManager.get_death_footer()
		if footer != "":
			show_dialogue("Shopkeeper", footer, Color(0.8, 0.8, 0.8), 6.0)
	
	call_deferred("_show_death_report", player.recent_damage_log) # the one and only call - see comment above

	# Wait 3 seconds, then kick back to garage
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(func():
		current_wave = last_garage_wave # Kick back to last checkpoint
		
		# Clear all active enemies
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		active_enemies = 0
		
		_open_garage()
	)
	add_child(timer)
	timer.start()

# "How did I die" breakdown (the user's playtest request) - aggregates
# Mech.recent_damage_log (last DEATH_LOG_LOOKBACK_SEC of damage taken) by
# attacker label and by element, then shows a small non-blocking panel over
# the death explosion. Doesn't block anything - it just auto-frees after a
# few seconds (or whenever the player backs out via the Garage/menu).
# Shared by the death-log entry above and _show_death_report's own "what
# killed you" breakdown below - same by_label aggregation either way. Static:
# a pure function of `log`, no instance state - lets tests exercise it
# without spinning up a full Main.gd scene.
static func _top_damage_label(log: Array) -> String:
	if log.is_empty():
		return "Unknown"
	var by_label: Dictionary = {}
	for entry in log:
		var l = str(entry.get("label", "Environment"))
		var amt = float(entry.get("amount", 0.0))
		by_label[l] = by_label.get(l, 0.0) + amt
	var labels_sorted = by_label.keys()
	labels_sorted.sort_custom(func(a, b): return by_label[a] > by_label[b])
	return labels_sorted[0]

func _show_death_report(log: Array):
	if log.is_empty():
		return

	var by_label: Dictionary = {}
	var by_element: Dictionary = {}
	for entry in log:
		var l = str(entry.get("label", "Environment"))
		var e = str(entry.get("element", "RAW"))
		var amt = float(entry.get("amount", 0.0))
		by_label[l] = by_label.get(l, 0.0) + amt
		by_element[e] = by_element.get(e, 0.0) + amt

	var labels_sorted = by_label.keys()
	labels_sorted.sort_custom(func(a, b): return by_label[a] > by_label[b])
	var elements_sorted = by_element.keys()
	elements_sorted.sort_custom(func(a, b): return by_element[a] > by_element[b])

	var canvas = CanvasLayer.new()
	canvas.layer = 120
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.02, 0.02, 0.92)
	style.border_color = Color(1.0, 0.35, 0.3)
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.position += Vector2(-230, 40)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "DESTROYED"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1.0, 0.45, 0.4)
	vbox.add_child(title)

	var squad_parts: Array = []
	for l in labels_sorted:
		squad_parts.append("%s (%d)" % [l, int(round(by_label[l]))])
	var squad_line = Label.new()
	squad_line.text = "Hit by: " + ", ".join(squad_parts)
	squad_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	squad_line.custom_minimum_size = Vector2(428, 0)
	vbox.add_child(squad_line)

	var elem_line = Label.new()
	elem_line.text = "Elements: " + ", ".join(elements_sorted)
	elem_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elem_line.custom_minimum_size = Vector2(428, 0)
	elem_line.modulate = Color(0.85, 0.85, 0.9)
	vbox.add_child(elem_line)

	add_child(canvas)

	var fade_timer = Timer.new()
	fade_timer.wait_time = 7.0
	fade_timer.one_shot = true
	fade_timer.timeout.connect(canvas.queue_free)
	canvas.add_child(fade_timer)
	fade_timer.start()

func _on_wave_cleared():
	print("--- WAVE CLEARED ---")
	AudioManager.set_combat_state(false) # back to the ambient loop
	# Occasional post-wave debrief when the director just logged a lopsided
	# kill pattern (see SquadDirector.get_debrief_line's gating).
	var tell_director = world.get_node_or_null("SquadDirector")
	if tell_director:
		var debrief = tell_director.get_debrief_line()
		if debrief != "":
			show_dialogue("Frank", debrief, Color(0.7, 0.9, 1.0), 5.0)
	current_wave += 1
	if current_wave > SaveManager.max_wave_reached:
		SaveManager.max_wave_reached = current_wave
	# Tournament arc unlock (the user: "yes re wave/level" - Level 100 ==
	# Wave 100, the same threshold Boss Rush already uses). Eligibility for
	# the picker is actually computed live off max_wave_reached, but this
	# flag also drives the one-time Tournament-unlock beat if anything ever
	# wants to react to the moment itself, so it's kept in sync here too.
	if current_wave >= 100:
		SaveManager.tournament_arc_unlocked = true
	if _should_rotate_map():
		_rotate_campaign_map()
	# Pixel-art cutscene beat, if the manifest maps one to the upcoming
	# wave (config/cutscenes/manifest.json). Plays once per session,
	# pauses the tree itself, and hands off to the normal intermission
	# when it finishes or gets skipped - no scene mapped means zero change.
	var cutscene = CutscenePlayer.maybe_create_for_wave(current_wave)
	if cutscene:
		cutscene.finished.connect(_start_intermission)
		add_child(cutscene)
	else:
		_start_intermission()

func _should_rotate_map() -> bool:
	if SaveManager.current_game_mode != "campaign":
		return false
	if current_wave - _map_rotation_wave_start >= MAP_ROTATION_MAX_WAVES:
		return true
	return _map_rotation_elapsed >= MAP_ROTATION_MAX_SECONDS

# Regenerates the battlefield terrain (see MAP_ROTATION_MAX_WAVES/
# MAP_ROTATION_MAX_SECONDS above). Only ever called from _on_wave_cleared,
# a safe checkpoint with zero active enemies - this tears down and rebuilds
# the whole map, so anything tied to the old layout has to go with it.
#
# Live Mechs (player, drones) don't need to be manually repointed at the
# new map REFERENCE: Mech._get_map_ref() already self-heals onto whatever
# node is currently in the "map_generator" group the instant its cached
# reference goes stale, which happens automatically the moment the old map
# is freed below (see Mech.gd:60-64). That's only half the story though -
# self-healing WHICH map a mech reads terrain from says nothing about
# whether its current WORLD POSITION is still valid on that new terrain.
# The player gets explicitly relocated below (map.get_valid_spawn_position)
# precisely because the freshly-rerolled layout can put anything at those
# old coordinates - a solid Obstacle, open water, whatever. Drones used to
# be left at their stale positions with no such correction (user report,
# 2026-08-11: "if the map changes midrun my drone vanishes" - landing
# inside newly-placed solid terrain with no path back to the player is
# exactly what that looks like from the player's side), so they now get
# the same treatment, scattered near the player's own new spawn point so
# they don't all stack on one tile. Existing enemies and dropped loot have
# no such self-heal (their AI/pickup state is meaningless on a different
# layout anyway), so those get cleared instead - same pattern
# _on_player_died() already uses for its own "clear the field" cleanup.
func _rotate_campaign_map():
	for loot in get_tree().get_nodes_in_group("loot"):
		if is_instance_valid(loot):
			loot.queue_free()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies = 0

	var old_type = map.map_type if is_instance_valid(map) else ""
	if is_instance_valid(map):
		map.queue_free()

	map = MapGenerator.new()
	# Avoid immediately re-rolling the same biome the player is leaving, and
	# keep Water gated on the player's live jumpjet state (see
	# _water_eligible_map_types above).
	var pool = _water_eligible_map_types()
	var choices = pool.filter(func(t): return t != old_type)
	map.map_type = choices[randi() % choices.size()] if not choices.is_empty() else pool[randi() % pool.size()]
	map.name = "GameMap"
	world.add_child(map)

	if player:
		player.global_position = map.get_valid_spawn_position(Vector2(map.width * map.tile_size / 2.0, map.height * map.tile_size / 2.0))

		# Relocate every live drone (bay id -> Drone, see drone_nodes' own
		# field comment) onto valid terrain near the player's own new spawn
		# point - see this function's header comment for why this is needed
		# at all. Small per-drone random offset so 2+ drones don't all land
		# on the exact same tile; get_valid_spawn_position's own spiral
		# search pulls each one off an obstacle/out-of-bounds target if the
		# offset happens to land on one. Nested inside `if player:` since
		# there's no sane "near the player" position without one.
		for bay_id in drone_nodes:
			var drone = drone_nodes[bay_id]
			if is_instance_valid(drone):
				var offset = Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
				drone.global_position = map.get_valid_spawn_position(player.global_position + offset)

	_map_rotation_wave_start = current_wave
	_map_rotation_elapsed = 0.0

func _open_garage():
	# Idempotent: never stack a second Garage on top of an existing one.
	# _open_garage has multiple callers (the new-game start, the tutorial's
	# _ensure_in_garage, DebugMenu's Teleport, the extraction return) and
	# used to create+add_child a fresh GarageMenu every time regardless -
	# so any two firing in the same frame (e.g. the tutorial forcing the
	# Garage open a frame before the start sequence does) left TWO garages
	# parented at once: a doubled/ghosted inventory, and a stale orphaned
	# copy whose "Deploy to Battlefield" button pointed at a garage that was
	# no longer the live one ("Deploy does nothing" / "tutorial broke the
	# game"). One live garage, always.
	if garage_ui and is_instance_valid(garage_ui):
		return
	print("Opening Garage Menu...")
	get_tree().paused = true
	AudioManager.set_combat_state(false) # garage is downtime regardless of how we got here

	# Garage-open checkpoint for StockBuildEvolution's deviation tracking
	# (see that file's header) - decide any pending (template, role) batches
	# now rather than waiting for MAX_TRACKED_DEVIATIONS, so nothing sits
	# half-decided across a play-session boundary.
	if world and world.has_node("SquadDirector"):
		var director = world.get_node("SquadDirector")
		if director.stock_build_evolution:
			director.stock_build_evolution.flush_all_pending()
	_despawn_all_drones()

	# Full heal on entering garage
	player.hp = player.max_hp
	player.visible = true
	player.set_process(true)
	player.set_physics_process(true)
	
	var GarageMenuClass = load("res://scripts/ui/GarageMenu.gd")
	if GarageMenuClass:
		garage_ui = GarageMenuClass.new()
		add_child(garage_ui)
	else:
		print("Failed to load GarageMenu!")
	
func _close_garage():
	print("Deploying from Garage...")
	get_tree().paused = false

	garage_timer = 90.0
	player_lives_remaining = SaveManager.DIFFICULTY_LIVES[SaveManager.difficulty]
	_update_hud()

	last_garage_wave = current_wave

	if player != null:
		# Anything could have changed in there - tile placement, routing,
		# synergy cycling, Mythic toggles, part swaps. The mech's
		# precalculated weapons are stale until _recalculate_grid runs, and
		# individual garage edit paths historically forgot to set this flag
		# (the "projectiles don't change until restart" bug). One
		# unconditional flag on deploy covers every edit path, present and
		# future.
		player.is_grid_dirty = true
		# Recalculate NOW rather than leaving it lazy - _shoot() only ever
		# ran _recalculate_grid() on-demand the first time is_grid_dirty was
		# true, which meant the (non-trivial: iterates every tile across
		# every component, then runs the full packet simulation) recalc
		# happened synchronously in the middle of the player's first shot
		# after every deploy, not just the first shot of a session. the user:
		# "the first time I shoot after a few seconds of not shooting it
		# freezes the game... a brief freeze, .25-.5 seconds." Doing it here
		# instead moves that cost to the deploy transition (already a scene
		# change moment) instead of interrupting live combat input.
		if player.has_method("_recalculate_grid"):
			player._recalculate_grid()
		# Live drones share their loadout OBJECT with the Drone Bay tile the
		# garage just edited, but nothing ever marked THEIR grids dirty - an
		# already-flying drone kept firing its stale precalculated weapons
		# until it died and respawned ("I just made a change in the garage
		# ... it changed in the test range, but did not update in game").
		# Same unconditional-on-deploy reasoning as the player's own flag
		# above: one recalc per live drone per deploy covers every drone
		# edit path, present and future.
		for bay_id in drone_nodes:
			var live_drone = drone_nodes[bay_id]
			if is_instance_valid(live_drone) and live_drone.has_method("_recalculate_grid"):
				live_drone.is_grid_dirty = true
				live_drone._recalculate_grid()
		# Prewarm every already-known enemy StockBuild's energy-simulation
		# cache here too - same "move the cost to the deploy transition
		# instead of live combat" reasoning as the player/drone recalcs
		# just above (user, 2026-08-10: "would it help if we did a
		# loading screen when we return from the garage for it to build
		# out the enemy mechs in advance"). No-op for builds already
		# warm this session - see StockBuildEvolution.
		# prewarm_all_simulation_caches's own comment.
		if world and world.has_node("SquadDirector"):
			var director = world.get_node("SquadDirector")
			if director.stock_build_evolution:
				director.stock_build_evolution.prewarm_all_simulation_caches()
		SaveManager.save_game("autosave", player, player_inventory)
		_spawn_drones_if_needed()
		# Reactive music: key the soundtrack to the build that just left the
		# bay - the dominant synergy across every armed weapon's packet.
		var syn_totals: Dictionary = {}
		for data in player.precalculated_weapons:
			for k in data.packet.synergies:
				syn_totals[k] = syn_totals.get(k, 0.0) + data.packet.synergies[k]
		var dominant = EnergyPacket.SynergyType.RAW
		var dominant_val = 0.0
		for k in syn_totals:
			if syn_totals[k] > dominant_val:
				dominant_val = syn_totals[k]
				dominant = k
		AudioManager.set_dominant_synergy(dominant)

	if garage_ui:
		garage_ui.queue_free()
		garage_ui = null
		
	if active_enemies <= 0:
		_show_countdown()
