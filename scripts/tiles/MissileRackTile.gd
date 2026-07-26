# Salvo Missile Rack weapon tile: banks incoming energy and launches
# a salvo of indirect mortar/missile shells delivered in a spread around
# the target aim point. Damage and salvo size scale with tile level and rarity.

var _face_magnitudes: Dictionary = {}
var _fed_packet: EnergyPacket = null

var cooldown_timer: float = 0.0
var ready_to_fire: bool = false

func _init():
	tile_type = "Missile Rack"
	category = TileCategory.OUTPUT
	base_color = Color(0.45, 0.4, 0.28)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("MissileRackTile", "weight", 7.0)

func clear_pending():
	_face_magnitudes.clear()
	_fed_packet = null

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active:
		return []

	var face_key = str(entry_direction)
	var prev = float(_face_magnitudes.get(face_key, 0.0))
	_face_magnitudes[face_key] = prev + packet.magnitude

	if _fed_packet == null or packet.magnitude > _fed_packet.magnitude:
		_fed_packet = packet.clone()

	var threshold = TileStatsRegistry.get_stat("MissileRackTile", "feed_threshold", 2000.0)
	if packet.magnitude >= threshold or _fed_packet.magnitude >= threshold:
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
	cooldown_timer = TileStatsRegistry.get_stat("MissileRackTile", "cooldown_time", 4.5)
	if not _fed_packet or not mech:
		return

	var muzzle = mech.global_position
	var aim_pos = mech.get("last_aim_position") if "last_aim_position" in mech else muzzle + Vector2(0, -200)
	var by_player = mech.get("is_player") == true
	var world = mech.get_parent()
	if not world: return

	var MortarShellScript = load("res://scripts/attacks/MortarShell.gd")
	if not MortarShellScript: return

	# Salvo count scales with rarity and tile level (+10% power/salvo bonus per level)
	var salvo_count = 3 + rarity + int(level / 3)
	var base_dmg = (_fed_packet.magnitude * _get_power_multiplier() * 0.3) / salvo_count

	for i in range(salvo_count):
		var offset = Vector2(randf_range(-60, 60), randf_range(-60, 60))
		var target = aim_pos + offset
		var flight_time = 0.6 + i * 0.15
		var shell = MortarShellScript.new()
		shell.setup(muzzle, target, flight_time, base_dmg, _fed_packet.synergies.duplicate(), by_player, mech)
		world.add_child(shell)
