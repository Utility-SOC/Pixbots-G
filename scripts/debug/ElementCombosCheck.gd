extends Node

# ElementCombos: Casual never gets a combo, higher difficulties get more and later waves ramp in, only weapon roles
# qualify, a shield-counter element builds its combo around that element, and retarget() actually splits a real bot's
# weapon elements across the pair.

const MechScript = preload("res://scripts/entities/Mech.gd")
const E = EnergyPacket.SynergyType

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _weapon_totals(bot) -> Dictionary:
	var total = 0.0
	var by = {}
	for data in bot.precalculated_weapons:
		for k in data.packet.synergies:
			total += float(data.packet.synergies[k])
			by[int(k)] = float(by.get(int(k), 0.0)) + float(data.packet.synergies[k])
	return {"total": total, "by_element": by}

func _elements(bot) -> Dictionary:
	var out = {}
	for comp in bot.components.values():
		for coord in comp.hex_grid.grid.keys():
			var tile = comp.hex_grid.grid[coord]
			if tile.tile_type == "Elemental Infuser":
				out[int(tile.secondary_synergy)] = true
			elif tile.tile_type == "Microcore":
				for d in tile.active_faces:
					out[int(tile.get_face_output(d))] = true
	return out

func _ready():
	_check("Casual never rolls a combo at any wave", ElementCombos.chance(0, 1) == 0.0 and ElementCombos.chance(0, 200) == 0.0)
	_check("harder difficulty means a higher chance", ElementCombos.chance(1, 60) < ElementCombos.chance(2, 60) and ElementCombos.chance(2, 60) < ElementCombos.chance(3, 60))
	_check("the chance ramps in with waves and then holds", ElementCombos.chance(3, 5) == 0.0 and ElementCombos.chance(3, 16) < ElementCombos.chance(3, 40) and ElementCombos.chance(3, 40) == ElementCombos.chance(3, 400))
	_check("a failed use-roll gives no combo", ElementCombos.roll("brawler", 3, 60, 0.99, 0.0).is_empty())
	_check("a passing roll gives a pair of two different elements", ElementCombos.roll("brawler", 3, 60, 0.0, 0.0).size() == 3 and ElementCombos.roll("brawler", 3, 60, 0.0, 0.0)["a"] != ElementCombos.roll("brawler", 3, 60, 0.0, 0.0)["b"])
	_check("a role with no real weapons never gets a combo", ElementCombos.roll("support", 3, 60, 0.0, 0.0).is_empty() and ElementCombos.roll("jammer", 3, 60, 0.0, 0.0).is_empty())
	_check("the pick roll chooses among the role's combos", ElementCombos.roll("brawler", 3, 60, 0.0, 0.0)["name"] != ElementCombos.roll("brawler", 3, 60, 0.0, 0.99)["name"])
	var c = ElementCombos.roll("sniper", 3, 60, 0.0, 0.0, E.LIGHTNING)
	_check("a shield counter element builds its combo around itself", c["a"] == E.LIGHTNING and c["b"] == E.EXPLOSION)
	_check("a counter with no partner falls back to a role combo", ElementCombos.roll("sniper", 3, 60, 0.0, 0.0, E.VAMPIRIC)["a"] != E.VAMPIRIC)
	for el in ElementCombos.PARTNER:
		_check("partner is symmetric for %d" % el, ElementCombos.PARTNER[ElementCombos.PARTNER[el]] == el)

	# Pure retint: energy is conserved, both elements of the pair end up well represented, alternate guns lead differently.
	var combo = {"name": "Shatter", "a": E.KINETIC, "b": E.ICE}
	var base = {E.KINETIC: 100.0}
	var t0 = ElementCombos.retint_synergies(base, combo, 0)
	var t1 = ElementCombos.retint_synergies(base, combo, 1)
	var sum0 = 0.0
	for k in t0: sum0 += t0[k]
	_check("retint keeps the total energy (%.1f)" % sum0, is_equal_approx(sum0, 100.0))
	_check("the guns lead differently (gun 1 carries more Ice than gun 0, gun 0 more Kinetic than gun 1)", t1[E.ICE] > t0[E.ICE] and t0[E.KINETIC] > t1[E.KINETIC])
	_check("both elements clear the 20% share wells and shatter need", t0[E.ICE] >= 20.0 and t1[E.KINETIC] >= 20.0)
	_check("a bot that already carried the elements is not erased", ElementCombos.retint_synergies({E.FIRE: 100.0}, combo, 0).has(E.FIRE))
	_check("an empty combo returns the synergies untouched", ElementCombos.retint_synergies(base, {}, 0) == base)

	# A real bot built through the real loadout path: with a combo its weapons carry both elements, same total energy.
	SimRng.seed_all(20261011)
	var bot = MechScript.new()
	bot.is_player = false
	bot.combat_role = "brawler"
	bot.base_rarity = HexTile.Rarity.RARE
	add_child(bot)
	bot._recalculate_grid()
	var before = _weapon_totals(bot)
	_check("the bot has weapons (%d)" % bot.precalculated_weapons.size(), bot.precalculated_weapons.size() > 0)
	bot.element_combo = combo
	bot.is_grid_dirty = true
	bot._recalculate_grid()
	var after = _weapon_totals(bot)
	_check("combo weapons carry both Kinetic and Ice", after["by_element"].get(E.KINETIC, 0.0) > 0.0 and after["by_element"].get(E.ICE, 0.0) > 0.0)
	_check("a baseline brawler carries no Ice, so the Ice is the combo (%.1f)" % after["by_element"].get(E.ICE, 0.0), before["by_element"].get(E.ICE, 0.0) == 0.0)
	_check("total weapon energy is conserved (%.1f vs %.1f)" % [before["total"], after["total"]], absf(before["total"] - after["total"]) < 0.01 * maxf(1.0, before["total"]))
	var player_like = MechScript.new()
	player_like.is_player = true
	player_like.element_combo = combo
	add_child(player_like)
	player_like._recalculate_grid()
	_check("a combo never touches the player's weapons", not _weapon_totals(player_like)["by_element"].has(E.ICE))
	print("ElementCombosCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
