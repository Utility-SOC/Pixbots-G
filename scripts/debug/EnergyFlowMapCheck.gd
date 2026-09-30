extends Node

# Per-tile flow data (HexGridComponent.flow / flow_loops / sim_saturated) from
# the Rust sim and the GDScript fallback: powered vs unpowered tiles, loop
# detection on a recirculating path, and a clean line staying loop-free.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const ComponentLinkTileScript = preload("res://scripts/tiles/ComponentLinkTile.gd")
const ReflectorTileScript = preload("res://scripts/tiles/ReflectorTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _build(loop: bool):
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	core.active_faces.clear()
	core.active_faces.append(0)
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var r1 = ReflectorTileScript.new()
	r1.body_slot = HexTile.BodySlot.TORSO
	r1.rotation_steps = 3 if loop else 0
	torso.hex_grid.add_tile(HexCoord.new(1, 0), r1)
	if not loop:
		var sink = ComponentLinkTileScript.new(HexTile.BodySlot.ARM_L, true)
		sink.body_slot = HexTile.BodySlot.TORSO
		torso.hex_grid.add_tile(HexCoord.new(2, 0), sink)
	var idle = ReflectorTileScript.new()
	idle.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 1), idle)
	return [torso, core]

func _run(loop: bool, gd: bool):
	var b = _build(loop)
	var torso = b[0]
	var core = b[1]
	var pk = core.generate_energy(torso.hex_grid)
	for p in pk:
		p.position = HexCoord.new(0, 0)
	var mech = MechScript.new()
	torso.hex_grid.reset_flow()
	mech._simulate_grid(torso.hex_grid, pk, gd)
	mech.free()
	return torso.hex_grid

func _ready():
	for gd in [false, true]:
		var tag = "gdscript" if gd else "rust"
		var g = _run(false, gd)
		_check("%s: fed tile is powered" % tag, g.is_powered(Vector2i(1, 0)))
		_check("%s: link at the end is powered" % tag, g.is_powered(Vector2i(2, 0)))
		_check("%s: isolated tile is unpowered" % tag, not g.is_powered(Vector2i(0, 1)))
		_check("%s: clean line has no loops or saturation" % tag, g.flow_loops.is_empty() and not g.sim_saturated)
		var l = _run(true, gd)
		_check("%s: recirculating path hits the step cap" % tag, l.sim_saturated)
		if not gd:
			_check("rust: recirculating reflector flagged as loop", l.flow_loops.has(Vector2i(1, 0)))
		_check("%s: loop visits are counted" % tag, l.flow.get(Vector2i(1, 0), {}).get("visits", 0) > 10)
	print("flow map check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
