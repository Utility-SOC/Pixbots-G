extends Node

# Phase 9 of the batch-pool full-parity plan (2026-08-10): biome cross-
# triggers (Lightning+Water AoE, Fire+Forest burn-spread, Fire+Oil-Slick
# ignition). Resolved decision: port faithfully and verify against a FAKE
# map/oil-slick stub, even though the Garage Test Range's own private,
# deliberately-isolated SubViewport/World2D means these can never actually
# be observed firing there today (no real MapGenerator or OilSlickHazard
# is ever registered in that private world - see GarageTestRange.gd's own
# header comment on why that isolation exists). This check exists so
# "full parity" stays true in the CODE, not just in whatever happens to be
# currently observable - the fakes below stand in for real world state the
# same way BuildLoadoutBreakdownCheck.gd/StockBuildPromotionGateCheck.gd
# already fake out SquadDirector-adjacent dependencies elsewhere in this
# project, rather than touching anything real.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_target(world: Node, pos: Vector2) -> Node:
	var t = MechScript.new()
	t.is_player = false
	t.max_hp = 1e9
	t.hp = 1e9
	t.global_position = pos
	world.add_child(t)
	return t

# Minimal fake standing in for the real MapGenerator - only exposes what
# Projectile.gd's biome-trigger code actually reads
# (has_method("get_biome_at_world_pos") + a BiomeType constant table).
# Reuses the REAL BiomeType enum values (MapGeneratorScript.BiomeType) so
# a match against real biome semantics, not a made-up parallel enum that
# could silently drift from what the real system means by "WATER"/"FOREST".
class FakeMapGenerator extends Node:
	var BiomeType = MapGeneratorScript.BiomeType
	var fixed_biome: int = MapGeneratorScript.BiomeType.GRASSLAND
	func get_biome_at_world_pos(_pos: Vector2) -> int:
		return fixed_biome

# Minimal fake standing in for a real OilSlickHazard - only exposes what
# Projectile.gd's ignite-trigger code actually reads (IGNITE_RADIUS +
# ignite()).
class FakeOilSlick extends Node2D:
	const IGNITE_RADIUS = 60.0
	var ignited: bool = false
	func ignite():
		ignited = true

func _ready():
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(16)
	world.add_child(pool)

	# --- 1: Lightning + Water biome = massive AoE (400px radius, 2x damage) ---
	var fake_map = FakeMapGenerator.new()
	fake_map.fixed_biome = MapGeneratorScript.BiomeType.WATER
	fake_map.add_to_group("map_generator")
	world.add_child(fake_map)

	var direct = _make_target(world, Vector2(300, 0))
	var water_splash = _make_target(world, Vector2(600, 0)) # 300px from the shot - inside the 400px water-biome radius, outside a plain hit radius
	pool.register_target(direct)
	pool.register_target(water_splash)
	var ltg_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 100.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 1.0})
	var water_hp_before = water_splash.hp
	pool._step_hit_test()
	_check("a Lightning hit while standing in a (fake) WATER biome triggers a wide AoE splash (300px away took %.0f damage)" % (water_hp_before - water_splash.hp),
		water_splash.hp < water_hp_before)
	pool.despawn(ltg_i)
	pool.unregister_target(direct)
	pool.unregister_target(water_splash)
	direct.queue_free()
	water_splash.queue_free()

	# --- 2: a Lightning hit OUTSIDE a water biome does NOT trigger the AoE
	# (regression guard - the trigger must be biome-gated, not unconditional) ---
	fake_map.fixed_biome = MapGeneratorScript.BiomeType.GRASSLAND
	var direct2 = _make_target(world, Vector2(300, 0))
	var no_splash = _make_target(world, Vector2(600, 0))
	pool.register_target(direct2)
	pool.register_target(no_splash)
	var ltg_i2 = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 100.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.LIGHTNING, {EnergyPacket.SynergyType.LIGHTNING: 1.0})
	var no_splash_hp_before = no_splash.hp
	pool._step_hit_test()
	_check("a Lightning hit OUTSIDE a water biome does NOT trigger the wide AoE (biome-gated, not unconditional)",
		no_splash.hp == no_splash_hp_before)
	pool.despawn(ltg_i2)
	pool.unregister_target(direct2)
	pool.unregister_target(no_splash)
	direct2.queue_free()
	no_splash.queue_free()

	# --- 3: Fire + Forest biome = burn spread (200px radius, applies burning) ---
	fake_map.fixed_biome = MapGeneratorScript.BiomeType.FOREST
	var direct3 = _make_target(world, Vector2(300, 0))
	var forest_splash = _make_target(world, Vector2(450, 0)) # 150px away - inside the 200px forest radius
	pool.register_target(direct3)
	pool.register_target(forest_splash)
	var fire_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 100.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	var forest_hp_before = forest_splash.hp
	pool._step_hit_test()
	_check("a Fire hit while standing in a (fake) FOREST biome burns nearby targets too (%.0f damage)" % (forest_hp_before - forest_splash.hp),
		forest_splash.hp < forest_hp_before)
	_check("the forest burn-spread also applies the Burning status to what it splashed",
		forest_splash.status_effects.get("burning", 0.0) > 0.0)
	pool.despawn(fire_i)
	pool.unregister_target(direct3)
	pool.unregister_target(forest_splash)
	direct3.queue_free()
	forest_splash.queue_free()
	fake_map.queue_free()

	# --- 4: Fire + Oil Slick = ignition, independent of biome entirely ---
	# EntityCache.get_group() caches its result per-frame (Engine.get_
	# physics_frames()/get_process_frames() stamp) - test #3's Fire shot
	# already called EntityCache.get_group("oil_slick") (found nothing, the
	# slick didn't exist yet) and that empty result would otherwise still
	# be cached for the rest of this synchronous _ready() unless a real
	# frame boundary passes in between, same as production code relies on
	# for its own within-frame caching correctness - not a pool bug.
	await get_tree().process_frame
	var slick = FakeOilSlick.new()
	slick.global_position = Vector2(340, 0) # within IGNITE_RADIUS of the shot's impact point
	slick.add_to_group("oil_slick")
	world.add_child(slick)
	var direct4 = _make_target(world, Vector2(300, 0))
	pool.register_target(direct4)
	var fire_slick_i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, 100.0, 20.0, 5.0, Color.WHITE, 1.0, true, null,
		EnergyPacket.SynergyType.FIRE, {EnergyPacket.SynergyType.FIRE: 1.0})
	pool._step_hit_test()
	_check("a Fire hit near a registered oil slick ignites it",
		slick.ignited)
	pool.despawn(fire_slick_i)
	pool.unregister_target(direct4)
	direct4.queue_free()
	slick.queue_free()

	if failures == 0:
		print("PASS: biome cross-triggers (Lightning+Water AoE, Fire+Forest burn-spread, Fire+Oil-Slick ignition) all fire correctly against a fake map/oil-slick stub, biome-gated (not unconditional), even though the Test Range's own isolated world can't show them live yet")
	get_tree().quit(0 if failures == 0 else 1)
