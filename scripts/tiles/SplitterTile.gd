class_name SplitterTile
extends HexTile

var active_faces: Array[int] = []

# Mythic Splitters gain a Resonator-style remnant boost (see ResonatorTile) -
# whatever passed through last time juices up the next packet through.
var _remnant_magnitudes: Dictionary = {}

# MYTHIC ratio tuning (Status.md re-imaginings: "assign output percentages
# instead of a forced 1:1 equal split"): per-face WEIGHTS indexed 0-5,
# normalized across the active faces at split time. Empty = legacy equal
# split (back-compat with every existing save; SaveManager's generic sweep
# persists it once set). Weights, not raw percentages, so toggling a face
# on/off never needs a re-normalization pass.
const RATIO_WEIGHT_MIN = 1.0
const RATIO_WEIGHT_MAX = 10.0
var output_ratios: Array = []

func get_ratio_weight(face: int) -> float:
	if rarity != Rarity.MYTHIC or output_ratios.size() != 6:
		return 1.0
	return clamp(float(output_ratios[face]), RATIO_WEIGHT_MIN, RATIO_WEIGHT_MAX)

func adjust_ratio_weight(face: int, delta: float):
	if output_ratios.size() != 6:
		output_ratios = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	output_ratios[face] = clamp(float(output_ratios[face]) + delta, RATIO_WEIGHT_MIN, RATIO_WEIGHT_MAX)

# Display helper for the config popup: this face's share of the total.
func get_ratio_percent(face: int) -> float:
	if not active_faces.has(face):
		return 0.0
	var total = 0.0
	for f in active_faces:
		total += get_ratio_weight(f)
	return 100.0 * get_ratio_weight(face) / max(0.001, total)

func _init():
	tile_type = "Splitter"
	category = TileCategory.ROUTER
	active_faces = [1, 5]

func reset_simulation_state() -> void:
	super.reset_simulation_state()
	_remnant_magnitudes.clear()

# Fill-paint template stamping (see HexTile.copy_config_from) - a newly
# placed Splitter inherits the origin's output faces AND ratio weights, so
# painting a line of Splitters from an existing configured one gives you a
# whole matched set instead of N separately-rolled random configs.
func copy_config_from(other: HexTile) -> void:
	if not (other is SplitterTile):
		return
	active_faces = other.active_faces.duplicate()
	output_ratios = other.output_ratios.duplicate()

func get_weight() -> float:
	return 2.0 # light - just a routing junction

func get_max_faces() -> int:
	match rarity:
		Rarity.COMMON: return 2
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 3
		Rarity.LEGENDARY: return 5
		Rarity.MYTHIC: return 6 # every face on the hex - the geometric maximum
		_: return 2

func toggle_output(direction: int):
	if active_faces.has(direction):
		if active_faces.size() > 1:
			active_faces.erase(direction)
	else:
		if active_faces.size() < get_max_faces():
			active_faces.append(direction)
		else:
			active_faces.pop_front()
			active_faces.append(direction)

func get_exit_directions(entry_direction: int = 0) -> Array[int]:
	return active_faces

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	# Mythic upgrade: doubles total throughput and behaves like a Resonator
	# too (remnant energy from the last packet boosts the next one).
	if rarity == Rarity.MYTHIC:
		if _remnant_magnitudes.size() > 0:
			for k in _remnant_magnitudes:
				packet.add_synergy(k, _remnant_magnitudes[k] * 0.8)
				_remnant_magnitudes[k] *= 0.2 # consume most of it
		for syn in packet.synergies:
			_remnant_magnitudes[syn] = packet.synergies[syn] * 0.15
		packet.amplify(2.0)

	var packets: Array[EnergyPacket] = []
	var split_count = active_faces.size()
	if split_count == 0:
		return [packet]

	# Per-face fractions: equal by default, weight-driven on a ratio-tuned
	# Mythic (get_ratio_weight returns 1.0 for everything else, so the
	# arithmetic below is the legacy equal split in that case).
	var total_weight = 0.0
	for f in active_faces:
		total_weight += get_ratio_weight(f)

	# Sequential split() calls each take a fraction of what REMAINS, so
	# face i's remaining-relative ratio is its share over the unconsumed
	# tail - the last face just keeps the remainder.
	var consumed = 0.0
	for i in range(split_count):
		var exit_dir = active_faces[i]

		if i < split_count - 1:
			var share = get_ratio_weight(exit_dir) / total_weight
			var tail_ratio = clamp(share / max(0.0001, 1.0 - consumed), 0.0001, 0.9999)
			var new_packet = packet.split(tail_ratio)
			new_packet.direction = exit_dir
			packets.append(new_packet)
			consumed += share
		else:
			packet.direction = exit_dir
			packets.append(packet)

	return packets
