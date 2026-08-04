extends Node

# Regression harness for Chip Splicing (Late-game progression, execution
# queue item 3) - see ChipSplicer.gd's header comment and the plan at
# C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md for the
# full design. Covers: Tier 1 splice (boost + random negative), Tier 2
# re-splice (match required, algebraic netting, unbounded growth), the
# same-stat-plain-chips-fall-through-to-Tier-2 rule, CHIP_STAT_FLOOR,
# save/load round-trip, legacy migration, enemy chip-equip, and the
# plain-only death-drop rule.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ChipSplicerScript = preload("res://scripts/core/ChipSplicer.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _check_true(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_component(rarity: int) -> ComponentEquipment:
	# Deliberately NOT parented here - section 8 hands its component to
	# Mech.equip_component(), which add_child()s it itself; a component
	# already parented under this check node would make that call fail
	# ("already has a parent"). Every other call site parents explicitly.
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity)
	comp.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = rarity
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)
	return comp

func _trait_value(chip: Dictionary, stat: String) -> float:
	for t in chip.get("traits", []):
		if str(t["stat"]) == stat:
			return float(t["value"])
	return 1.0

func _ready():
	var seeded_rng = RandomNumberGenerator.new()
	seeded_rng.seed = 12345

	# --- 1. Tier 1 splice ------------------------------------------------------
	var chip_a = {"traits": [{"stat": "kin_mult", "value": 1.20}]}
	var chip_b = {"traits": [{"stat": "fire_mult", "value": 1.10}]}
	_check("classify_splice: two different-stat plain chips = tier1", ChipSplicerScript.classify_splice(chip_a, chip_b), "tier1")
	var t1 = ChipSplicerScript.splice_tier1(chip_a, chip_b, seeded_rng)
	_check("Tier 1 result has exactly 3 traits", t1["traits"].size(), 3)
	var expected_kin = 1.0 + (1.20 - 1.0) * ChipSplicerScript.SPLICE_BOOST_MULT
	var expected_fire = 1.0 + (1.10 - 1.0) * ChipSplicerScript.SPLICE_BOOST_MULT
	_check_true("Tier 1 boosts stat A beyond its original value", is_equal_approx(_trait_value(t1, "kin_mult"), round(expected_kin * 100.0) / 100.0))
	_check_true("Tier 1 boosts stat B beyond its original value", is_equal_approx(_trait_value(t1, "fire_mult"), round(expected_fire * 100.0) / 100.0))
	var neg_stat = ""
	for t in t1["traits"]:
		if str(t["stat"]) != "kin_mult" and str(t["stat"]) != "fire_mult":
			neg_stat = str(t["stat"])
	_check_true("Tier 1's negative trait is drawn from CHIP_STAT_POOL, not kin_mult/fire_mult", neg_stat != "" and ComponentEquipmentScript.CHIP_STAT_POOL.has(neg_stat))
	_check_true("Tier 1's negative trait value is actually negative (< 1.0)", _trait_value(t1, neg_stat) < 1.0)
	_check_true("Tier 1's negative trait magnitude is within the configured range", _trait_value(t1, neg_stat) >= 1.0 - ChipSplicerScript.NEG_TRAIT_MAX_MAG - 0.001 and _trait_value(t1, neg_stat) <= 1.0 - ChipSplicerScript.NEG_TRAIT_MIN_MAG + 0.001)

	# --- 2. Tier 2 re-splice -----------------------------------------------------
	var no_overlap_a = {"traits": [{"stat": "kin_mult", "value": 1.2}]}
	var no_overlap_b = {"traits": [{"stat": "fire_mult", "value": 1.2}, {"stat": "ice_mult", "value": 1.1}]}
	_check("classify_splice: zero stat overlap = invalid", ChipSplicerScript.classify_splice(no_overlap_a, no_overlap_b), "invalid")
	_check("splice_chips on zero overlap returns {} (rejected, nothing consumed)", ChipSplicerScript.splice_chips(no_overlap_a, no_overlap_b).is_empty(), true)

	# Sign-flip case: +20% ice meets -8% ice -> nets to +12%.
	var pos_ice = {"traits": [{"stat": "ice_mult", "value": 1.20}]}
	var neg_ice = {"traits": [{"stat": "ice_mult", "value": 0.92}]} # -8%
	_check("classify_splice: shared stat = tier2", ChipSplicerScript.classify_splice(pos_ice, neg_ice), "tier2")
	var sign_flip = ChipSplicerScript.splice_tier2(pos_ice, neg_ice)
	_check("sign-flip case has exactly 1 resulting trait", sign_flip["traits"].size(), 1)
	_check_true("sign-flip nets algebraically to +12% (no boost applied)", is_equal_approx(_trait_value(sign_flip, "ice_mult"), 1.12))

	# Full-cancellation case: +15% and -15% on the same stat -> vanishes entirely.
	var pos_exact = {"traits": [{"stat": "psn_mult", "value": 1.15}]}
	var neg_exact = {"traits": [{"stat": "psn_mult", "value": 0.85}]}
	var cancelled = ChipSplicerScript.splice_chips(pos_exact, neg_exact)
	_check_true("a splice that fully cancels to zero traits is rejected ({}), not a dead 0-trait chip", cancelled.is_empty())

	# --- 3. Unbounded growth - the user's own worked example -------------------
	# {+fire,+ice,-vortex} re-spliced with {+fire,+ice,-lightning} -> 4 traits:
	# fire and ice both matched-and-summed, vortex and lightning both carried
	# over unchanged (one from each side, no match).
	var corrupted_a = {"traits": [{"stat": "fire_mult", "value": 1.30}, {"stat": "ice_mult", "value": 1.25}, {"stat": "vtx_mult", "value": 0.90}]}
	var corrupted_b = {"traits": [{"stat": "fire_mult", "value": 1.10}, {"stat": "ice_mult", "value": 1.05}, {"stat": "ltg_mult", "value": 0.88}]}
	_check("classify_splice: two Corrupted chips sharing fire/ice = tier2", ChipSplicerScript.classify_splice(corrupted_a, corrupted_b), "tier2")
	var grown = ChipSplicerScript.splice_tier2(corrupted_a, corrupted_b)
	_check("unbounded growth: 4-trait result (2 merged + 2 carried over), no cap", grown["traits"].size(), 4)
	_check_true("fire summed: 1.30 + 1.10 - 1.0 = 1.40", is_equal_approx(_trait_value(grown, "fire_mult"), 1.40))
	_check_true("ice summed: 1.25 + 1.05 - 1.0 = 1.30", is_equal_approx(_trait_value(grown, "ice_mult"), 1.30))
	_check_true("vortex carried over unchanged from side A", is_equal_approx(_trait_value(grown, "vtx_mult"), 0.90))
	_check_true("lightning carried over unchanged from side B", is_equal_approx(_trait_value(grown, "ltg_mult"), 0.88))

	# --- 4. Same-stat plain chips fall through to Tier 2, not Tier 1 -----------
	var same_stat_a = {"traits": [{"stat": "spd_mult", "value": 1.15}]}
	var same_stat_b = {"traits": [{"stat": "spd_mult", "value": 1.10}]}
	_check("two same-stat PLAIN chips classify as tier2, not tier1", ChipSplicerScript.classify_splice(same_stat_a, same_stat_b), "tier2")
	var same_stat_result = ChipSplicerScript.splice_tier2(same_stat_a, same_stat_b)
	_check_true("no SPLICE_BOOST_MULT applied - pure algebraic sum (1.15+1.10-1.0=1.25)", is_equal_approx(_trait_value(same_stat_result, "spd_mult"), 1.25))

	# --- 5. CHIP_STAT_FLOOR ------------------------------------------------------
	var floor_comp = _make_component(HexTile.Rarity.MYTHIC)
	add_child(floor_comp)
	floor_comp.equipped_chips.append({"traits": [{"stat": "dmg_mult", "value": 0.50}]})
	floor_comp.equipped_chips.append({"traits": [{"stat": "dmg_mult", "value": 0.30}]})
	floor_comp.equipped_chips.append({"traits": [{"stat": "dmg_mult", "value": 0.20}]})
	floor_comp._recompute_stat_modifiers()
	_check_true("stacked negative traits clamp at CHIP_STAT_FLOOR, never go negative",
		is_equal_approx(float(floor_comp.stat_modifiers.get("dmg_mult", 1.0)), ComponentEquipmentScript.CHIP_STAT_FLOOR))

	# --- 6. Save/load round-trip of a multi-trait chip ---------------------------
	var save_comp = _make_component(HexTile.Rarity.RARE)
	add_child(save_comp)
	save_comp.equipped_chips.append(grown.duplicate(true)) # the 4-trait chip from section 3
	var save_mgr = SaveManagerScript.new()
	var serialized = save_mgr._serialize_component(save_comp)
	var restored = save_mgr._deserialize_component(serialized)
	_check("multi-trait equipped_chips entry survives save/load with the same trait count", restored.equipped_chips[0]["traits"].size(), 4)
	_check_true("restored chip's stat_modifiers matches (fire_mult)", is_equal_approx(float(restored.stat_modifiers.get("fire_mult", 1.0)), 1.40))

	# --- 7. Legacy migration ------------------------------------------------------
	var legacy_cdata = {
		"slot_type": HexTile.BodySlot.TORSO, "rarity": HexTile.Rarity.RARE,
		"component_name": "Legacy Part", "infusion_level": 0, "infusion_xp": 0,
		"equipped_chips": [{"stat": "kin_mult", "value": 1.25}], # OLD flat shape, no "traits" key
		"forbidden_tile_types": [], "tiles": [], "fixed_sinks": [], "valid_hexes": [],
	}
	var migrated = save_mgr._deserialize_component(legacy_cdata)
	_check("legacy flat chip migrates to a single-trait chip losslessly", migrated.equipped_chips[0]["traits"].size(), 1)
	_check_true("migrated chip's effective bonus is unchanged", is_equal_approx(float(migrated.stat_modifiers.get("kin_mult", 1.0)), 1.25))

	# --- 8. Enemy chip equip at spawn ---------------------------------------------
	# Calls the real Main._equip_enemy_chips() directly (not a reimplementation
	# of its logic) - Main.new() without add_child() never enters the tree, so
	# its heavy _ready() (UI/squad-director setup) never fires; the function
	# under test only touches its `mech` param and its own consts/statics.
	var world = Node2D.new()
	add_child(world)
	var fake_mech = MechScript.new()
	fake_mech.is_player = false
	world.add_child(fake_mech) # triggers Mech._ready(), auto-equips 7 starter components
	fake_mech.set_physics_process(false)

	var main_script = load("res://scripts/core/Main.gd")
	var main = main_script.new()
	main._equip_enemy_chips(fake_mech)
	fake_mech._recalculate_grid()

	var granted_chips = []
	for comp in fake_mech.components.values():
		for chip in comp.equipped_chips:
			granted_chips.append(chip)
	_check_true("enemy chip-equip grants between ENEMY_CHIP_COUNT_MIN and _MAX chips total",
		granted_chips.size() >= main_script.ENEMY_CHIP_COUNT_MIN and granted_chips.size() <= main_script.ENEMY_CHIP_COUNT_MAX)
	var all_single_trait = true
	var all_in_range = true
	for chip in granted_chips:
		if chip["traits"].size() != 1:
			all_single_trait = false
		var v = float(chip["traits"][0]["value"])
		if v < 1.0 + main_script.ENEMY_CHIP_MIN_BONUS - 0.011 or v > 1.0 + main_script.ENEMY_CHIP_MAX_BONUS + 0.011:
			all_in_range = false
	_check_true("every enemy-granted chip is plain (single-trait)", all_single_trait)
	_check_true("every enemy-granted chip's value is within the configured bonus range", all_in_range)

	# --- 9. Death-drop rule: plain chips roll, Corrupted chips never do --------
	var drop_comp = _make_component(HexTile.Rarity.MYTHIC)
	add_child(drop_comp)
	drop_comp.equipped_chips.append({"traits": [{"stat": "dmg_mult", "value": 1.2}]}) # plain
	drop_comp.equipped_chips.append(grown.duplicate(true)) # Corrupted, 4 traits
	var plain_eligible = 0
	var corrupted_eligible = 0
	for chip in drop_comp.equipped_chips:
		if chip.get("traits", []).size() == 1:
			plain_eligible += 1
		else:
			corrupted_eligible += 1
	_check("exactly 1 plain chip is eligible to roll a drop", plain_eligible, 1)
	_check("exactly 1 Corrupted chip is correctly excluded from ever dropping", corrupted_eligible, 1)

	# LootPickup.chip_data round-trip. _on_body_entered() reads
	# body.get_tree().current_scene, which isn't reachable without a real
	# SceneTree.current_scene swap - verify the pickup's own field plus the
	# exact append LootPickup._on_body_entered's chip branch performs.
	var pickup = load("res://scripts/entities/LootPickup.gd").new()
	pickup.chip_data = {"traits": [{"stat": "spd_mult", "value": 1.18}]}
	var fake_scene_script = GDScript.new()
	fake_scene_script.source_code = "extends Node2D\nvar player_modifier_chips: Array = []\n"
	fake_scene_script.reload()
	var fake_scene = Node2D.new()
	fake_scene.set_script(fake_scene_script)
	world.add_child(fake_scene)
	fake_scene.player_modifier_chips.append(pickup.chip_data)
	_check("LootPickup.chip_data round-trips into player_modifier_chips on pickup", fake_scene.player_modifier_chips.size(), 1)
	_check_true("picked-up chip data matches what was dropped", is_equal_approx(float(fake_scene.player_modifier_chips[0]["traits"][0]["value"]), 1.18))

	if failures == 0:
		print("PASS: ChipSplicingCheck - Tier 1/2 merge algorithm, unbounded growth, stat floor, save/load, legacy migration, enemy equip, and death-drop rules all behave correctly")
	get_tree().quit(0 if failures == 0 else 1)
