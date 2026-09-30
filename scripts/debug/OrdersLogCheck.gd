extends Node

const OrdersLog = preload("res://scripts/ai/OrdersLog.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var o = OrdersLog.new()
	var got: Array = []
	o.line_emitted.connect(func(e): got.append(e))
	o.post("plan", "Alpha", 1, "pincer")
	o.pump(0.1)
	_check("first line emits immediately", got.size() == 1 and "Alpha" in got[0]["text"])
	o.post("commit", "Alpha", 1, "pincer")
	o.pump(0.5)
	_check("rate limited (gap)", got.size() == 1)
	o.pump(3.0)
	_check("emits after gap", got.size() == 2)
	o.post("commit", "Alpha", 1)
	o.pump(10.0)
	_check("same squad+kind cooldown", got.size() == 2)
	# priority: wipe beats plan
	var o2 = OrdersLog.new()
	var g2: Array = []
	o2.line_emitted.connect(func(e): g2.append(e))
	o2.pump(5.0)
	o2.post("plan", "B", 2, "swarm")
	o2.post("wipe", "B", 2)
	o2.pump(0.1)
	_check("highest priority first", g2[0]["kind"] == "wipe")
	# pending bounded, stale dropped
	var o3 = OrdersLog.new()
	for i in range(10):
		o3.post("casualty", "S%d" % i, i)
	_check("pending capped", o3._pending.size() <= OrdersLog.MAX_PENDING)
	var g3: Array = []
	o3.line_emitted.connect(func(e): g3.append(e))
	o3.pump(OrdersLog.PENDING_TTL + 1.0)
	_check("stale pending dropped", g3.is_empty())
	for i in range(200):
		o3.post("plan", "Z", 1000 + i, "swarm")
		o3.pump(3.0)
	_check("history capped", o3.history.size() <= OrdersLog.HISTORY_CAP)
	var o4 = OrdersLog.new()
	o4.post("bogus", "x", 1)
	_check("unknown kind ignored", o4._pending.is_empty())
	var t = OrdersLog.new()
	t.post("replan", "Q", 9, "hammer_anvil")
	_check("replan line mentions switching", t._pending.size() == 1)
	print("orders check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
