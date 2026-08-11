extends Node

# Regression check for the 2026-08-11 missile rework (user ruling):
#   1. "Nuke tier" - a charge past 32 frames at 600000+ energy/frame reads
#      as genuinely different (terrain-wiping), scaling up to a full
#      "feels like a nuke" read at the frame-multiplier ladder's own 256
#      ceiling - MissileRackTile._nuke_scale().
#   2. min_range is now 2x THIS shot's own blast radius (dynamic, per
#      shot) instead of the old flat 350.0 guess -
#      MissileRackTile._estimate_effective_radius()/MIN_RANGE_RADIUS_MULT.
#   3. Missile Rack targeting choice (Mythic-only): Furthest (unchanged
#      default) vs Most Powerful (new) - MissileRackTile._find_target_
#      in_range() dispatch.
#   4. Nuke-tier MortarShell detonations destroy DestructibleObstacle-like
#      nodes ("obstacle" group) within a scaled blast radius -
#      MortarShell._wipe_terrain(). A normal (non-nuke) shell leaves
#      obstacles untouched.
#   5. ElementalPuddle fades toward a scorched "bombed out" ash color over
#      its lifetime when nuke_scale > 0, and stays the plain vibrant
#      synergy color (only alpha changes) when nuke_scale == 0 - unchanged
#      regression guard for every puddle that isn't nuke-tier.
#
# SAFETY: mirrors AntiMissileInterceptCheck.gd's established safe pattern -
# `components = {}` on every Mech before add_child() so Mech._ready() never
# runs build_loadout_for_role(). No SquadDirector, real or fake, is ever
# constructed here.

