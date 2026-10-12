class_name CaptureBuffs
extends RefCounted

# Temporary buffs from capturing map objectives (owner idea 2026-10-11). Each fort hold point is assigned one buff type when the
# map is generated (a pure function of its position, so a seeded map always offers the same ones) and shows it in its ring
# colour; finishing the hold grants it, on top of the salvage part. One per type (re-capturing refreshes it), at most
# MAX_ACTIVE at once (the one closest to expiring gives way). Applied as plain multipliers at the places they matter:
#   weapons  +% shot damage      (HexTile._fire_via_live_batch_pool)
#   armor    -% damage taken     (MechDamage._apply_damage_body)
#   speed    +% move speed       (MechDamage.update_status_effects)
#   regen    +% of max HP per second back (ticked here)
# All numbers are (tune).

const TYPES = ["weapons", "armor", "speed", "regen"]
const DURATION = 45.0 # seconds
const MAX_ACTIVE = 3
const MAGNITUDE = {"weapons": 0.12, "armor": 0.10, "speed": 0.12, "regen": 0.01}
const LABELS = {"weapons": "WEAPONS +12%", "armor": "ARMOR -10% DAMAGE", "speed": "SPEED +12%", "regen": "REGEN 1%/s"}
const COLORS = {"weapons": Color(1.0, 0.55, 0.25), "armor": Color(0.45, 0.7, 1.0), "speed": Color(0.5, 1.0, 0.55), "regen": Color(1.0, 0.5, 0.75)}

static func type_for_position(pos: Vector2) -> String:
	var h: int = (int(roundf(pos.x)) * 73856093) ^ (int(roundf(pos.y)) * 19349663)
	h = (h ^ (h >> 13)) & 0x7fffffff
	return TYPES[h % TYPES.size()]

# Grants `type` to the mech (refreshing it if already active). Returns false for an unknown type.
static func grant(mech: Node, type: String) -> bool:
	if not (type in TYPES) or not ("capture_buffs" in mech):
		return false
	var buffs: Dictionary = mech.capture_buffs
	if not buffs.has(type) and buffs.size() >= MAX_ACTIVE:
		var soonest = ""
		for k in buffs:
			if soonest == "" or float(buffs[k]) < float(buffs[soonest]):
				soonest = k
		buffs.erase(soonest)
	buffs[type] = DURATION
	return true

static func is_active(mech: Node, type: String) -> bool:
	return "capture_buffs" in mech and float(mech.capture_buffs.get(type, 0.0)) > 0.0

static func weapons_mult(mech: Node) -> float:
	return 1.0 + float(MAGNITUDE["weapons"]) if is_active(mech, "weapons") else 1.0

static func speed_mult(mech: Node) -> float:
	return 1.0 + float(MAGNITUDE["speed"]) if is_active(mech, "speed") else 1.0

static func damage_taken_mult(mech: Node) -> float:
	return 1.0 - float(MAGNITUDE["armor"]) if is_active(mech, "armor") else 1.0

# Once per status update: counts timers down, drops expired buffs, applies regen.
static func tick(mech: Node, delta: float) -> void:
	if not ("capture_buffs" in mech) or mech.capture_buffs.is_empty():
		return
	var buffs: Dictionary = mech.capture_buffs
	for k in buffs.keys():
		buffs[k] = float(buffs[k]) - delta
		if float(buffs[k]) <= 0.0:
			buffs.erase(k)
	if buffs.has("regen") and mech.get("is_dead") != true:
		mech.hp = minf(mech.hp + mech.max_hp * float(MAGNITUDE["regen"]) * delta, mech.max_hp)
