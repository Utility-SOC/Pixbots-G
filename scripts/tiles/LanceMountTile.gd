class_name LanceMountTile
extends HexTile

# The "lance phaser" weapon mount (Utility-SOC, referencing the Enterprise-D
# phaser lance from TNG "Best of Both Worlds"): a single ultra-long-range
# collimated beam that lingers and leaves a damage-residue field behind it
# - like cooling lava. The first (and so far only) multi-cell tile in the
# game - see HexTile.footprint_offsets and HexGridComponent.add_tile/
# remove_tile/get_all_tiles for how a 3-hex straight-line footprint is
# stored/deduped as one logical tile. footprint_offsets itself is assigned
# at PLACEMENT time (see GarageInventoryPanel._drop_footprint_tile), not
# here - a freshly-created Lance starts with no footprint until placed.
#
# Gated on REQUIRED_FACES of its external faces each carrying >=
# FACE_THRESHOLD energy this simulation pass - not a live per-frame check,
# since the grid only ever simulates once per loadout change (see
# FEATURE_ROADMAP.md's key architectural fact: "the energy grid is NOT
# simulated live during combat"). Doesn't fire on mouse/key input like a
# normal Weapon Mount - it's an automatic, heavy-commitment weapon: once
# fed, it fires itself the moment its cooldown clears (see
# Mech._tick_weapon_charges).

const FACE_THRESHOLD = 10000.0
const REQUIRED_FACES = 6
const COOLDOWN_TIME = 10.0
const RESIDUE_LIFETIME = 25.0
const BEAM_RANGE = 6000.0

# "cell_idx:direction" -> summed magnitude fed to that face this sim pass.
# cell_idx 0 = anchor, 1/2 = footprint_offsets[0]/[1] - the same physical
# direction on a DIFFERENT one of the 3 cells is a genuinely distinct face.
var _face_magnitudes: Dictionary = {}
# Highest-magnitude packet seen this pass - supplies the beam's damage/
# element split when it fires.
var _fed_packet: EnergyPacket = null

var cooldown_timer: float = 0.0
var ready_to_fire: bool = false

func _init():
	tile_type = "Lance Mount"
	category = TileCategory.OUTPUT

func get_weight() -> float:
	return 14.0 # a three-hex capital weapon - heaviest tile in the game after the Core

func get_footprint_size() -> int:
	return 3

# Called once per _recalculate_grid() after simulation, mirroring
# WeaponMountTile.clear_pending()'s "consume, then reset for next time"
# pattern (see Mech._recalculate_grid).
func clear_pending():
	_face_magnitudes.clear()
	_fed_packet = null

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
	var face_key = "%d:%d" % [cell_idx, entry_direction]
	_face_magnitudes[face_key] = _face_magnitudes.get(face_key, 0.0) + packet.magnitude

	if _fed_packet == null or packet.magnitude > _fed_packet.magnitude:
		_fed_packet = packet.copy()

	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

# Sets ready_to_fire from this pass's accumulated face data - called once
# per recalc, right before clear_pending() resets for the next one.
func check_face_gate():
	var fed_faces = 0
	for k in _face_magnitudes:
		if _face_magnitudes[k] >= FACE_THRESHOLD:
			fed_faces += 1
	ready_to_fire = fed_faces >= REQUIRED_FACES

# Fires the beam + spawns the lingering damage-residue field. Called from
# Mech._tick_weapon_charges once ready_to_fire is true and cooldown_timer
# has cleared. mech: the owning Mech (for muzzle position/direction/side).
func fire(mech) -> void:
	cooldown_timer = COOLDOWN_TIME
	if not _fed_packet or not mech:
		return

	var muzzle = get_muzzle_position(mech)
	var aim_pos = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var dir = (aim_pos - muzzle).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)
	var end_pos = muzzle + dir * BEAM_RANGE

	var damage = _fed_packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()
	var by_player = mech.get("is_player") == true

	var world = mech.get_parent()
	if not world:
		return

	var LanceBeamScript = load("res://scripts/attacks/LanceBeam.gd")
	var beam = LanceBeamScript.new()
	beam.setup(muzzle, end_pos, damage, _fed_packet.synergies.duplicate(), by_player, mech, RESIDUE_LIFETIME)
	world.add_child(beam)
