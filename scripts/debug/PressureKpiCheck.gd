extends Node

# The pressure KPIs summarise a wave correctly: median squad lifetime, share of squads with non-zero fitness, damage taken as a
# share of effective HP; an empty wave is safe.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var k = SquadDirector.kpi_summary([5.0, 40.0, 12.0], 2, 3, 300.0, 1000.0)
	_check("median lifetime is the middle value (%.0f)" % k["median_lifetime_s"], k["median_lifetime_s"] == 12.0)
	_check("one of three squads scored (%.2f)" % k["nonzero_fitness_share"], absf(k["nonzero_fitness_share"] - 1.0 / 3.0) < 0.001)
	_check("damage taken is a share of effective HP", is_equal_approx(k["damage_taken_share"], 0.3))
	var e = SquadDirector.kpi_summary([], 0, 0, 0.0, 0.0)
	_check("an empty wave does not divide by zero", e["squads"] == 0 and e["median_lifetime_s"] == 0.0 and e["nonzero_fitness_share"] == 0.0)
	var d = SquadDirector.new()
	add_child(d)
	d.note_squad_result(10.0, 0.0)
	d.note_squad_result(20.0, 55.0)
	d._kpi_flush(100.0, 1000.0, 7)
	_check("the director flushes a wave and resets (%s)" % str(d.last_kpi), d.last_kpi["squads"] == 2 and d.last_kpi["wave"] == 7 and d._kpi_squads == 0)
	print("PressureKpiCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
