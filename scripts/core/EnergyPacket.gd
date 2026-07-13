class_name EnergyPacket
extends RefCounted

enum SynergyType {
	RAW, FIRE, ICE, LIGHTNING, VORTEX, POISON, EXPLOSION, KINETIC, PIERCE, VAMPIRIC
}

# These are project-defined design limits, not an engine constraint -
# nothing in Godot caps a float. Raised from the original 30,000/100 to
# give real headroom for stacked-Accumulator "capacitor bank" volleys
# (see AccumulatorTile.gd / Mech._get_adjacent_accumulator_bonus) to keep
# growing instead of plateauing well short of what a big investment should
# feel like. Defined once here (previously the 30000 cap was ALSO
# duplicated as a literal inside amplify() below - a classic way for two
# copies of the same limit to quietly drift apart) so raising it again
# later is a one-line change.
const MAX_MAGNITUDE = 150000.0
const MAX_CHARGE_REQUIRED = 500.0 # ~100s at base fire rate - a genuinely long charge-up for the biggest builds

var magnitude: float = 100.0 :
	set(val):
		magnitude = min(val, MAX_MAGNITUDE)
var synergies: Dictionary = {}

# Resonator Sync (Mythic Resonator only - see ResonatorTile.gd): a
# synergy_type -> strength (0..1-ish, same scale as Projectile.gd's `ratios`)
# map of status-effect PROCS this packet is carrying that did NOT come from
# its own actual elemental composition. A packet with 100% RAW magnitude can
# still carry a "FIRE" entry here picked up from a Resonator's crossed sync
# path, which Projectile.gd applies as the burning status on impact - but
# contributes nothing to damage, color, or dominant-synergy calculations.
# Deliberately separate from `synergies` so "confer effects, not energy" -
# the whole point of Sync - can't accidentally leak into damage math.
var proc_synergies: Dictionary = {}

func add_proc(synergy_type: int, strength: float):
	proc_synergies[synergy_type] = max(proc_synergies.get(synergy_type, 0.0), strength)

var position: HexCoord = null
var direction: int = 0
var is_active: bool = true
var trigger_key: String = "None"
# Set true only at the two bank-charge-dump fire sites (Mech._tick_weapon_
# charges' AI auto-release, PlayerController.fire_charged's hold-1/2/3) -
# the projectile reads this for an exclusive bonus a same-magnitude
# mixed-splitter shot can't reach any other way (see Projectile.gd), so
# Accumulator banking is a real categorical choice, not just a flat
# magnitude buff achievable by piling packets into a splitter. Deliberately
# NOT carried through copy() - set explicitly at the fire site on the
# already-copied packet, since it describes how THIS shot is being
# released, not a property of the packet's own composition.
var is_banked_shot: bool = false
# 1.0 = no penalty. Set below 1.0 by AccumulatorTile.process_energy():
# normal (mouse) fire of an accumulator-fed weapon pays this small
# convenience tax, which shrinks as accumulator rarity/level rises.
# Manual key-dumps (hold 1/2/3 + fire) always deliver full value.
var accumulator_quality: float = 1.0
# Pumped by Mythic Amplifiers in AoE-focus mode: each point grows the
# projectile's visual scale and explosion radius (see Projectile.gd).
var aoe_bonus: float = 0.0
# Accumulated by AccumulatorTile.process_energy WITHOUT modifying the
# packet itself: the through-flowing packet stays "as if there were no
# accumulator" (that's the mouse-fired shot), and these multipliers are
# used at mount collection to build the SEPARATE big charged shot that
# fires only via its 1/2/3 key. See Mech._recalculate_grid.
var acc_charge_mult: float = 1.0
var acc_damage_mult: float = 1.0
var traversal_steps: int = 0
var charge_required: float = 1.0 :
	set(val):
		charge_required = min(val, MAX_CHARGE_REQUIRED)

func _init(_magnitude: float = 100.0, _position: HexCoord = null):
	magnitude = _magnitude
	position = _position
	synergies[SynergyType.RAW] = magnitude

