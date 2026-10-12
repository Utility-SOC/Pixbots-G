class_name ElementCombos
extends RefCounted

# Enemy element doctrine: on higher difficulties a share of weapon-carrying bots are kitted with a PAIR of elements that
# actually interact, instead of the near-monoculture of Kinetic the baseline builds fall into (about 97% of enemy element
# usage in a long save). The pairs come from interactions the game already implements (see Status.md, elemental balance):
#   Shatter      Kinetic + Ice        Ice freezes and embrittles, a Kinetic hit then shatters the target and its neighbours
#   Gravity well Poison + Vortex      a Poison mine with a large Vortex share becomes a gravity well that drags and crashes bodies
#   Rend & burn  Pierce + Fire        Pierce rends (+20% damage taken) and passes through a line, Fire's burn then scales with the shot
#   Storm        Lightning + Explosion  paralysis and chaining, then splash on the locked-up targets
# Applied after the loadout is built or replayed (so it works with cached stock builds), by retargeting the weapon-feeding
# Microcore faces and Elemental Infusers, exactly where the shield counter-doctrine already edits them. Casual is untouched.
# Numbers marked (tune).

const E = EnergyPacket.SynergyType

# Chance a bot gets a combo, per difficulty (0 Casual, 1 Normal, 2 Hard, 3 top); ramps in over waves.
const CHANCE_BY_DIFFICULTY = [0.0, 0.2, 0.4, 0.6] # owner-set: Casual 0, Normal 20%, Hard 40%, top 60%
const RAMP_START_WAVE = 6
const RAMP_WAVES = 20

# element -> its interaction partner
const PARTNER = {
	E.KINETIC: E.ICE, E.ICE: E.KINETIC,
	E.POISON: E.VORTEX, E.VORTEX: E.POISON,
	E.PIERCE: E.FIRE, E.FIRE: E.PIERCE,
	E.LIGHTNING: E.EXPLOSION, E.EXPLOSION: E.LIGHTNING,
}

const COMBOS = {
	"Shatter": {"a": E.KINETIC, "b": E.ICE},
	"Gravity well": {"a": E.POISON, "b": E.VORTEX},
	"Rend & burn": {"a": E.PIERCE, "b": E.FIRE},
	"Storm": {"a": E.LIGHTNING, "b": E.EXPLOSION},
}

# Which combos suit which role (roles that carry no real weapons get none).
const ROLE_COMBOS = {
	"sniper": ["Rend & burn", "Shatter"],
	"brawler": ["Shatter", "Storm", "Gravity well"],
	"ambusher": ["Gravity well", "Storm"],
	"flamethrower": ["Rend & burn"],
	"scout": ["Storm", "Shatter"],
}

static func chance(difficulty: int, wave: int) -> float:
	var base = CHANCE_BY_DIFFICULTY[clampi(difficulty, 0, CHANCE_BY_DIFFICULTY.size() - 1)]
	var ramp = clampf(float(wave - RAMP_START_WAVE) / float(RAMP_WAVES), 0.0, 1.0)
	return base * ramp

# The combo (a Dictionary {name, a, b}) or {} for none. `roll_use` and `roll_pick` are 0..1 rolls from the caller's seeded
# stream. `counter_element` (>= 0) is the element the shield counter-doctrine already chose; the combo then builds around it
# when it has a partner, so a bot can counter your shield AND combo.
static func roll(role: String, difficulty: int, wave: int, roll_use: float, roll_pick: float, counter_element: int = -1) -> Dictionary:
	if not ROLE_COMBOS.has(role) or roll_use >= chance(difficulty, wave):
		return {}
	if counter_element >= 0 and PARTNER.has(counter_element):
		return {"name": "Counter combo", "a": counter_element, "b": PARTNER[counter_element]}
	var names: Array = ROLE_COMBOS[role]
	var name: String = names[mini(int(roll_pick * names.size()), names.size() - 1)]
	var c: Dictionary = COMBOS[name]
	return {"name": name, "a": c["a"], "b": c["b"]}

# How strongly the pair replaces a weapon's own element mix (0 = untouched, 1 = exactly the pair).
const RETINT_STRENGTH = 0.7 # (tune) the bot keeps some of what its build made, so combos do not erase every other element
# Weapons alternate which element leads so a bot's guns are not identical.
const LEAD_SHARE = 0.6

# Reshapes a finished weapon packet's elements toward the combo pair, keeping its total energy. Both elements end up well
# above the 20% share a Poison+Vortex well and a Shatter need.
static func retint_synergies(synergies: Dictionary, combo: Dictionary, weapon_index: int) -> Dictionary:
	if combo.is_empty():
		return synergies
	var total = 0.0
	for k in synergies:
		total += float(synergies[k])
	if total <= 0.0:
		return synergies
	var lead = int(combo["a"]) if weapon_index % 2 == 0 else int(combo["b"])
	var other = int(combo["b"]) if weapon_index % 2 == 0 else int(combo["a"])
	var out := {}
	for k in synergies:
		out[k] = float(synergies[k]) * (1.0 - RETINT_STRENGTH)
	out[lead] = float(out.get(lead, 0.0)) + total * RETINT_STRENGTH * LEAD_SHARE
	out[other] = float(out.get(other, 0.0)) + total * RETINT_STRENGTH * (1.0 - LEAD_SHARE)
	return out

# Share of a counter-tuned enemy shield's energy that is retinted to the element it counters, by difficulty (Casual
# keeps the old loose tuning).
const SHIELD_COUNTER_STRENGTH = [0.5, 0.7, 0.85, 1.0]
# Extra odds, by difficulty, that a bot commits to tuning its shield against what the player leans on.
const SHIELD_COUNTER_CHANCE_BONUS = [0.0, 0.05, 0.12, 0.2]

static func shield_counter_strength(difficulty: int) -> float:
	return SHIELD_COUNTER_STRENGTH[clampi(difficulty, 0, SHIELD_COUNTER_STRENGTH.size() - 1)]

static func shield_counter_chance_bonus(difficulty: int) -> float:
	return SHIELD_COUNTER_CHANCE_BONUS[clampi(difficulty, 0, SHIELD_COUNTER_CHANCE_BONUS.size() - 1)]

# Moves `strength` of the shield's energy onto `element`, keeping the total. Pure.
static func retint_shield(synergies: Dictionary, element: int, strength: float) -> Dictionary:
	var total = 0.0
	for k in synergies:
		total += float(synergies[k])
	var out := {}
	for k in synergies:
		out[k] = float(synergies[k]) * (1.0 - strength)
	out[element] = float(out.get(element, 0.0)) + total * strength
	return out

# Called by MechGridSim once the weapons are final (so it also survives every mid-fight grid recalculation).
static func retint_weapons(mech: Node) -> void:
	var combo: Dictionary = mech.element_combo
	if combo.is_empty():
		return
	var i = 0
	for data in mech.precalculated_weapons:
		data.packet.synergies = retint_synergies(data.packet.synergies, combo, i)
		i += 1
