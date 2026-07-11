extends Node

# Regression harness for the director "tells" (SquadDirector.get_intel_line /
# get_debrief_line): lines must come from REAL telemetry, stay silent when
# nothing was learned, and never repeat the same tell twice running.

func _ready():
	var failures = 0
	var director = load("res://scripts/ai/SquadDirector.gd").new()
	director.name = "SquadDirector"
	add_child(director)

	# 1. Fresh director: silence (nothing learned yet).
	if director.get_intel_line(5) != "":
		push_error("FAIL: intel line invented with zero telemetry")
		failures += 1
	else:
		print("1) fresh director stays silent")

	# 2. Heavy FIRE damage share -> resistance-profiling tell.
	for i in range(60):
		director.log_player_damage(20.0, "FIRE")
	var line = director.get_intel_line(5)
	if not ("Fire" in line):
		push_error("FAIL: expected a FIRE-study tell, got '%s'" % line)
		failures += 1
	else:
		print("2) resistance tell: ", line)

	# 3. Same tell isn't repeated back-to-back.
	if director.get_intel_line(6) != "":
		push_error("FAIL: identical tell repeated on the next wave")
		failures += 1
	else:
		print("3) repeat suppressed")

	# 4. Kill over-reliance -> jammer counter-doctrine tell outranks it.
	for i in range(20):
		director.log_player_kill("PIERCE")
	line = director.get_intel_line(7)
	if not ("jammer" in line.to_lower() and "Pierce" in line):
		push_error("FAIL: expected a PIERCE-jammer tell, got '%s'" % line)
		failures += 1
	else:
		print("4) counter-doctrine tell: ", line)

	# 5. Debrief fires (eventually - it's chance-gated) on a lopsided wave.
	director.note_wave_started()
	for i in range(12):
		director.log_player_kill("KINETIC")
	var debrief = ""
	for _attempt in range(50):
		debrief = director.get_debrief_line()
		if debrief != "":
			break
	if not ("12" in debrief and "Kinetic" in debrief):
		push_error("FAIL: expected a 12-Kinetic-kills debrief, got '%s'" % debrief)
		failures += 1
	else:
		print("5) debrief: ", debrief)

	# 6. Balanced wave -> no debrief ever.
	director.note_wave_started()
	for el in ["FIRE", "ICE", "KINETIC"]:
		director.log_player_kill(el)
	var silent = true
	for _attempt in range(50):
		if director.get_debrief_line() != "":
			silent = false
			break
	if not silent:
		push_error("FAIL: debrief invented for a balanced wave")
		failures += 1
	else:
		print("6) balanced wave stays silent")

	if failures == 0:
		print("PASS: director tells are truthful, gated, and non-repeating")
	get_tree().quit(0 if failures == 0 else 1)
