extends Node

# Regression harness for the search-AI fixes (Natalia: "enemy search
# patterns are slow/inefficient"):
#   A) Exhausting the expanding square ESCALATES to a frontier hop (new
#      datum 500-900px away) instead of restarting on the same stale datum
#      forever.
#   B) The escalated datum is NOT snapped back to stale last_known intel on
#      the next search tick (the redatum check keys on intel freshness now).
#   C) A genuinely fresh sighting (last_known moves > SEARCH_REDATUM_DIST)
#      still redatums the pattern onto the new intel.
#   D) A searcher making no physical progress (grinding an obstacle) skips
#      the blocked leg via stuck detection.

const MechScript = preload("res://scripts/entities/Mech.gd")
const SightAndSearchScript = preload("res://scripts/entities/SightAndSearch.gd")

func _ready():
	var world = Node2D.new()
	add_child(world)

	var enemy = MechScript.new()
	enemy.is_player = false
	enemy.combat_role = "brawler"
	world.add_child(enemy)
	enemy.set_physics_process(false) # ticked manually below
	enemy.global_position = Vector2(2000, 2000)

	var sas = SightAndSearchScript.new(enemy)
	enemy.last_known_player_pos = Vector2(2000, 2000)
	enemy._search_pos_initialized = true

	var failures = 0

	# --- A: escalation on pattern exhaustion ---
	sas._execute_search(0.05) # initializes the pattern on the datum
	var datum_before = enemy._search_datum
	for i in range(40): # far more than the 2*SEARCH_MAX_LEG_UNITS legs a full square needs
		sas._advance_search_leg()
	var hop = enemy._search_datum.distance_to(datum_before)
	print("A) datum moved %.0fpx after exhausting the square (expect within escalate hop range %.0f-%.0f-ish, NOT 0)" % [hop, sas.ESCALATE_HOP_MIN, sas.ESCALATE_HOP_MAX])
	if hop < 100.0:
		push_error("FAIL A: pattern still recentering on the same datum forever")
		failures += 1

	# --- B: no snap-back to stale intel ---
	var escalated_datum = enemy._search_datum
	sas._execute_search(0.05)
	if enemy._search_datum.distance_to(escalated_datum) > 1.0:
		push_error("FAIL B: next search tick snapped the datum back (%.0fpx) - redatum is keying on datum drift, not intel freshness" % enemy._search_datum.distance_to(escalated_datum))
		failures += 1
	else:
		print("B) escalated datum survives the next search tick (no stale-intel snap-back)")

	# --- C: fresh intel still redatums ---
	enemy.last_known_player_pos = Vector2(4000, 4000)
	sas._execute_search(0.05)
	if enemy._search_datum.distance_to(Vector2(4000, 4000)) > 1.0:
		push_error("FAIL C: fresh sighting did not redatum the pattern")
		failures += 1
	else:
		print("C) fresh sighting redatums onto new intel")

	# --- D: stuck detection skips a blocked leg ---
	var leg_before = enemy._search_leg_target
	enemy._search_stuck_timer = 0.0
	enemy._search_progress_pos = Vector2.INF
	# Mech never moves between these ticks (we never apply velocity), so the
	# second sampled interval must detect zero progress and advance the leg.
	sas._execute_search(0.05) # takes the baseline sample
	sas._execute_search(sas.SEARCH_STUCK_INTERVAL + 0.01) # no progress since baseline
	if enemy._search_leg_target == leg_before:
		push_error("FAIL D: stuck searcher never skipped its blocked leg")
		failures += 1
	else:
		print("D) stuck searcher abandoned its blocked leg")

	if failures == 0:
		print("PASS: search escalation, intel redatum, and stuck detection all behave")
	get_tree().quit(0 if failures == 0 else 1)