func get_dominant_synergy() -> int:
	if synergies.is_empty():
		return SynergyType.RAW
	var max_syn = SynergyType.RAW
	var max_val = -1.0
	for k in synergies:
		if synergies[k] > max_val:
			max_val = synergies[k]
			max_syn = k
	return max_syn

func total_synergy_magnitude() -> float:
	var total: float = 0.0
	for v in synergies.values():
		total += v
	return total

func add_synergy(synergy_type: int, amount: float):
	var current = synergies.get(synergy_type, 0.0)
	synergies[synergy_type] = current + amount
	magnitude += amount
	_sync_synergies_to_magnitude()

func has_synergy(synergy_type: int, min_percentage: float = 0.0) -> bool:
	if magnitude == 0: return false
	var perc = synergies.get(synergy_type, 0.0) / magnitude
	return perc >= min_percentage

func convert_synergy(from_type: int, to_type: int, percentage: float):
	if not synergies.has(from_type):
		return
	
	var amount = synergies[from_type] * percentage
	synergies[from_type] -= amount
	
	if synergies[from_type] <= 0:
		synergies.erase(from_type)
		
	synergies[to_type] = synergies.get(to_type, 0.0) + amount
	
func amplify(multiplier: float):
	var new_mag = magnitude * multiplier
	if new_mag > MAX_MAGNITUDE and magnitude > 0:
		multiplier = MAX_MAGNITUDE / magnitude
	elif magnitude <= 0:
		multiplier = 1.0
		
	magnitude *= multiplier
	for key in synergies:
		synergies[key] *= multiplier
	_sync_synergies_to_magnitude()

func split(ratio: float) -> EnergyPacket:
	if ratio <= 0.0 or ratio >= 1.0:
		push_error("Split ratio must be between 0 and 1")
		return null
	
	var new_packet = EnergyPacket.new(magnitude * ratio, position)
	new_packet.direction = direction
	new_packet.charge_required = charge_required
	new_packet.accumulator_quality = accumulator_quality
	new_packet.aoe_bonus = aoe_bonus
	new_packet.acc_charge_mult = acc_charge_mult
	new_packet.acc_damage_mult = acc_damage_mult
	new_packet.synergies.clear()
	for k in synergies:
		new_packet.synergies[k] = synergies[k] * ratio
	new_packet.proc_synergies = proc_synergies.duplicate()

	magnitude *= (1.0 - ratio)
	for k in synergies:
		synergies[k] *= (1.0 - ratio)

	return new_packet

func copy() -> EnergyPacket:
	var new_packet = EnergyPacket.new(magnitude, position)
	new_packet.direction = direction
	new_packet.position = position
	new_packet.is_active = is_active
	new_packet.trigger_key = trigger_key
	new_packet.synergies = synergies.duplicate()
	new_packet.proc_synergies = proc_synergies.duplicate()
	new_packet.traversal_steps = traversal_steps
	new_packet.charge_required = charge_required
	new_packet.accumulator_quality = accumulator_quality
	new_packet.aoe_bonus = aoe_bonus
	new_packet.acc_charge_mult = acc_charge_mult
	new_packet.acc_damage_mult = acc_damage_mult
	return new_packet

func merge(other: EnergyPacket):
	magnitude += other.magnitude
	# Merged streams pay the worse of the two convenience taxes
	accumulator_quality = min(accumulator_quality, other.accumulator_quality)
	aoe_bonus = max(aoe_bonus, other.aoe_bonus)
	# Strongest accumulator stack on any merged path defines the big shot
	acc_charge_mult = max(acc_charge_mult, other.acc_charge_mult)
	acc_damage_mult = max(acc_damage_mult, other.acc_damage_mult)
	for k in other.synergies:
		synergies[k] = synergies.get(k, 0.0) + other.synergies[k]
	for k in other.proc_synergies:
		proc_synergies[k] = max(proc_synergies.get(k, 0.0), other.proc_synergies[k])
	_sync_synergies_to_magnitude()

