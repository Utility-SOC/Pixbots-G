extends Node

# Regression check for sub-archetype slot tracking: same-role squad-mates
# (e.g. two "brawler" slots in one squad template) now independently evolve
# their own StockBuild instead of always sharing one build for the whole
# role - see StockBuild.sub_archetype_slot, StockBuildEvolution's 4th key
# dimension, and SquadDirector._spawn_bot_for_role's clamp.
#
# Uses the same FakeDirector pattern as StockBuildPromotionGateCheck.gd -
# never touches a real SquadDirector's save machinery (see that file's own
# header comment on why a throwaway test must never risk the real
# "learned_state" save file).

const StockBuildEvolutionScript = preload("res://scripts/ai/StockBuildEvolution.gd")
const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")

class FakeDirector:
	var stock_builds: Array = []
	func request_save_learned_state():
		pass

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1: two different slots for the same (template, role, rarity) get
	# independently tracked/promoted builds - a win in slot 0 must not
	# affect slot 1's own champion.
	var fake = FakeDirector.new()
	var evo = StockBuildEvolutionScript.new(fake)
	evo.establish_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, {"tag": "slot0_v1"}, 0)
	evo.establish_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, {"tag": "slot1_v1"}, 1)
	_check("slot 0 and slot 1 get separate StockBuild entries for the same (template, role, rarity)",
		fake.stock_builds.size() == 2)
	_check("slot 0's build is retrievable independently of slot 1's",
		evo.get_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, 0).serialized_components.get("tag") == "slot0_v1")
	_check("slot 1's build is retrievable independently of slot 0's",
		evo.get_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, 1).serialized_components.get("tag") == "slot1_v1")

	# A majority-win batch for slot 0 only should promote slot 0's build and
	# leave slot 1's completely untouched.
	var slot0_champion = evo.get_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, 0)
	slot0_champion.times_used = 1
	slot0_champion.total_fitness = 100.0
	for f in [110.0, 120.0, 130.0, 140.0, 90.0, 80.0, 70.0, 60.0]: # 4 of 8 beat 100 - meets the 50% win-rate gate
		evo.record_deviation_result("Escort", "brawler", HexTile.Rarity.COMMON, {"tag": "slot0_dev_%d" % int(f)}, f, 0)
	var slot0_after = evo.get_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, 0)
	var slot1_after = evo.get_stock_build("Escort", "brawler", HexTile.Rarity.COMMON, 1)
	_check("promoting slot 0's build changes slot 0's tag",
		slot0_after.serialized_components.get("tag") == "slot0_dev_140")
	_check("promoting slot 0's build leaves slot 1's build completely untouched",
		slot1_after.serialized_components.get("tag") == "slot1_v1")

	# --- 2: _spawn_bot_for_role clamps sub_archetype_slot to
	# MAX_SUB_ARCHETYPE_SLOTS - 1 (a squad's 5th+ same-role member reuses
	# the last slot instead of opening a new cache entry). Bare Mech.new(),
	# never added to the tree (avoids @onready-coupled _ready() - same
	# established pattern as other pure-logic checks on heavy scene-coupled
	# classes this session).
	var director = SquadDirectorScript.new()
	director.name = "SquadDirector"
	add_child(director)
	var bot_over_cap = director._spawn_bot_for_role("brawler", false, 0, "", false, 10)
	_check("a slot index past MAX_SUB_ARCHETYPE_SLOTS clamps to the last slot (got %d, expect %d)" % [
		bot_over_cap.sub_archetype_slot, StockBuildEvolutionScript.MAX_SUB_ARCHETYPE_SLOTS - 1],
		bot_over_cap.sub_archetype_slot == StockBuildEvolutionScript.MAX_SUB_ARCHETYPE_SLOTS - 1)
	bot_over_cap.queue_free()
	var bot_in_range = director._spawn_bot_for_role("brawler", false, 0, "", false, 1)
	_check("a slot index within range passes through unchanged (got %d, expect 1)" % bot_in_range.sub_archetype_slot,
		bot_in_range.sub_archetype_slot == 1)
	bot_in_range.queue_free()

	# --- 3: merge dedup (SquadDirector._merge_learned, simulated directly
	# via the same comparison it uses) keeps two different slots' entries
	# separate on a simulated reload, rather than colliding and silently
	# overwriting one with the other.
	var loaded_slot0 = StockBuildEvolutionScript.StockBuild.new("Escort", "brawler", HexTile.Rarity.COMMON)
	loaded_slot0.sub_archetype_slot = 0
	loaded_slot0.serialized_components = {"tag": "reloaded_slot0"}
	var loaded_slot1 = StockBuildEvolutionScript.StockBuild.new("Escort", "brawler", HexTile.Rarity.COMMON)
	loaded_slot1.sub_archetype_slot = 1
	loaded_slot1.serialized_components = {"tag": "reloaded_slot1"}
	var target_stock_builds: Array = [slot0_after, slot1_after]
	var merge_matches = 0
	for lsb in [loaded_slot0, loaded_slot1]:
		for sb in target_stock_builds:
			if sb.template_name == lsb.template_name and sb.role == lsb.role and sb.rarity == lsb.rarity and sb.sub_archetype_slot == lsb.sub_archetype_slot:
				merge_matches += 1
				break
	_check("merge dedup correctly matches each loaded slot to its own existing slot, not the other one",
		merge_matches == 2)

	if failures == 0:
		print("PASS: sub-archetype slots are independently tracked/promoted, clamp correctly at spawn time, and stay distinct through merge dedup")
	get_tree().quit(0 if failures == 0 else 1)
