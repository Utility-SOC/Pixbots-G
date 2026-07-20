extends Node

# Regression harness for the ShieldGenerator/ShieldTile consolidation (per
# the user: "it SHOULD be using ShieldTile instead of ShieldGeneratorTile -
# deprecated because the linear scaling didn't work properly. All tiles need
# to be ported, there are issues displaying tiles with the mixed system").
#
# Two classes shared tile_type "Shield Generator" - a genuine collision.
# ShieldTile is now canonical (tuned per-rarity curve); ShieldGeneratorTile
# is a deprecated thin subclass so old saves still load but adopt the curve.
# Verifies: the shim inherits ShieldTile behavior, a serialized
# ShieldGeneratorTile round-trips (and behaves on the curve, not the old
# linear scaling), and both report the same banked energy for the same input.

const ShieldTileScript = preload("res://scripts/tiles/ShieldTile.gd")
const ShieldGeneratorTileScript = preload("res://scripts/tiles/ShieldGeneratorTile.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _bank_for(tile, rarity: int) -> float:
	tile.rarity = rarity
	tile.stored_energy = 0.0
	var pkt = EnergyPacket.new(100.0, HexCoord.new(0, 0))
	tile.process_energy(pkt, 3)
	return tile.get_shield_energy()

func _ready():
	# 1. The shim IS a ShieldTile and shares the canonical tile_type.
	var shim = ShieldGeneratorTileScript.new()
	_check("ShieldGeneratorTile is now a subclass of ShieldTile", shim is ShieldTileScript)
	_check("ShieldGeneratorTile still reports tile_type 'Shield Generator'", shim.tile_type == "Shield Generator")

	# 2. The shim banks energy on the SAME curve as ShieldTile at every
	# rarity (i.e. it no longer uses the old linear scaling).
	var canonical = ShieldTileScript.new()
	var curve_match = true
	for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]:
		var a = _bank_for(canonical, rarity)
		var b = _bank_for(shim, rarity)
		if abs(a - b) > 0.001:
			curve_match = false
			print("    rarity %d: ShieldTile banked %f, shim banked %f" % [rarity, a, b])
	_check("shim banks identically to ShieldTile across rarities (curve, not linear)", curve_match)

	# 3. The Mythic curve multiplier is the tuned 10.0x, not the old linear
	# 1 + 4*0.5 = 3.0x - proves the deprecated scaling is gone.
	var mythic_bank = _bank_for(canonical, HexTile.Rarity.MYTHIC)
	_check("Mythic Shield banks on the 10x curve (got %f for 100 energy), not the old ~3x linear" % mythic_bank,
		mythic_bank > 900.0)

	# 4. A serialized ShieldGeneratorTile round-trips and still behaves.
	var sm = SaveManagerScript.new()
	var original = ShieldGeneratorTileScript.new()
	original.rarity = HexTile.Rarity.RARE
	var restored = sm._deserialize_tile(JSON.parse_string(JSON.stringify(sm._serialize_tile(original))))
	_check("a serialized ShieldGeneratorTile round-trips as a Shield Generator",
		restored != null and restored.tile_type == "Shield Generator")
	if restored:
		_check("the round-tripped shield banks on the curve",
			abs(_bank_for(restored, HexTile.Rarity.RARE) - _bank_for(canonical, HexTile.Rarity.RARE)) < 0.001)

	if failures == 0:
		print("PASS: Shield Generator consolidated onto ShieldTile - one class, the tuned curve, no mixed-system collision")
	get_tree().quit(0 if failures == 0 else 1)
