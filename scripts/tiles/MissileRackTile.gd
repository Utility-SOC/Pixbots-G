class_name MissileRackTile
extends HexTile

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

	# Perf audit (2026-08-01): int key directly, no string allocation per
	# packet - only ever read back by key, never displayed/parsed as text.
	var face_key = entry_direction
	var prev = float(_face_magnitudes.get(face_key, 0.0))
	_face_magnitudes[face_key] = prev + packet.magnitude

	# Real production bug, found 2026-08-03 while building a regression check
	# for the face_key change above: this called packet.clone(), which
	# doesn't exist on EnergyPacket (only .copy() does - see LanceMountTile's
	# own identical _fed_packet assignment for the established convention).
	# The resulting "Invalid call" error aborted process_energy() BEFORE
	# reaching the ready_to_fire gate below on every call - meaning this
	# tile could never actually fire in real gameplay, the same class of
	# bug as the earlier "Lance Beam can never fire" fix.
	if _fed_packet == null or packet.magnitude > _fed_packet.magnitude:
		_fed_packet = packet.copy()

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
