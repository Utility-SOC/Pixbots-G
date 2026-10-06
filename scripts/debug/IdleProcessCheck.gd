extends Node

# Per-frame _process calls that did nothing most of the time (400+ oil slicks, 400+ tile-durability loops at
# wave 35) now sleep until something wakes them.
const SlickScript = preload("res://scripts/hazards/OilSlickHazard.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var slick = SlickScript.new()
	add_child(slick)
	await get_tree().process_frame
	_check("a permanent oil slick is idle until ignited", not slick.is_processing())
	slick.ignite()
	_check("ignite() wakes it", slick.is_processing() and slick.is_burning)
	slick._burn_timer = 0.01
	slick._process(0.05)
	_check("burning out leaves it cooling down, still ticking", not slick.is_burning and slick.is_processing())
	slick._process(SlickScript.REIGNITE_COOLDOWN + 0.1)
	_check("after the cooldown it goes back to sleep", not slick.is_processing())
	var temp = SlickScript.new()
	temp.lifetime = 5.0
	add_child(temp)
	await get_tree().process_frame
	_check("a temporary slick keeps ticking for its fade", temp.is_processing())
	# durability loop
	var comp = load("res://scripts/core/ComponentEquipment.gd").create_starter_arm(true, "", HexTile.Rarity.RARE)
	var grid = comp.hex_grid
	add_child(comp)
	await get_tree().process_frame
	_check("a grid's durability loop is idle at rest", not grid.is_processing())
	var tile = grid.get_all_tiles()[0]
	tile.take_damage(tile.hp + 1.0) # knock it offline
	_check("a hit wakes the durability loop", grid.is_processing() and tile.is_disabled)
	tile.disable_timer = 0.05
	grid._process(0.1)
	_check("the tile reboots on schedule (hp restored)", not tile.is_disabled and tile.hp == tile.max_hp)
	tile.time_since_last_hit = 0.0
	grid._process(6.0)
	_check("after 5 s without a hit the strike count clears and the loop sleeps", tile.times_disabled == 0 and not grid.is_processing())
	print("idle process check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
