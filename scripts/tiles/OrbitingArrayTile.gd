class_name OrbitingArrayTile
extends HexTile

# A 3-hex rotatable triangle capital weapon tile (requires all 6 external faces
# carrying >= 10,000 energy). When fired, spawns OrbitingProjectiles that enter
# synergy-driven orbital trajectories around the bot (Kinetic/Pierce fast elliptical,
# Vortex bezier-blob, Lightning lashing bolts, Poison hazard trails).
#
# Follows LanceMountTile.gd's capital-weapon pattern exactly: process_energy
# only ACCUMULATES per-face magnitudes during the sim pass; check_face_gate()
# (called once per Mech._recalculate_grid, right before clear_pending resets
# the accumulators) decides ready_to_fire and stashes the firing payload; and
# Mech._tick_weapon_charges auto-fires it whenever the cooldown clears.

# "cell_idx:direction" -> summed magnitude fed to that face this sim pass.
# cell_idx 0 = anchor, 1/2 = footprint_offsets[0]/[1] - same convention as
# LanceMountTile._face_magnitudes.
var _face_magnitudes: Dictionary = {}
var _fed_packet: EnergyPacket = null
# Payload snapshot taken by check_face_gate() - survives clear_pending()
# until fire() actually runs (see LanceMountTile._armed_packet).
var _armed_packet: EnergyPacket = null

var cooldown_timer: float = 0.0
var ready_to_fire: bool = false

func _init():
	tile_type = "Orbiting Array"
	category = TileCategory.OUTPUT
	base_color = Color(0.1, 0.6, 0.8)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("OrbitingArrayTile", "weight", 12.0)

func get_footprint_size() -> int:
	return 3

# Compact 3-hex triangle rather than the Lance's 3-in-a-row line - see
# HexTile.get_footprint_shape and GarageInventoryPanel's placement/preview.
func get_footprint_shape() -> String:
	return "triangle"

func clear_pending():
	_face_magnitudes.clear()
	_fed_packet = null

# See LanceMountTile.reset_simulation_state's comment - same Timeline
# Scrubber determinism gap applies to every capital weapon that banks
# per-face energy across a simulation pass.
func reset_simulation_state() -> void:
	super.reset_simulation_state()
	_face_magnitudes.clear()
	_fed_packet = null
	ready_to_fire = false

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active:
		return []

	var cell_idx = 0
	if entry_coord and grid_position and (entry_coord.q != grid_position.q or entry_coord.r != grid_position.r):
		for i in range(footprint_offsets.size()):
			var off = footprint_offsets[i]
			if entry_coord.q == grid_position.q + off.x and entry_coord.r == grid_position.r + off.y:
				cell_idx = i + 1
				break

	# Perf audit (2026-08-01): Vector2i key instead of a concatenated string
	# per packet - Vector2i is natively hashable as a Dictionary key and this
	# is only ever read back by key/iterated, never displayed/parsed as text.
	var face_key = Vector2i(cell_idx, entry_direction)
	var prev = float(_face_magnitudes.get(face_key, 0.0))
	_face_magnitudes[face_key] = prev + packet.magnitude

	# Real production bug, found 2026-08-03 (same fix as MissileRackTile.gd's
	# identical mistake) - this called packet.clone(), which doesn't exist on
	# EnergyPacket (only .copy() does). The resulting "Invalid call" error
	# aborted process_energy() before ever reaching ready_to_fire below, so
	# this tile could never actually fire in real gameplay.
	if _fed_packet == null or packet.magnitude > _fed_packet.magnitude:
		_fed_packet = packet.copy()

	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

# Sets ready_to_fire from this pass's accumulated face data and stashes the
# firing payload - called once per recalc, right before clear_pending().
func check_face_gate():
	var face_threshold = TileStatsRegistry.get_stat("OrbitingArrayTile", "face_threshold", 10000.0)
	var required_faces = int(TileStatsRegistry.get_stat("OrbitingArrayTile", "required_faces", 6))
	var fed_faces = 0
	for k in _face_magnitudes:
		if _face_magnitudes[k] >= face_threshold:
			fed_faces += 1
	ready_to_fire = fed_faces >= required_faces
	_armed_packet = _fed_packet.copy() if (ready_to_fire and _fed_packet) else null

# Spawns the 3-projectile orbital array. Called from Mech._tick_weapon_charges
# once ready_to_fire is true and cooldown_timer has cleared - and again every
# time the cooldown clears while the build stays fed, same as the Lance.
func fire(mech) -> void:
	cooldown_timer = TileStatsRegistry.get_stat("OrbitingArrayTile", "cooldown_time", 6.0)
	if not _armed_packet or not mech:
		return

	var muzzle = mech.global_position
	var by_player = mech.get("is_player") == true
	var world = mech.get_parent()
	if not world: return

	var OrbitingProjScript = load("res://scripts/entities/OrbitingProjectile.gd")
	if not OrbitingProjScript: return

	var damage = _armed_packet.magnitude * 0.45
	var angle_step = (PI * 2.0) / 3.0

	for i in range(3):
		var proj = OrbitingProjScript.new()
		proj.global_position = muzzle
		proj.setup(mech, damage, _armed_packet.synergies.duplicate(), by_player, i * angle_step)
		world.add_child(proj)
