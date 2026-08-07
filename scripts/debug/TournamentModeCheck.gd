extends Node

# Regression harness for Tournament mode (the user: "Tournament mode is
# rounds of fights against the other players and the four champions. The
# four champions unlock as they are defeated through normal play.") Covers
# the pure-logic pieces only - SaveManager's new per-save fields/helpers,
# the 5 new RivalProfile entries (Elite Four + Frank), and SquadDirector's
# pool-gating. Deliberately does NOT call SaveManager.save_game/load_game -
# user:// is the player's real save directory, not a test sandbox (see
# feedback_headless_test_userdata_safety memory) - so this only ever
# manipulates the SaveManager singleton's in-memory fields directly, and
# restores them to a clean slate when done.

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Snapshot so this test can restore the singleton afterward.
	var saved_defeated_rivals = SaveManager.defeated_rivals.duplicate()
	var saved_locked_out = SaveManager.tournament_locked_out
	var saved_arc_unlocked = SaveManager.tournament_arc_unlocked

	# --- SaveManager: roster consts ---
	_check("REGULAR_RIVAL_NAMES has exactly the 14 profile keys (15 named regulars, Leo & Luna share one)",
		SaveManager.REGULAR_RIVAL_NAMES.size() == 14)
	_check("ELITE_FOUR_NAMES has exactly 4 champions",
		SaveManager.ELITE_FOUR_NAMES.size() == 4)
	_check("Frank is NOT in either roster const (he's the separate twist finale)",
		not SaveManager.REGULAR_RIVAL_NAMES.has("Frank") and not SaveManager.ELITE_FOUR_NAMES.has("Frank"))

	# --- SaveManager: all_regulars_defeated() / defeated_champion_names() ---
	SaveManager.defeated_rivals = {}
	_check("all_regulars_defeated() false with zero defeats",
		not SaveManager.all_regulars_defeated())

	for r_name in SaveManager.REGULAR_RIVAL_NAMES:
		SaveManager.defeated_rivals[r_name] = true
	_check("all_regulars_defeated() true once all 14 regular keys are marked defeated",
		SaveManager.all_regulars_defeated())

	SaveManager.defeated_rivals["Hrothgar"] = true
	SaveManager.defeated_rivals["Dan"] = true
	_check("defeated_champion_names() returns only the defeated champions, in ELITE_FOUR_NAMES order",
		SaveManager.defeated_champion_names() == ["Hrothgar", "Dan"])

	# --- RivalProfilesFactory: Elite Four + Frank ---
	var profiles = RivalProfilesFactory.create_profiles(DialogueManager.dialogue_data)
	_check("RivalProfilesFactory produces all 5 new profiles",
		profiles.has("Hrothgar") and profiles.has("Dan") and profiles.has("Evan")
		and profiles.has("Joe") and profiles.has("Frank"))

	_check("Dan is force_junk_only (starter-tier gear, zero Mythic parts per STORY_SCRIPT.md)",
		profiles.has("Dan") and profiles["Dan"].force_junk_only == true)
	_check("Dan's dialogue_intro was pulled from dialogue.json (compile_dialogue.py already covers the Elite Four section)",
		profiles.has("Dan") and profiles["Dan"].dialogue_intro != "")
	_check("Hrothgar's dialogue_win was pulled from dialogue.json",
		profiles.has("Hrothgar") and profiles["Hrothgar"].dialogue_win != "")
	_check("Evan's dialogue_loss was pulled from dialogue.json",
		profiles.has("Evan") and profiles["Evan"].dialogue_loss != "")
	_check("Joe's dialogue is empty (documented placeholder - 'Needs a real design pass', not yet written in STORY_SCRIPT.md's parseable format)",
		profiles.has("Joe") and profiles["Joe"].dialogue_intro == "")
	_check("Frank's dialogue_intro was pulled from dialogue.json (Tournament capstone)",
		profiles.has("Frank") and profiles["Frank"].dialogue_intro != "")
	_check("Elite Four all have an hp_mult bump over the 1.0 baseline (one tier above the Regulars)",
		profiles["Hrothgar"].hp_mult > 1.0 and profiles["Dan"].hp_mult > 1.0
		and profiles["Evan"].hp_mult > 1.0 and profiles["Joe"].hp_mult > 1.0)
	_check("Frank has the highest hp_mult of any profile (toughest fight in the game)",
		profiles["Frank"].hp_mult > profiles["Hrothgar"].hp_mult
		and profiles["Frank"].hp_mult > profiles["Dan"].hp_mult
		and profiles["Frank"].hp_mult > profiles["Evan"].hp_mult
		and profiles["Frank"].hp_mult > profiles["Joe"].hp_mult)

	# --- SquadDirector: pool gating ---
	var director = SquadDirector.new()
	add_child(director)
	await get_tree().process_frame # let _ready() populate all_rival_profiles

	SaveManager.defeated_rivals = {}
	var pool_locked = director._eligible_rival_pool_keys()
	_check("Frank never appears in the normal rival pool, locked or unlocked",
		not pool_locked.has("Frank"))
	_check("Elite Four excluded from the pool while regulars aren't all defeated",
		not pool_locked.has("Hrothgar") and not pool_locked.has("Dan")
		and not pool_locked.has("Evan") and not pool_locked.has("Joe"))
	_check("All 14 regulars still present in the pool while Elite Four is locked out",
		pool_locked.size() == 14)

	for r_name in SaveManager.REGULAR_RIVAL_NAMES:
		SaveManager.defeated_rivals[r_name] = true
	var pool_open = director._eligible_rival_pool_keys()
	_check("Elite Four enters the pool once all regulars are defeated",
		pool_open.has("Hrothgar") and pool_open.has("Dan")
		and pool_open.has("Evan") and pool_open.has("Joe"))
	_check("Frank still excluded even with Elite Four unlocked (Tournament-only capstone)",
		not pool_open.has("Frank"))
	_check("Pool grows to 18 (14 regulars + 4 champions) once unlocked",
		pool_open.size() == 18)

	director.queue_free()

	# --- Restore singleton state ---
	SaveManager.defeated_rivals = saved_defeated_rivals
	SaveManager.tournament_locked_out = saved_locked_out
	SaveManager.tournament_arc_unlocked = saved_arc_unlocked

	if failures == 0:
		print("PASS: Tournament mode's roster tracking, Elite Four/Frank profiles, and pool gating are all wired correctly")
	get_tree().quit(0 if failures == 0 else 1)
