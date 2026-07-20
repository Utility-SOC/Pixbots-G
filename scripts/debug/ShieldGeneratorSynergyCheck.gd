extends Node

# Regression harness for the ShieldTile/ShieldGeneratorTile divergence found
# by a full-codebase audit: both share tile_type "Shield Generator" (so
# Mech.gd's collection loop treats instances of either the same way), but
# only ShieldTile (Mythic Shield backpack) tracked shield_synergies -
# ShieldGeneratorTile (Command Suite backpack) silently never fed
# dominant_shield_synergy, so the AI's shield-counter-doctrine system never
# engaged for a mech built from the Command Suite. Proves both tiles now
# expose get_shield_synergies() with equivalent behavior (each keeping its
# own distinct energy multiplier curve).

const ShieldTileScript = preload("res://scripts/tiles/ShieldTile.gd")
const ShieldGeneratorTileScript = preload("res://scripts/tiles/ShieldGeneratorTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var lightning_packet = EnergyPacket.new(10.0, null)
	lightning_packet.synergies.clear()
	lightning_packet.synergies[EnergyPacket.SynergyType.LIGHTNING] = 10.0

	var shield = ShieldTileScript.new()
	shield.rarity = HexTile.Rarity.RARE
	shield.process_energy(lightning_packet.copy(), 0)
	var shield_syns = shield.get_shield_synergies()
	_check("ShieldTile.get_shield_synergies() has_method exists and returns LIGHTNING", shield_syns.has(EnergyPacket.SynergyType.LIGHTNING) and shield_syns[EnergyPacket.SynergyType.LIGHTNING] > 0.0)

	var shield_gen = ShieldGeneratorTileScript.new()
	shield_gen.rarity = HexTile.Rarity.RARE
	_check("ShieldGeneratorTile now has get_shield_synergies method", shield_gen.has_method("get_shield_synergies"))
	shield_gen.process_energy(lightning_packet.copy(), 0)
	var gen_syns = shield_gen.get_shield_synergies()
	_check("ShieldGeneratorTile.get_shield_synergies() returns LIGHTNING (was always empty before the fix)",
		gen_syns.has(EnergyPacket.SynergyType.LIGHTNING) and gen_syns[EnergyPacket.SynergyType.LIGHTNING] > 0.0)

	# Consuming synergies clears them, same contract as get_shield_energy()
	var second_read = shield_gen.get_shield_synergies()
	_check("ShieldGeneratorTile.get_shield_synergies() clears after read", second_read.is_empty())

	# CONSOLIDATED (2026-07-20): ShieldGeneratorTile's linear scaling was
	# deprecated - it's now a thin subclass of ShieldTile, so both use the
	# SAME tuned per-rarity curve. This used to assert they diverged; now it
	# asserts they're identical (the whole point of removing the mixed
	# system). See ShieldConsolidationCheck for the full consolidation proof.
	var shield_energy = shield.get_shield_energy()
	var gen_energy_tile = ShieldGeneratorTileScript.new()
	gen_energy_tile.rarity = HexTile.Rarity.RARE
	gen_energy_tile.process_energy(lightning_packet.copy(), 0)
	var gen_energy = gen_energy_tile.get_shield_energy()
	_check("ShieldGeneratorTile now banks identically to ShieldTile (%.2f == %.2f) - one canonical curve" % [shield_energy, gen_energy],
		abs(shield_energy - gen_energy) < 0.001)

	if failures == 0:
		print("PASS: ShieldGeneratorTile consolidated onto ShieldTile - shared synergy tracking AND shared curve")
	get_tree().quit(0 if failures == 0 else 1)
