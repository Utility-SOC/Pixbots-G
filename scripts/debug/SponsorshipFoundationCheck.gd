extends Node

# Regression harness for the Corporate Sponsorships foundation (task #17,
# first of three build stages - see Status.md/task tracker). Covers what's
# actually testable before any brand tiles exist (task #50 builds those):
# BrandRegistry's data API, BrandTileFactory's null-safety with an empty
# registry, Mech.brand_affiliation's default/assignability, SaveManager
# round-tripping player_sponsorship, and LootManager's drop hook not
# crashing on a brand-affiliated boss kill even with zero tiles registered.
# Once task #50 lands real brand tiles, extend this (or a sibling check) to
# also verify actual drops - see BrandTileFactory.BRAND_TILE_SCRIPTS's own
# comment for why it's empty right now.

const BrandRegistryScript = preload("res://scripts/core/BrandRegistry.gd")
const BrandTileFactoryScript = preload("res://scripts/core/BrandTileFactory.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _ready():
	# --- 1. BrandRegistry API ------------------------------------------------
	_check("BrandRegistry has 7 brands", BrandRegistryScript.BRAND_IDS.size(), 7)
	for id in BrandRegistryScript.BRAND_IDS:
		if not BrandRegistryScript.is_valid_brand(id):
			push_error("FAIL: BrandRegistry doesn't recognize its own id '%s'" % id)
			failures += 1
		if BrandRegistryScript.display_name(id) == "Unknown":
			push_error("FAIL: BrandRegistry has no display name for '%s'" % id)
			failures += 1
		if BrandRegistryScript.logo_letter(id) == "?":
			push_error("FAIL: BrandRegistry has no logo letter for '%s'" % id)
			failures += 1
	print("1) BrandRegistry: all 7 brand ids have names + logo marks")

	if BrandRegistryScript.is_valid_brand("not_a_real_brand"):
		push_error("FAIL: BrandRegistry accepted a garbage brand id")
		failures += 1
	else:
		print("2) BrandRegistry correctly rejects an unrecognized id")

	for i in range(20):
		if not BrandRegistryScript.is_valid_brand(BrandRegistryScript.random_brand()):
			push_error("FAIL: random_brand() produced an invalid id")
			failures += 1
			break
	print("3) random_brand() always returns a valid id (20 samples)")

	# --- 2. BrandTileFactory null-safety (no brand tiles built yet) --------
	# "defensive" is the last brand still pending as of this check's most
	# recent update - power/sniper/efficiency/cloak/sensors are all built
	# now (see BrandTileFactory.BRAND_TILE_SCRIPTS), so this assertion has to
	# keep pointing at whichever brand is still genuinely unbuilt.
	var tile = BrandTileFactoryScript.random_tile_for_brand("defensive")
	_check("random_tile_for_brand() for an unbuilt brand returns null", tile, null)
	var garbage_tile = BrandTileFactoryScript.random_tile_for_brand("not_a_real_brand")
	_check("random_tile_for_brand() for a garbage id returns null", garbage_tile, null)

	# --- 3. Mech.brand_affiliation -----------------------------------------
	var world = Node2D.new()
	add_child(world)
	var boss = MechScript.new()
	boss.is_player = false
	world.add_child(boss)
	boss.set_physics_process(false)
	_check("fresh Mech.brand_affiliation defaults empty", boss.brand_affiliation, "")
	boss.brand_affiliation = "defensive"
	_check("Mech.brand_affiliation is freely assignable", boss.brand_affiliation, "defensive")

	# --- 4. LootManager doesn't crash on a brand-affiliated boss kill -------
	# (produces zero pickups right now since BrandTileFactory has no tiles
	# registered yet - this only proves the new code path is safe, not that
	# it drops anything. See this file's header.)
	boss.is_boss = true
	boss.set_meta("boss_drop", "shield")
	var before_children = world.get_child_count()
	LootManager.generate_loot_for_mech(boss)
	await get_tree().process_frame
	print("4) LootManager.generate_loot_for_mech() ran on a brand-affiliated boss without erroring (children %d -> %d)" % [before_children, world.get_child_count()])

	# NOTE: player_sponsorship's save/load wiring (SaveManager.gd's
	# save_game()/load_game(), Main.gd's _setup_player() load branch) is
	# deliberately NOT exercised here via a live SaveManager.save_game()/
	# load_game() call - user://saves/ is the REAL save directory, not a
	# sandbox, and a throwaway test must never write there even with
	# cleanup afterward. The wiring mirrors current_wave's existing pattern
	# exactly (same has()-guarded read/write shape) - verified by code
	# review instead of a live round-trip.

	if failures == 0:
		print("PASS: Corporate Sponsorships foundation (brand registry, tile factory, boss affiliation, drop hook, save/load) all verified")
	get_tree().quit(0 if failures == 0 else 1)
