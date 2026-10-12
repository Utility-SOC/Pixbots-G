extends Node

# StatusCounterHints: only notable CC elements with a counter tile produce a hint, thin telemetry stays silent, biggest first.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("no telemetry, no hints", StatusCounterHints.hints({}).is_empty())
	_check("thin telemetry stays silent", StatusCounterHints.hints({"LIGHTNING": 100.0}).is_empty())
	_check("RAW does not count toward the total", StatusCounterHints.hints({"RAW": 1e9, "LIGHTNING": 100.0}).is_empty())
	var h = StatusCounterHints.hints({"KINETIC": 8000.0, "LIGHTNING": 2000.0})
	_check("a 20% Lightning share names the Shock Guard", h.size() == 1 and "Shock Guard" in h[0] and "paralysis" in h[0] and "20%" in h[0])
	_check("a share under the threshold is not mentioned", StatusCounterHints.hints({"KINETIC": 9000.0, "LIGHTNING": 1000.0}).is_empty())
	var both = StatusCounterHints.hints({"KINETIC": 4000.0, "ICE": 2000.0, "LIGHTNING": 4000.0})
	_check("biggest share first, one line per element", both.size() == 2 and "Shock Guard" in both[0] and "Freeze Guard" in both[1])
	_check("elements with no counter tile are never listed", StatusCounterHints.hints({"KINETIC": 5000.0, "PIERCE": 5000.0}).is_empty())
	print("StatusCounterHintsCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