const MissileRackTileScript = preload("res://scripts/tiles/MissileRackTile.gd")
const MortarShellScript = preload("res://scripts/attacks/MortarShell.gd")
const ElementalPuddleScript = preload("res://scripts/attacks/ElementalPuddle.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_mech(pos: Vector2, p_is_player: bool, p_max_hp: float) -> Node:
	var m = MechScript.new()
	m.is_player = p_is_player
	m.components = {}
	m.max_hp = p_max_hp
	m.hp = p_max_hp
	world.add_child(m)
	m.global_position = pos
	if p_is_player:
		m.add_to_group("player") # Mech.gd itself only ever auto-groups enemies, see its own field comment
	return m

func _ready():
	world = Node.new()
	add_child(world)

	# --- 1: nuke_scale math (pure, no scene needed) -----------------------
	var tile = MissileRackTileScript.new()
	tile.mythic_frame_multiplier = 16
	_check("16 frames never qualifies for nuke tier regardless of magnitude",
		tile._nuke_scale(999999999.0) == 0.0)

	tile.mythic_frame_multiplier = 64
	_check("64 frames at 400000 energy/frame (below 600000) doesn't qualify",
		tile._nuke_scale(64.0 * 400000.0) == 0.0)

	var scale_at_64 = tile._nuke_scale(64.0 * 600000.0)
	_check("64 frames at exactly 600000 energy/frame qualifies and scales to ~(64-32)/(256-32)",
		abs(scale_at_64 - (32.0 / 224.0)) < 0.001)

	tile.mythic_frame_multiplier = 256
	_check("256 frames at 600000+ energy/frame reaches the full 1.0 nuke scale",
		tile._nuke_scale(256.0 * 600000.0) == 1.0)

	tile.mythic_frame_multiplier = 512 # past the real ladder's ceiling, but the formula itself must still clamp
	_check("nuke_scale never exceeds 1.0 even past the ladder's own 256 ceiling",
		tile._nuke_scale(512.0 * 600000.0) == 1.0)

	# --- 2: dynamic min_range scales with frame_multiplier -----------------
	var packet = EnergyPacket.new()
	packet.add_synergy(EnergyPacket.SynergyType.EXPLOSION, 100.0)
	tile.mythic_frame_multiplier = 1
	var radius_1x = tile._estimate_effective_radius(packet, 100.0)
	tile.mythic_frame_multiplier = 64
	var radius_64x = tile._estimate_effective_radius(packet, 6400.0)
	_check("a 64x frame charge has a measurably bigger effective radius than a 1x charge of the same ratios",
		radius_64x > radius_1x * 2.0) # sqrt(64) = 8x scale, well past 2x
	_check("MIN_RANGE_RADIUS_MULT is exactly 2.0 (user ruling: 2x the shot's own blast radius)",
		MissileRackTileScript.MIN_RANGE_RADIUS_MULT == 2.0)

	# --- 3: targeting mode dispatch -----------------------------------------
	var near_weak = _make_mech(Vector2(1000, 0), false, 500.0)
	var far_strong = _make_mech(Vector2(3000, 0), false, 5000.0)
	var muzzle = Vector2.ZERO
	var min_r = 100.0
	var max_r = 5000.0

	var furthest = tile._find_furthest_target_in_range(muzzle, true, min_r, max_r)
	_check("Furthest picks the more distant target regardless of its power",
		furthest == far_strong)

	var most_powerful = tile._find_most_powerful_target_in_range(muzzle, true, min_r, max_r)
	_check("Most Powerful picks the higher-max_hp target regardless of distance",
		most_powerful == far_strong) # far_strong is both furthest AND strongest here - swap roles next

	near_weak.max_hp = 9000.0
	near_weak.hp = 9000.0
	var most_powerful2 = tile._find_most_powerful_target_in_range(muzzle, true, min_r, max_r)
	_check("Most Powerful re-picks correctly once the CLOSER target becomes the tougher one",
		most_powerful2 == near_weak)
	var furthest2 = tile._find_furthest_target_in_range(muzzle, true, min_r, max_r)
	_check("Furthest is unaffected by the max_hp change - still the distant one",
		furthest2 == far_strong)

	tile.rarity = HexTile.Rarity.MYTHIC
	tile.targeting_mode = 1
	var dispatched = tile._find_target_in_range(muzzle, true, min_r, max_r)
	_check("_find_target_in_range dispatches to Most Powerful when a Mythic tile's targeting_mode is set to it",
		dispatched == near_weak)
	tile.targeting_mode = 0
	var dispatched2 = tile._find_target_in_range(muzzle, true, min_r, max_r)
	_check("_find_target_in_range dispatches back to Furthest when targeting_mode is 0",
		dispatched2 == far_strong)

	near_weak.queue_free()
	far_strong.queue_free()

	# --- 4: nuke-tier terrain wipe destroys obstacles in the blast area ----
	# _FakeObstacle (defined at the bottom of this file) is a minimal
	# stand-in with just the surface MortarShell._wipe_terrain() actually
	# needs (add_to_group("obstacle") + global_position + apply_damage),
	# not a real DestructibleObstacle, whose own _init() reaches into
	# TileStatsRegistry-adjacent stat tables this check has no reason to
	# depend on.
	var obstacle = _FakeObstacle.new()
	world.add_child(obstacle)
	obstacle.global_position = Vector2(500, 500)
	obstacle.add_to_group("obstacle")

	var shell_nuke = MortarShellScript.acquire()
	shell_nuke.setup(Vector2(500, 500), Vector2(500, 500), 0.01, 100.0, {EnergyPacket.SynergyType.EXPLOSION: 100.0}, true, null, 0.0, 1.0, false, 256, 1.0)
	world.add_child(shell_nuke)
	shell_nuke._process(0.2) # past the 0.15 floor, lands and detonates this tick
	_check("a nuke-tier shell's terrain wipe destroys an obstacle inside its blast radius",
		obstacle.destroyed)
	shell_nuke.release()

	var obstacle2 = _FakeObstacle.new()
	world.add_child(obstacle2)
	obstacle2.global_position = Vector2(600, 600)
	obstacle2.add_to_group("obstacle")
	var shell_normal = MortarShellScript.acquire()
	shell_normal.setup(Vector2(600, 600), Vector2(600, 600), 0.01, 100.0, {EnergyPacket.SynergyType.EXPLOSION: 100.0}, true, null, 0.0, 1.0, false, 1, 0.0)
	world.add_child(shell_normal)
	shell_normal._process(0.2)
	_check("a normal (non-nuke) shell leaves obstacles in its blast radius untouched",
		not obstacle2.destroyed)
	shell_normal.release()

	# --- 5: puddle ash-fade vs normal vibrant-color regression guard -------
	var vibrant_puddle = ElementalPuddleScript.new()
	vibrant_puddle.setup(80.0, 10.0, 100.0, {EnergyPacket.SynergyType.FIRE: 100.0}, true, 0.0)
	world.add_child(vibrant_puddle)
	vibrant_puddle._process(9.0) # near end of its 10s life
	_check("a normal puddle (nuke_scale 0.0) stays modulate-white - only alpha changes, unchanged regression guard",
		vibrant_puddle._circle_poly.modulate.r == 1.0 and vibrant_puddle._circle_poly.modulate.g == 1.0 and vibrant_puddle._circle_poly.modulate.b == 1.0)

	var ash_puddle = ElementalPuddleScript.new()
	ash_puddle.setup(80.0, 10.0, 100.0, {EnergyPacket.SynergyType.FIRE: 100.0}, true, 1.0)
	world.add_child(ash_puddle)
	ash_puddle._process(9.0) # near end of its life, nuke_scale 1.0 -> should be nearly fully cooled to ash
	_check("a nuke-tier puddle (nuke_scale 1.0) has visibly cooled toward ash color by near end of life",
		ash_puddle._circle_poly.modulate.r < 0.3 and ash_puddle._circle_poly.modulate.g < 0.3)

	var ash_puddle_early = ElementalPuddleScript.new()
	ash_puddle_early.setup(80.0, 10.0, 100.0, {EnergyPacket.SynergyType.FIRE: 100.0}, true, 1.0)
	world.add_child(ash_puddle_early)
	ash_puddle_early._process(0.1) # just spawned
	_check("a nuke-tier puddle starts still close to full vibrant color right after spawning (cools OVER time, not instantly)",
		ash_puddle_early._circle_poly.modulate.r > 0.9)

	if failures == 0:
		print("PASS: nuke-tier missile threshold/scaling, dynamic min-range, Furthest/Most Powerful targeting, terrain-wiping detonations, and puddle ash-fade all behave correctly")
	get_tree().quit(0 if failures == 0 else 1)

# Minimal "obstacle" stand-in - just the surface MortarShell._wipe_terrain()
# actually touches (group membership, global_position, apply_damage), not a
# real DestructibleObstacle (whose _init() pulls in stat tables this check
# has no reason to depend on).
class _FakeObstacle extends Node2D:
	var destroyed = false
	func apply_damage(_amount: float, _element: String = "RAW", _source: Node = null, _was_reflected: bool = false, _source_label_override: String = ""):
		destroyed = true
