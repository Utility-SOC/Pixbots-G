extends Node

# Regression guard for a display bug caused by SquadDirector.gd's
# captured_loadouts key change: captured_loadouts is now keyed by a
# composite "template:role" string (see SquadDirector._maybe_capture_
# loadout), not a plain role. GarageShop._make_bot_offer/_add_bot_row
# used to stuff that raw key straight into offer.role and display it
# verbatim ("Grunt_template:brawler" in the shop UI). Fixed by adding a
# separate offer.role_name field (mirrors the role_name/template_name
# split WarRoomMenu.gd's _build_captures already established) and having
# display code read that instead of the lookup key.

const GarageShopScript = preload("res://scripts/ui/GarageShop.gd")

class FakeDirector:
	var captured_loadouts: Dictionary = {}

class FakeGarage:
	func _show_scrap_float(_msg, _color): pass
	func _refresh_inventory_ui(): pass
	func _slot_display_name(_slot): return "Slot"

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var shop = GarageShopScript.new(FakeGarage.new())

	# --- Captured offer, current composite-key format ---
	var director = FakeDirector.new()
	director.captured_loadouts["Grunt_Template:brawler"] = {
		"fitness": 42.0,
		"rarity": HexTile.Rarity.LEGENDARY,
		"components": {},
		"role_name": "brawler",
		"template_name": "Grunt_Template",
	}
	var offer = shop._make_bot_offer("Grunt_Template:brawler", director)
	_check("offer.role keeps the composite lookup key (purchase/re-roll depend on an exact dict-key match)",
		offer.role == "Grunt_Template:brawler")
	_check("offer.role_name is the clean role alone, no template prefix",
		offer.role_name == "brawler")
	_check("offer.role_name contains no colon",
		not offer.role_name.contains(":"))

	var vbox = VBoxContainer.new()
	add_child(vbox)
	shop._bot_offers = [offer]
	shop._add_bot_row(vbox, null, 0)
	var btn_text: String = vbox.get_child(0).text
	_check("the rendered shop button text shows 'Brawler', not the raw composite key (got: %s)" % btn_text,
		btn_text.contains("Brawler") and not btn_text.contains(":"))

	# --- Generated (non-captured) fallback path: role_name mirrors role ---
	var offer_gen = shop._make_bot_offer("sniper", FakeDirector.new())
	_check("generated-offer role_name mirrors the plain role",
		offer_gen.role_name == "sniper" and offer_gen.role == "sniper")

	# --- Old-format capture missing role_name: graceful fallback, no crash ---
	var director_old = FakeDirector.new()
	director_old.captured_loadouts["oldrole"] = {"fitness": 1.0, "rarity": 0, "components": {}}
	var offer_old = shop._make_bot_offer("oldrole", director_old)
	_check("a pre-existing capture with no role_name field falls back to the lookup key instead of crashing",
		offer_old.role_name == "oldrole")

	if failures == 0:
		print("PASS: GarageShop bot-offer display uses the clean role_name, never the raw composite captured_loadouts key")
	get_tree().quit(0 if failures == 0 else 1)