# `magnitude` has a clamping setter (capped at MAX_MAGNITUDE), but the
# `synergies` dict is just plain float values with no such cap - add_synergy()
# and merge() above both add directly into it. On a normal single call that's
# fine (both grow together), but across the up to 100 routing steps a packet
# can take in Mech._simulate_grid() - especially in an Amplifier/Resonator
# feedback loop - repeated adds/merges kept inflating `synergies` even after
# `magnitude` had long since saturated at its cap, since nothing ever pulled
# the dict back down to match. The two totally decoupled over enough loop
# iterations: real damage (which reads `magnitude`) stayed sane, but the
# Garage's per-element OUTPUT stats (which sum `synergies`) showed absurd
# ~1e21-scale numbers. Rescales the whole dict proportionally back down
# whenever it's grown past what `magnitude` actually represents, so the two
# can never drift apart no matter how many loop iterations feed into this.
func _sync_synergies_to_magnitude():
	var total = 0.0
	for v in synergies.values():
		total += v
	if total <= 0.0:
		return
	# Small tolerance so ordinary floating-point rounding noise doesn't
	# trigger a rescale (and the sqrt-of-nothing edge case above already
	# bails out when there's nothing to rescale).
	if total > magnitude * 1.0001:
		var factor = magnitude / total
		for k in synergies:
			synergies[k] *= factor

func _to_string() -> String:
	return "EnergyPacket(mag: " + str(magnitude) + ")"

# Canonical synergy id <-> element-name-string conversion. Order MUST match
# the SynergyType enum above. These strings are the game's element ids in
# damage/telemetry paths (Mech.apply_damage's `element`, SquadDirector's
# usage dicts, SHIELD_COUNTER_WHEEL keys...) - before these helpers existed,
# five call sites kept hand-written copies of this table and three of them
# had silently drifted onto DIFFERENT numberings, breaking the shield
# rock-paper-scissors and the director's shield counter-doctrine.
const SYNERGY_NAMES = ["RAW", "FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "EXPLOSION", "KINETIC", "PIERCE", "VAMPIRIC"]

static func element_name(id: int) -> String:
	if id >= 0 and id < SYNERGY_NAMES.size():
		return SYNERGY_NAMES[id]
	return "RAW"

# Returns the SynergyType id, or -1 for an unknown string ("RAW" returns 0).
static func element_id(name: String) -> int:
	return SYNERGY_NAMES.find(name)

static func get_color_for_synergy(synergy: int) -> Color:
	match synergy:
		SynergyType.RAW: return Color(1, 1, 1) # White
		SynergyType.FIRE: return Color(1, 0.4, 0) # Orange/Red
		SynergyType.ICE: return Color(0, 0.8, 1) # Cyan
		SynergyType.LIGHTNING: return Color(1, 1, 0) # Yellow
		SynergyType.VORTEX: return Color(0.6, 0, 1) # Purple
		SynergyType.POISON: return Color(0, 1, 0.2) # Green
		SynergyType.EXPLOSION: return Color(1, 0.2, 0.2) # Bright Red
		SynergyType.KINETIC: return Color(0.7, 0.7, 0.8) # Grey
		SynergyType.PIERCE: return Color(0.9, 0.9, 1.0) # Bright Silver
		SynergyType.VAMPIRIC: return Color(0.8, 0, 0.3) # Crimson
	return Color(1, 1, 1)

static func get_color_blend(syn_dict: Dictionary) -> Color:
	if syn_dict.is_empty(): return Color(1, 1, 1)
	var total = 0.0
	for v in syn_dict.values(): total += v
	if total <= 0: return Color(1, 1, 1)
	
	var r = 0.0; var g = 0.0; var b = 0.0
	for k in syn_dict.keys():
		var weight = syn_dict[k] / total
		var c = get_color_for_synergy(k)
		r += c.r * weight
		g += c.g * weight
		b += c.b * weight
	
	return Color(r, g, b)
