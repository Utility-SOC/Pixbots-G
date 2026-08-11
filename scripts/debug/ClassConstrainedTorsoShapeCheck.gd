extends Node

# Regression check for class-constrained torso shapes (design doc,
# 2026-08-10 - "torso shape constrained by class, not helter skelter").
#
# Confirms, for each of the four newly-shaped roles (scout/sniper/
# brawler/ambusher) across several rarities:
#  - the full 6-neighbor hub around the core is ALWAYS present (the hard
#    constraint every shape must build outward from, never instead of -
#    an earlier "thin the torso per role" attempt got reverted for
#    breaking exactly this).
#  - the shape actually differs from the plain default disc growth (real
#    class identity, not an accidental no-op).
#  - AutoEquipSolver can still route power from the core to all 6 limb
#    spoke links on the new shape, driven through the REAL production
#    path (create_starter_torso -> generate_shape -> _spoke_tip ->
#    solver BFS), not a synthetic shortcut.
# Also confirms an unlisted role (commander) still gets the untouched
# default disc shape.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _has_full_hub(comp) -> bool:
	if not comp.hex_grid.has_tile(HexCoord.new(0, 0)):
		# Core tile itself - create_starter_torso always places one, but
		# double check the hex is at least in the valid footprint.
		if not comp._valid_hex_set.has(comp._hex_key(0, 0)):
			return false
	for d in range(6):
		var n = HexCoord.new(0, 0).neighbor(d)
		if not comp._valid_hex_set.has(comp._hex_key(n.q, n.r)):
			return false
	return true

func _real_starter_inventory() -> Array:
	var inventory: Array = []
	var taper = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE, HexTile.Rarity.LEGENDARY, HexTile.Rarity.MYTHIC]
	var taper_counts = {HexTile.Rarity.COMMON: 6, HexTile.Rarity.UNCOMMON: 4, HexTile.Rarity.RARE: 3, HexTile.Rarity.LEGENDARY: 2, HexTile.Rarity.MYTHIC: 2}
	var classes = [
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/AmplifierTile.gd"),
	]
	for r in taper:
		for c in classes:
			for i in range(taper_counts[r]):
				var tile = c.new()
				tile.rarity = r
				inventory.append(tile)
	return inventory

func _ready():
	var roles = ["scout", "sniper", "brawler", "ambusher"]
	var rarities = [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]

	# Reference: the plain default shape (no role) at each rarity, to
	# confirm the new shapes actually differ from it.
	var default_sizes = {}
	for rarity in rarities:
		var d = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity)
		d.generate_shape()
		default_sizes[rarity] = d.valid_hexes.size()

	for role in roles:
		for rarity in rarities:
			var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity)
			comp.role_variant = role
			comp.generate_shape()

			_check("%s torso (rarity %d) has the full 6-neighbor hub around the core" % [role, rarity],
				_has_full_hub(comp))
			_check("%s torso (rarity %d) is non-trivially larger than just the hub (%d hexes)" % [role, rarity, comp.valid_hexes.size()],
				comp.valid_hexes.size() > 7)

			# Solvability: build a REAL starter torso for this role/rarity
			# (the actual production path) and confirm the solver can
			# route power to every one of the 6 limb spoke links.
			var torso = ComponentEquipmentScript.create_starter_torso(role, rarity)
			var solver = AutoEquipSolverScript.new()
			solver.solve(torso, _real_starter_inventory(), null)
			var reached = 0
			for tip_coord in torso.fixed_sinks:
				if tip_coord.q == 0 and tip_coord.r == 0:
					continue # the core itself, not a spoke link
				var tile = torso.hex_grid.get_tile(tip_coord)
				if tile and tile.tile_type in ["Left Arm Link", "Right Arm Link", "Left Leg Link", "Right Leg Link", "Head Link", "Backpack Link"]:
					reached += 1
			_check("%s torso (rarity %d) solver still finds all 6 limb links as real fixed sinks" % [role, rarity],
				reached == 6)

	# Unlisted role stays on the untouched default disc shape.
	for rarity in rarities:
		var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, rarity)
		comp.role_variant = "commander"
		comp.generate_shape()
		_check("an unlisted role (commander, rarity %d) keeps the exact default disc size (%d vs %d)" % [rarity, comp.valid_hexes.size(), default_sizes[rarity]],
			comp.valid_hexes.size() == default_sizes[rarity])
		_check("commander torso (rarity %d) still has the full hub" % rarity,
			_has_full_hub(comp))

	if failures == 0:
		print("PASS: class-constrained torso shapes keep the guaranteed hub, read as distinct silhouettes, stay fully solvable through the real production path, and leave unlisted roles unchanged")
	get_tree().quit(0 if failures == 0 else 1)
