extends RefCounted

# What the ground does to a walking mech. Pure lookups so the player controller, the AI movement and the
# tests share one table. Biome ints are MapGenerator.BiomeType:
#   GRASSLAND 0, WATER 1, DESERT 2, FOREST 3, TUNDRA 4, VOLCANO 5, DUNGEON 6, ROAD 7, FLOOR 8
#
#   speed   multiplier on walking speed (roads reward routes; ash and undergrowth cost a little)
#   traction how fast velocity can change: 1.0 = normal, low = ice, where you keep sliding the way you
#            were going and steering takes a moment to bite
# Jumpjet and amphibious-flying mechs ignore all of it (they are not touching the ground).

const ROAD_SPEED = 1.25
const ASH_SPEED = 0.9
const UNDERGROWTH_SPEED = 0.92
const ICE_TRACTION = 0.18

static func speed(biome: int) -> float:
	match biome:
		7: return ROAD_SPEED
		5: return ASH_SPEED
		3: return UNDERGROWTH_SPEED
	return 1.0

static func traction(biome: int) -> float:
	return ICE_TRACTION if biome == 4 else 1.0

# Velocity step toward `target` under `accel` (px/s^2) on a surface with `traction`.
static func steer(current: Vector2, target: Vector2, accel: float, traction_factor: float, delta: float) -> Vector2:
	return current.move_toward(target, accel * traction_factor * delta)

# AI mechs set `velocity` outright each tick; this turns that into a slide on low-traction ground.
static func slide(previous: Vector2, wanted: Vector2, traction_factor: float, delta: float) -> Vector2:
	if traction_factor >= 1.0:
		return wanted
	var k = 1.0 - exp(-8.0 * traction_factor * delta)
	return previous.lerp(wanted, k)
