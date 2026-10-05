extends Node
# Windowed. Draw calls and frame cost PER INSTANCE of each effect type, with N copies on screen at once.
#   godot --path . res://scripts/debug/FxCostProbe.tscn

const N = 25
var world: Node2D

func _draws() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

func _pos(i: int) -> Vector2:
	return Vector2(80 + (i % 8) * 120, 70 + (i / 8) * 110)

func _measure(label: String, spawn: Callable) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var base = _draws()
	var nodes0 = get_tree().get_node_count()
	var made: Array = []
	for i in range(N):
		var n = spawn.call(i)
		if n != null:
			made.append(n)
	var t0 = Time.get_ticks_usec()
	for f in range(4):
		await get_tree().process_frame
	var peak = 0
	for f in range(6):
		await get_tree().process_frame
		peak = max(peak, _draws())
	var nodes1 = get_tree().get_node_count()
	print("FXCOST %-26s draws/instance=%5.1f  nodes/instance=%5.1f" % [label, float(peak - base) / N, float(nodes1 - nodes0) / N])
	for n in made:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _ready():
	world = Node2D.new()
	add_child(world)
	var cam = Camera2D.new()
	cam.position = Vector2(480, 200)
	cam.zoom = Vector2(1.4, 1.4)
	world.add_child(cam)
	var E = EnergyPacket.SynergyType

	await _measure("baseline (nothing)", func(i): return null)
	await _measure("LootPickup (tile)", func(i):
		var lp = load("res://scripts/entities/LootPickup.gd").new()
		lp.tile_data = load("res://scripts/tiles/AmplifierTile.gd").new()
		world.add_child(lp)
		lp.global_position = _pos(i)
		return lp)
	await _measure("DeathExplosion", func(i):
		var d = load("res://scripts/visuals/DeathExplosion.gd").new()
		world.add_child(d)
		d.global_position = _pos(i)
		return d)
	await _measure("ElementalPuddle (plain)", func(i):
		var p = load("res://scripts/attacks/ElementalPuddle.gd").new()
		p.setup(60.0, 6.0, 100.0, {E.EXPLOSION: 1.0}, true)
		world.add_child(p)
		p.global_position = _pos(i)
		return p)
	await _measure("ElementalPuddle (fire)", func(i):
		var p = load("res://scripts/attacks/ElementalPuddle.gd").new()
		p.setup(60.0, 10.0, 100.0, {E.FIRE: 1.0}, true, 0.0, 1.0)
		world.add_child(p)
		p.global_position = _pos(i)
		return p)
	await _measure("MortarShell in flight", func(i):
		var sh = load("res://scripts/attacks/MortarShell.gd").new()
		world.add_child(sh)
		sh.setup(_pos(i) + Vector2(0, -80), _pos(i), 4.0, 3000.0, {E.EXPLOSION: 3000.0}, true, null)
		sh._elapsed = 2.0
		return sh)
	await _measure("MineEmitter (flame+volley)", func(i):
		var em = load("res://scripts/attacks/MineEmitter.gd").new()
		world.add_child(em)
		em.global_position = _pos(i)
		em.setup(5.0, 100.0, 300.0, 100.0, 650.0, 4, null, {"color": Color.WHITE, "dominant": 3, "ratios": {}, "by_player": true, "source": null})
		return em)
	await _measure("LightningChainVisual", func(i):
		var lc = load("res://scripts/visuals/LightningChainVisual.gd").new()
		world.add_child(lc)
		lc.setup([_pos(i), _pos(i) + Vector2(60, 20), _pos(i) + Vector2(110, -10)], Color(1, 0.95, 0.4))
		return lc)
	await _measure("PulseRingVisual", func(i):
		var pr = load("res://scripts/attacks/PulseRingVisual.gd").new()
		world.add_child(pr)
		pr.global_position = _pos(i)
		pr.setup(80.0, Color(0.4, 1, 0.4), 3.0)
		return pr)
	get_tree().quit()
