class_name ResonatorTile
extends HexTile

@export var boost_per_remnant: float = 1.3
var _remnant_magnitudes: Dictionary = {}

# Guaranteed baseline amplify applied on EVERY pass, not just a second pass
# that consumes remnant memory (see process_energy below).
const BASELINE_AMPLIFY = 0.15

# --- Resonator Sync (Mythic-only) -------------------------------------------
# Natalia's design: a Resonator sits at a 3-way crossing of the hex's
# opposite-face pairs (E/W, NW/SE, SW/NE - see HexCoord.get_directions()).
# Whatever synergy dominates the last packet to cross ANY one of those 3
# paths gets left behind as residue FOR THAT PATH SPECIFICALLY, with its own
# per-path dropoff counter. Any packet subsequently crossing the OTHER two
# paths can "pick up" that residue as a status-effect PROC (e.g. inflicts
# burning) - critically, this confers the EFFECT only, never the actual
# energy/magnitude of that synergy (see EnergyPacket.proc_synergies). Info
# swaps all three ways: any path can leave residue for the other two to
# read. No range limit, no throughput tax - this is meant to be the most
# rewarding tile in the game for deep, deliberate hex-grid crossings.
#
# "Dropoff" is measured in simulation steps, not real time, since the grid
# is only ever simulated once per loadout change (_recalculate_grid), not
# live during combat (see FEATURE_ROADMAP.md's key architectural fact) -
# packet.traversal_steps is the only clock that actually exists here.
const SYNC_DROPOFF_DEFAULT = 3
const SYNC_DROPOFF_MIN = 1
const SYNC_DROPOFF_MAX = 9
# Player-tunable dropoff PER TRAVERSAL PATH (Status.md queue: "manually
# tweak the Sync Dropoff independently for all three paths") - indexed by
# path id 0/1/2 (E/W, SE/NW, SW/NE). An Array rather than an int-keyed
# Dictionary so SaveManager's generic tile-prop sweep JSON round-trips it
# losslessly (JSON turns int dict keys into strings).
var sync_dropoff_per_path: Array = [SYNC_DROPOFF_DEFAULT, SYNC_DROPOFF_DEFAULT, SYNC_DROPOFF_DEFAULT]
var _path_residue: Dictionary = {} # path_id (0/1/2) -> {"synergy": int, "steps_left": int}

func get_sync_dropoff(path_id: int) -> int:
	if path_id < 0 or path_id >= sync_dropoff_per_path.size():
		return SYNC_DROPOFF_DEFAULT
	return clamp(int(sync_dropoff_per_path[path_id]), SYNC_DROPOFF_MIN, SYNC_DROPOFF_MAX)

func adjust_sync_dropoff(path_id: int, delta: int):
	if path_id < 0 or path_id >= sync_dropoff_per_path.size():
		return
	sync_dropoff_per_path[path_id] = clamp(get_sync_dropoff(path_id) + delta, SYNC_DROPOFF_MIN, SYNC_DROPOFF_MAX)

func _init():
	tile_type = "Resonator"
	category = TileCategory.PROCESSOR

func get_weight() -> float:
	return 3.0 # not too heavy - mostly resonating chambers, not dense hardware

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if rarity == Rarity.MYTHIC:
		return _process_sync(packet, entry_direction)

	# Baseline resonance (Utility-SOC: "give me a reason to use accumulators
	# / resonator effects need to be more pronounced - right now I can just
	# pipe everything into a splitter, mix it up, then push everything into
	# the weapon mount"). This USED to only pay off on a SECOND pass through
	# the same tile within one simulation (consuming the remnant left by a
	# FIRST pass) - on the much more common single-pass build, `mult`
	# stayed a flat 1.0 and the tile did nothing at all, making a plain
	# pass-through/Splitter strictly better (identical routing, zero wasted
	# opportunity cost). A guaranteed baseline amplify now applies on every
	# pass; the remnant-memory bonus still layers on top for genuinely
	# repeat/crossed traffic.
	var mult = 1.0 + (BASELINE_AMPLIFY * _get_power_multiplier())
	if _remnant_magnitudes.size() > 0:
		for k in _remnant_magnitudes:
			packet.add_synergy(k, _remnant_magnitudes[k] * 0.8)
			_remnant_magnitudes[k] *= 0.2 # consume most of it
		mult += boost_per_remnant * _get_power_multiplier()
	packet.amplify(mult)

	# Leave a remnant
	for syn in packet.synergies:
		_remnant_magnitudes[syn] = packet.synergies[syn] * 0.15

	return [packet]

# entry_direction is the face the packet entered THROUGH (see Mech.
# _simulate_grid: `(dir + 3) % 6`, i.e. already the opposite of travel
# direction). Either the entry face or the packet's own travel direction
# reduce to the same path id via %3 - E/W share 0, SE/NW share 1, SW/NE
# share 2 - so this works regardless of which of the two we read.
static func _direction_to_path(dir: int) -> int:
	return dir % 3

func _process_sync(packet: EnergyPacket, entry_direction: int) -> Array[EnergyPacket]:
	var this_path = _direction_to_path(entry_direction)

	# Pickup: any residue left on the OTHER two paths confers its status
	# effect onto this packet (proc only, no energy added) and ticks down
	# one step closer to expiring.
	for path_id in _path_residue.keys().duplicate():
		if path_id == this_path:
			continue
		var res = _path_residue[path_id]
		packet.add_proc(res.synergy, 0.5) # flat mid-strength proc - see Projectile.gd's status thresholds
		res.steps_left -= 1
		if res.steps_left <= 0:
			_path_residue.erase(path_id)

	# Deposit: this path's residue is refreshed to whatever synergy
	# currently dominates this packet (RAW carries no meaningful effect to
	# confer, so it doesn't overwrite an existing non-RAW residue on the
	# same path - a RAW pass-through shouldn't erase a live proc source).
	var dom = packet.get_dominant_synergy()
	if dom != EnergyPacket.SynergyType.RAW:
		_path_residue[this_path] = {"synergy": dom, "steps_left": get_sync_dropoff(this_path)}

	return [packet]

