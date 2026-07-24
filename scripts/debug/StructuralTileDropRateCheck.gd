extends Node

# Regression harness for: "the hex tiles that are core (accessory return,
# torso return, core reactor, links) should all drop at a much lower rate.
# Microcores should ALSO drop at a lower rate than they are now, but I'm
# happy for them to spawn more often than the returns, core and links."
#
# Root cause: LootManager.generate_loot_for_mech/generate_ghost_loot rolled
# every equipped tile's drop chance from RARITY alone. A Torso structurally
# REQUIRES 7 mandatory "plumbing" tiles (Core Reactor, Accessory Return,
# one Link per limb/head/backpack) regardless of build, while genuinely
# interesting processors (Amplifier/Splitter/Resonator/...) are a much
# smaller slice - so with no per-type adjustment, that plumbing majority
# dominated actual drops. Fixed with a tile-type multiplier applied on top
# of the existing rarity-based chance.

const LootManagerScript = preload("res://scripts/core/LootManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var lm = LootManagerScript.new()

	_check("Core Reactor gets the structural (heavily reduced) multiplier",
		lm._tile_type_drop_multiplier("Core Reactor") == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)
	_check("Accessory Return gets the structural multiplier",
		lm._tile_type_drop_multiplier("Accessory Return") == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)
	_check("Torso Return gets the structural multiplier",
		lm._tile_type_drop_multiplier("Torso Return") == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)
	_check("Energy Intake gets the structural multiplier",
		lm._tile_type_drop_multiplier("Energy Intake") == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)
	for link_name in ["Left Arm Link", "Right Arm Link", "Left Leg Link", "Right Leg Link", "Head Link", "Backpack Link"]:
		_check("%s gets the structural multiplier" % link_name,
			lm._tile_type_drop_multiplier(link_name) == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)

	_check("Actuator gets the structural multiplier (follow-up: was previously unreduced)",
		lm._tile_type_drop_multiplier("Actuator") == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)

	_check("Microcore gets its own reduced multiplier, distinct from the structural group",
		lm._tile_type_drop_multiplier("Microcore") == LootManagerScript.MICROCORE_DROP_MULTIPLIER)
	_check("Microcore's multiplier is higher (more common) than the structural group's",
		LootManagerScript.MICROCORE_DROP_MULTIPLIER > LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)

	_check("an ordinary processing tile (Amplifier) is unaffected - stays at 1.0x",
		lm._tile_type_drop_multiplier("Amplifier") == 1.0)
	_check("Splitter (a real configurable tool, not mandatory plumbing) is unaffected",
		lm._tile_type_drop_multiplier("Splitter") == 1.0)

	# Follow-up (per the user): "...need to drop less frequently at all
	# tiers except mythic" - a Mythic-rarity structural/microcore tile
	# should NOT be reduced, unlike every lower rarity.
	_check("a MYTHIC Core Reactor is exempt from the structural reduction (full 1.0x)",
		lm._tile_type_drop_multiplier("Core Reactor", HexTile.Rarity.MYTHIC) == 1.0)
	_check("a MYTHIC Left Arm Link is exempt from the structural reduction",
		lm._tile_type_drop_multiplier("Left Arm Link", HexTile.Rarity.MYTHIC) == 1.0)
	_check("a MYTHIC Actuator is exempt from the structural reduction",
		lm._tile_type_drop_multiplier("Actuator", HexTile.Rarity.MYTHIC) == 1.0)
	_check("a MYTHIC Microcore is exempt from its reduction",
		lm._tile_type_drop_multiplier("Microcore", HexTile.Rarity.MYTHIC) == 1.0)
	_check("a COMMON Core Reactor is still reduced (mythic exemption doesn't leak to other tiers)",
		lm._tile_type_drop_multiplier("Core Reactor", HexTile.Rarity.COMMON) == LootManagerScript.STRUCTURAL_DROP_MULTIPLIER)
	_check("a LEGENDARY Microcore is still reduced (mythic exemption doesn't leak to other tiers)",
		lm._tile_type_drop_multiplier("Microcore", HexTile.Rarity.LEGENDARY) == LootManagerScript.MICROCORE_DROP_MULTIPLIER)

	if failures == 0:
		print("PASS: structural/plumbing tiles and Microcores drop less often than genuine processing tiles")
	get_tree().quit(0 if failures == 0 else 1)
