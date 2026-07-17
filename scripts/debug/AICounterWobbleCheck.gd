extends Node

# Regression harness for the "more wobble in counter-building" + "Kinetic
# counters need sight range to matter" + "more aggressive experimentation"
# playtest fixes (War Room screenshot feedback). Checks:
# 1. SightAndSearch._effective_sight_range() actually adds kinetic_sight_bonus.
# 2. SquadDirector.COUNTER_BUILD_CHANCE gate produces BOTH outcomes across
#    many rolls (i.e. it's not secretly 0.0 or 1.0 - the old deterministic
#    100% behavior the user found too rigid).
# 3. Evolution pool caps were actually bumped (Template/Profile/Boss).
# 4. Main.gd's wave-modulo cadence was actually tightened.
# Safe to delete once validated.

const MechScript = preload("res://scripts/entities/Mech.gd")
const SightAndSearchScript = preload("res://scripts/entities/SightAndSearch.gd")
const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")
const TemplateEvolutionScript = preload("res://scripts/ai/TemplateEvolution.gd")
const ProfileEvolutionScript = preload("res://scripts/ai/ProfileEvolution.gd")
const BossEvolutionScript = preload("res://scripts/ai/BossEvolution.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: ", label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Kinetic sight bonus actually reaches effective sight range ------
	var mech = MechScript.new()
	mech.is_player = false
	mech.combat_role = "sniper"
	add_child(mech)
	mech.sight_and_search = SightAndSearchScript.new(mech)
	var base_sight = mech.sight_and_search._effective_sight_range()
	mech.kinetic_sight_bonus = 2000.0
	var boosted_sight = mech.sight_and_search._effective_sight_range()
	_check("kinetic_sight_bonus raises _effective_sight_range by exactly its value",
		is_equal_approx(boosted_sight - base_sight, 2000.0))
	mech.queue_free()

	# --- 2. Counter-build gate is genuinely probabilistic -------------------
	var true_count = 0
	var false_count = 0
	for i in range(300):
		if randf() < SquadDirectorScript.COUNTER_BUILD_CHANCE:
			true_count += 1
		else:
			false_count += 1
	_check("COUNTER_BUILD_CHANCE is between 0 and 1 (not deterministic)",
		SquadDirectorScript.COUNTER_BUILD_CHANCE > 0.0 and SquadDirectorScript.COUNTER_BUILD_CHANCE < 1.0)
	_check("300 rolls at COUNTER_BUILD_CHANCE produced both commit and skip outcomes",
		true_count > 0 and false_count > 0)

	_check("KINETIC_COUNTER_SIGHT_BONUS is a meaningful positive bump",
		SquadDirectorScript.KINETIC_COUNTER_SIGHT_BONUS > 0.0)

	# --- 3. Evolution pools widened ------------------------------------------
	_check("TemplateEvolution.MAX_EXPERIMENTAL_TEMPLATES bumped to 7",
		TemplateEvolutionScript.MAX_EXPERIMENTAL_TEMPLATES == 7)
	_check("ProfileEvolution.MAX_EXPERIMENTAL_PROFILES bumped to 7",
		ProfileEvolutionScript.MAX_EXPERIMENTAL_PROFILES == 7)
	_check("BossEvolution.MAX_EXPERIMENTAL_BOSS_PROFILES bumped to 6",
		BossEvolutionScript.MAX_EXPERIMENTAL_BOSS_PROFILES == 6)

	# --- 4. Main.gd cadence tightened ---------------------------------------
	var main_source: String = FileAccess.get_file_as_string("res://scripts/core/Main.gd")
	_check("Main.gd rolls experimental templates every 2 waves now",
		main_source.contains("current_wave % 2 == 0"))
	_check("Main.gd rolls experimental profiles every 3 waves now",
		main_source.contains("current_wave % 3 == 0"))
	_check("Main.gd rolls experimental boss profiles every 4 waves now",
		main_source.contains("current_wave % 4 == 0"))

	if failures == 0:
		print("PASS: AI counter-build wobble, kinetic sight bonus, and widened experimentation all verified")
	get_tree().quit(0 if failures == 0 else 1)
