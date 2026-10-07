extends Node

# MechStatusGraph: glyph classification (including subclasses), tile/limb state rules, hex fit, and that a full
# draw over a bare Mech with damaged/offline/fried tiles runs without script errors.

const GraphScript = preload("res://scripts/ui/MechStatusGraph.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _tile(path: String):
	return load(path).new()

func _ready():
	var K = GraphScript.Kind
	var S = GraphScript.State
	_check("actuator -> ACTUATOR", GraphScript.kind_of(_tile("res://scripts/tiles/ActuatorTile.gd")) == K.ACTUATOR)
	_check("jumpjet -> JUMPJET", GraphScript.kind_of(_tile("res://scripts/tiles/JumpjetTile.gd")) == K.JUMPJET)
	_check("maneuvering thruster -> JUMPJET", GraphScript.kind_of(_tile("res://scripts/tiles/ManeuveringThrusterTile.gd")) == K.JUMPJET)
	_check("weapon mount -> WEAPON", GraphScript.kind_of(_tile("res://scripts/tiles/WeaponMountTile.gd")) == K.WEAPON)
	_check("lance mount -> WEAPON", GraphScript.kind_of(_tile("res://scripts/tiles/LanceMountTile.gd")) == K.WEAPON)
	_check("missile rack -> WEAPON", GraphScript.kind_of(_tile("res://scripts/tiles/MissileRackTile.gd")) == K.WEAPON)
	_check("component link -> LINK", GraphScript.kind_of(_tile("res://scripts/tiles/ComponentLinkTile.gd")) == K.LINK)
	_check("heal beacon -> MODULE", GraphScript.kind_of(_tile("res://scripts/tiles/HealBeaconTile.gd")) == K.MODULE)
	_check("shield generator -> MODULE", GraphScript.kind_of(_tile("res://scripts/tiles/ShieldGeneratorTile.gd")) == K.MODULE)
	_check("an amplifier is not drawn", GraphScript.kind_of(_tile("res://scripts/tiles/AmplifierTile.gd")) == K.NONE)
	_check("a splitter is not drawn", GraphScript.kind_of(_tile("res://scripts/tiles/SplitterTile.gd")) == K.NONE)

	# Brand variants (subclasses living under tiles/brands/) inherit their base tile's glyph.
	var brand_checked := 0
	var brand_ok := 0
	var dir = DirAccess.open("res://scripts/tiles/brands")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".gd"):
				var t = load("res://scripts/tiles/brands/" + f).new()
				brand_checked += 1
				var base = t.get_script().get_base_script()
				var base_file: String = base.resource_path.get_file() if base else ""
				var expected = GraphScript.KIND_BY_FILE.get(base_file, K.NONE)
				if GraphScript.kind_of(t) == expected:
					brand_ok += 1
	_check("brand variants match their base tile's glyph (%d of %d)" % [brand_ok, brand_checked], brand_ok == brand_checked)

	var t = _tile("res://scripts/tiles/WeaponMountTile.gd")
	_check("fresh tile is OK", GraphScript.state_of(t) == S.OK)
	t.hp = t.max_hp * 0.59
	_check("under 60% HP is DAMAGED", GraphScript.state_of(t) == S.DAMAGED)
	t.hp = t.max_hp * 0.6
	_check("exactly 60% is still OK", GraphScript.state_of(t) == S.OK)
	t.is_disabled = true
	_check("disabled is REBOOTING", GraphScript.state_of(t) == S.REBOOTING)
	t.power_lost = true
	_check("power lost wins: LOST", GraphScript.state_of(t) == S.LOST)

	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.COMMON)
	_check("untouched limb is fine", GraphScript.limb_state(comp) == 0)
	comp.max_integrity = 100.0
	comp.integrity = 49.0
	_check("limb under half integrity is hurt", GraphScript.limb_state(comp) == 1)
	comp.is_broken = true
	_check("broken limb is destroyed", GraphScript.limb_state(comp) == 2)

	var pts: Array = []
	for q in range(-2, 3):
		for r in range(-2, 3):
			pts.append(GraphScript.hex_world(q, r))
	var inner := Rect2(10, 10, 80, 60)
	var f2 = GraphScript.fit(pts, inner)
	var inside := true
	for p in pts:
		var px: Vector2 = p * float(f2["scale"]) + (f2["origin"] as Vector2)
		inside = inside and inner.grow(0.01).has_point(px)
	_check("all hex centres land inside the box (scale %.2f)" % float(f2["scale"]), inside)
	var one = GraphScript.fit([Vector2.ZERO], inner)
	_check("a single tile is capped, not blown up (scale %.1f)" % float(one["scale"]), float(one["scale"]) <= 7.0)

	# Full draw over a bare Mech with a mix of states.
	var mech = MechScript.new()
	add_child(mech)
	var arm = ComponentEquipmentScript.new(HexTile.BodySlot.ARM_L, HexTile.Rarity.COMMON)
	var coords = [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(0, 1), HexCoord.new(-1, 1), HexCoord.new(1, -1)]
	var paths = ["ActuatorTile", "JumpjetTile", "WeaponMountTile", "ComponentLinkTile", "HealBeaconTile"]
	for i in range(coords.size()):
		var tt = _tile("res://scripts/tiles/%s.gd" % paths[i])
		if i == 1: tt.hp = tt.max_hp * 0.3
		if i == 2: tt.is_disabled = true
		if i == 3: tt.power_lost = true
		arm.hex_grid.add_tile(coords[i], tt)
	mech.components[HexTile.BodySlot.ARM_L] = arm
	var broken_leg = ComponentEquipmentScript.new(HexTile.BodySlot.LEG_L, HexTile.Rarity.COMMON)
	broken_leg.is_broken = true
	mech.components[HexTile.BodySlot.LEG_L] = broken_leg
	var main_stub = Node.new()
	main_stub.set_script(load("res://scripts/debug/StatusGraphMainStub.gd"))
	main_stub.player = mech
	add_child(main_stub)
	var g = GraphScript.new()
	g.main = main_stub
	add_child(g)
	for k in range(6):
		await get_tree().process_frame
		g._t += 0.2
		g.queue_redraw()
	_check("the graph draws a mixed-state mech without errors", g.visible)
	print("MechStatusGraphCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
