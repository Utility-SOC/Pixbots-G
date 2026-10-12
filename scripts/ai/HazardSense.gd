class_name HazardSense
extends RefCounted

# Enemy awareness of map hazards: a wary bot steps out of (and will not walk into) a lava vent that is about to
# erupt or an oil slick that is burning. Vents and slicks stay a tool against careless squads: how wary a bot is
# is fixed per bot and rises with difficulty, so Casual squads still wander into them and the top difficulty
# mostly does not. Pure queries over the hazard groups; Mech asks for a push and blends it into its velocity.

# Share of bots that watch for hazards, by SaveManager.difficulty. (tune)
const WARY_BY_DIFFICULTY = [0.0, 0.3, 0.6, 0.9]
# How far ahead (seconds of walking) a bot looks when deciding not to walk into a danger zone.
const LOOKAHEAD = 0.4
# Slack added to a hazard's radius so a bot clears the edge, not just touches it.
const MARGIN = 1.15

static func wary_share(difficulty: int) -> float:
	return WARY_BY_DIFFICULTY[clampi(difficulty, 0, WARY_BY_DIFFICULTY.size() - 1)]

# Stable per bot (from its instance id) so a bot does not flip between careful and careless.
static func is_wary(id: int, difficulty: int) -> bool:
	return float(posmod(id * 2654435761, 1000)) / 1000.0 < wary_share(difficulty)

# Is `point` inside a zone that is about to hurt, or is hurting? Returns the centre of that zone, or null.
static func danger_centre(point: Vector2, vents: Array, slicks: Array):
	for v in vents:
		if is_instance_valid(v) and v.has_method("is_dangerous") and v.is_dangerous() \
				and point.distance_to(v.global_position) <= v.radius * MARGIN:
			return v.global_position
	for s in slicks:
		if is_instance_valid(s) and s.get("is_burning") == true and point.distance_to(s.global_position) <= s.radius * MARGIN:
			return s.global_position
	return null

# Unit direction a bot at `pos` moving with `velocity` should add to leave or avoid a danger zone, or ZERO when clear.
static func push(pos: Vector2, velocity: Vector2, vents: Array, slicks: Array) -> Vector2:
	if vents.is_empty() and slicks.is_empty():
		return Vector2.ZERO
	var centre = danger_centre(pos, vents, slicks)
	if centre == null:
		centre = danger_centre(pos + velocity * LOOKAHEAD, vents, slicks)
	if centre == null:
		return Vector2.ZERO
	var away: Vector2 = pos - centre
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	return away.normalized()
