extends Node

# Fire needs Kinetic/Pierce backing (pure fire stalls ~130 px). Player solve
# (profile == null) must swap a spare Kinetic infuser in beside a placed Fire
# infuser when it did not place one. Pure fire stays melee by design, so
# enemy profile picks are NOT touched.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const SolverProfileScript = preload("res://scripts/ai/SolverProfile.gd")
const InfuserScript = preload("res://scripts/tiles/InfuserTile.gd")
const AmplifierScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterScript = preload("res://scripts/tiles/SplitterTile.gd")
const ConduitScript = preload("res://scripts/tiles/DirectionalConduitTile.gd")

func _infuser(el: int):
	var t = InfuserScript.new()
	t.rarity = HexTile.Rarity.COMMON
	t.secondary_synergy = el
	return t

func _placed_elements(comp) -> Array:
	var out = []
	for k in comp.hex_grid.grid.keys():
		var t = comp.hex_grid.grid[k]
		if t and t.tile_type == "Elemental Infuser":
			out.append(int(t.secondary_synergy))
	return out

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# 1. Player solve: fire + poison + kinetic infusers, plenty of filler.
	AutoEquipSolverScript._topology_cache.clear()
	var torso = ComponentEquipmentScript.create_starter_arm(false, "brawler", HexTile.Rarity.RARE)
	world.add_child(torso)
	var inv: Array = []
	inv.append(_infuser(EnergyPacket.SynergyType.FIRE))
	inv.append(_infuser(EnergyPacket.SynergyType.POISON))
	inv.append(_infuser(EnergyPacket.SynergyType.KINETIC))
	for i in range(30):
		var c = ConduitScript.new()
		c.rarity = HexTile.Rarity.COMMON
		inv.append(c)
	for i in range(3):
		var sp = SplitterScript.new()
		sp.rarity = HexTile.Rarity.COMMON
		inv.append(sp)
	var solver = AutoEquipSolverScript.new()
	solver.solve(torso, inv)
	var placed = _placed_elements(torso)
	var counts = {}
	for k in torso.hex_grid.grid.keys():
		var tt = torso.hex_grid.grid[k]
		if tt: counts[tt.tile_type] = counts.get(tt.tile_type, 0) + 1
	print("tiles placed: ", counts, " leftover inv: ", inv.size())
	print("player solve placed infuser elements: ", placed)
	var has_fire = placed.has(EnergyPacket.SynergyType.FIRE)
	var has_kin = placed.has(EnergyPacket.SynergyType.KINETIC)
	if has_fire and not has_kin:
		push_error("FAIL: Fire infuser placed without Kinetic backing")
		failures += 1
	elif not has_fire:
		print("(note: solver did not place the fire infuser on this layout; backing rule not exercised)")
	else:
		print("1) fire infuser is backed by a kinetic infuser")

	if failures == 0:
		print("PASS: kinetic backing for fire")
	get_tree().quit(0 if failures == 0 else 1)
