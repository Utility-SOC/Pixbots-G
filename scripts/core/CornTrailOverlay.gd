class_name CornTrailOverlay
extends Node2D

# Trampled-corn trail decal layer for FightShovel 1920 (Utility-SOC: "corn-
# fields that leave trails when walked through"). A separate always-on-top
# overlay rather than mutating the baked ground chunk textures - those are
# deliberately baked ONCE at load and never touched again elsewhere in
# MapGenerator.gd (see _build_terrain_chunk's own comment: "Purely a load-
# time cost... never touched again"). Permanent for the run once trampled -
# no regrowth timer, the simplest honest reading of "leaves a trail."
#
# Created (and freed/recreated on regen) by MapGenerator._ensure_corn_
# trail_overlay, one per map. trample() is called from Mech._refresh_water_
# state, piggybacking the exact per-mech-per-tick terrain-lookup precedent
# that function already established (same grid_pos, same "cheap enough to
# run for every mech every physics tick" cost class) rather than a new
# per-frame scan.

var tile_size: float = 32.0
var _trampled: Dictionary = {} # Vector2i -> true
var _dirty: bool = false
var _redraw_timer: float = 0.0

const REDRAW_THROTTLE = 0.2
const TRAIL_COLOR = Color(0.4, 0.32, 0.16, 0.55) # flattened dirt-brown path

func _ready():
	z_index = 1 # above the baked ground, below obstacles/mechs

# Returns true the first time a given cell is trampled (false on repeat
# calls for an already-trampled cell) - callers don't need to care, but it
# makes the "did anything actually change" intent explicit at the call site.
func trample(cell: Vector2i) -> bool:
	if _trampled.has(cell):
		return false
	_trampled[cell] = true
	_dirty = true
	return true

func _process(delta: float):
	if not _dirty:
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_THROTTLE
		_dirty = false
		queue_redraw()

func _draw():
	for cell in _trampled:
		draw_rect(Rect2(Vector2(cell.x, cell.y) * tile_size, Vector2.ONE * tile_size), TRAIL_COLOR)
