class_name PhaseDrain
extends RefCounted

# The Phase Shifter's cost (see PhaseShifterTile): `mech.phase_flow` is the share of normal energy flow still moving
# through the mech (1.0 = untouched). Every physics tick spent inside obstacles multiplies it by (1 - 0.05 x pieces
# touched); once clear it climbs back over PhaseShifterTile.RECOVER_SECONDS. Weapons and shields read it.

const MAX_PIECES = 20
const BODY_RADIUS = 18.0
const TICK_HZ = 60.0

# Flow after `delta` seconds inside `pieces` obstacle pieces. Frame-rate independent: the per-tick factor is applied
# delta x 60 times.
static func drained(flow: float, pieces: int, delta: float) -> float:
	if pieces <= 0:
		return flow
	var per_tick = maxf(0.0, 1.0 - PhaseShifterTile.DRAIN_PER_PIECE * float(mini(pieces, MAX_PIECES)))
	return flow * pow(per_tick, delta * TICK_HZ)

static func recovered(flow: float, delta: float) -> float:
	return minf(1.0, flow + delta / PhaseShifterTile.RECOVER_SECONDS)

# Number of distinct obstacle pieces (collider + shape) overlapping the mech's body right now.
static func pieces_touching(body: Node2D) -> int:
	var space = body.get_world_2d().direct_space_state
	var q = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = BODY_RADIUS
	q.shape = shape
	q.transform = Transform2D(0.0, body.global_position)
	q.collision_mask = SimPhysics.LAYER_OBSTACLE
	var seen := {}
	for res in space.intersect_shape(q, MAX_PIECES):
		seen[str(res["collider_id"]) + ":" + str(res["shape"])] = true
	return seen.size()

# Called every physics frame for a mech with a working shifter.
static func tick(mech: Node, delta: float) -> void:
	if not mech.phase_shifter_active:
		mech.phase_flow = 1.0
		return
	var n = pieces_touching(mech)
	mech.phase_flow = drained(mech.phase_flow, n, delta) if n > 0 else recovered(mech.phase_flow, delta)
