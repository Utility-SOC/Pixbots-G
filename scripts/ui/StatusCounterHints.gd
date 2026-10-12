class_name StatusCounterHints
extends RefCounted

# War Room "the AI's read" hint: when enemies lean on an element whose crowd-control status has a counter tile, say so.
# (Shock Guard answers Lightning's paralysis; owner asked for a paralysis counter, and it already exists, it just was not
# surfaced anywhere but the Garage tooltip.) Pure, so it is testable without the menu.

const COUNTERS = {
	"LIGHTNING": {"tile": "Shock Guard", "status": "paralysis"},
	"ICE": {"tile": "Freeze Guard", "status": "freezing"},
	"EXPLOSION": {"tile": "Stun Guard", "status": "concussion"},
}
const MIN_SHARE = 0.15 # (tune) of the enemies' elemental (non-RAW) damage
const MIN_TOTAL = 500.0 # ignore thin telemetry

# bot_element_usage: element NAME -> damage dealt by enemies. Returns display lines, biggest share first.
static func hints(bot_element_usage: Dictionary) -> Array:
	var total = 0.0
	for k in bot_element_usage:
		if str(k) != "RAW":
			total += float(bot_element_usage[k])
	if total < MIN_TOTAL:
		return []
	var rows: Array = []
	for el in COUNTERS:
		var share = float(bot_element_usage.get(el, 0.0)) / total
		if share >= MIN_SHARE:
			rows.append([share, el])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for r in rows:
		var c: Dictionary = COUNTERS[r[1]]
		out.append("  %s is %.0f%% of what enemies hit you with: a %s shortens %s (up to 90%%, fed by the energy you route into it)." % [str(r[1]).capitalize(), r[0] * 100.0, c["tile"], c["status"]])
	return out
