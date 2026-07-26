class_name OrbitingArrayTile
extends HexTile

# A 3-hex rotatable triangle capital weapon tile (requires all 6 external faces
# carrying >= 10,000 energy). When fired, spawns OrbitingProjectiles that enter
# synergy-driven orbital trajectories around the bot (Kinetic/Pierce fast elliptical,
# Vortex bezier-blob, Lightning lashing bolts, Poison hazard trails).

var _face_magnitudes: Dictionary = {}
var _fed_packet: EnergyPacket = null

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

func clear_pending():
	_face_magnitudes.clear()
	_fed_packet = null

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active:
		return []

	var cell_idx = 0
	if grid_position and entry_coord:
		if entry_coord.equals(grid_position):
			cell_idx = 0
		else:
			for i in range(footprint_offsets.size()):
				var off = footprint_offsets[i]
				var h = HexCoord.new(grid_position.q + off.q, grid_position.r + off.r)
				if entry_coord.equals(h):
					cell_idx = i + 1
					break

	var face_key = str(cell_idx) + ":" + str(entry_direction)
	var prev = float(_face_magnitudes.get(face_key, 0.0))
	_face_magnitudes[face_key] = prev + packet.magnitude

	if _fed_packet == null or packet.magnitude > _fed_packet.magnitude:
		_fed_packet = packet.clone()

	var face_threshold = TileStatsRegistry.get_stat("OrbitingArrayTile", "face_threshold", 10000.0)
	var required_faces = int(TileStatsRegistry.get_stat("OrbitingArrayTile", "required_faces", 6))
	var fed_count = 0
	for fk in _face_magnitudes:
		if float(_face_magnitudes[fk]) >= face_threshold:
			fed_count += 1

	if fed_count >= required_faces:
		ready_to_fire = true

	return []

func update_cooldown(delta: float):
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			cooldown_timer = 0.0

func can_fire() -> bool:
	return ready_to_fire and cooldown_timer <= 0.0 and _fed_packet != null

func fire(mech) -> void:
	ready_to_fire = false
	cooldown_timer = TileStatsRegistry.get_stat("OrbitingArrayTile", "cooldown_time", 6.0)
	if not _fed_packet or not mech:
		return

	var muzzle = mech.global_position
	var by_player = mech.get("is_player") == true
	var world = mech.get_parent()
	if not world: return

	var OrbitingProjScript = load("res://scripts/entities/OrbitingProjectile.gd")
	if not OrbitingProjScript: return

	var damage = _fed_packet.magnitude * 0.45
	var angle_step = (PI * 2.0) / 3.0

	for i in range(3):
		var proj = OrbitingProjScript.new()
		proj.global_position = muzzle
		proj.setup(mech, damage, _fed_packet.synergies.duplicate(), by_player, i * angle_step)
		world.add_child(proj)
