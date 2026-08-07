extends Node

# Regression harness for GarageTestRange's opt-in "Batch Renderer
# (experimental)" toggle - proves the parallel ProjectileBatchPool system
# is wired correctly through the REAL Test Range UI (not just in
# isolation, see ProjectileBatchPoolCheck.gd for that), and - just as
# importantly - that it's genuinely OFF by default and genuinely
# alternate, not a silent replacement of the real firing path.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const GarageTestRangeScript = preload("res://scripts/ui/GarageTestRange.gd")

func _count_real_projectiles(world: Node) -> int:
	var n = 0
	for c in world.get_children():
		if c.is_in_group("projectile"):
			n += 1
	return n

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	var active: Array[int] = [0]
	core.active_faces = active
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount)

	player.equip_component(torso)
	for slot in player.components.keys().duplicate():
		if slot != HexTile.BodySlot.TORSO:
			player.unequip_component(slot)
	player._recalculate_grid()

	var range_popup = GarageTestRangeScript.new()
	range_popup.setup(player)
	add_child(range_popup)

	_check("batch toggle defaults to OFF (real path is the default, unaffected by this feature existing)",
		range_popup._batch_toggle != null and range_popup._batch_toggle.button_pressed == false)
	_check("the batch pool itself was constructed and wired to the dummy", range_popup._batch_pool != null)

	# --- Toggle OFF (default): fires a real Projectile, batch pool untouched ---
	var real_before = _count_real_projectiles(range_popup._world_root)
	var batch_before = range_popup._batch_pool.live_count()
	range_popup._fire_selected()
	_check("toggle OFF: FIRE still spawns a real Projectile (existing behavior untouched)",
		_count_real_projectiles(range_popup._world_root) == real_before + 1)
	_check("toggle OFF: the batch pool received nothing", range_popup._batch_pool.live_count() == batch_before)

	# --- Toggle ON: fires into the batch pool instead, no real Projectile ---
	range_popup._batch_toggle.button_pressed = true
	var real_before2 = _count_real_projectiles(range_popup._world_root)
	range_popup._fire_selected()
	_check("toggle ON: FIRE does NOT spawn a real Projectile",
		_count_real_projectiles(range_popup._world_root) == real_before2)
	_check("toggle ON: FIRE spawned into the batch pool instead", range_popup._batch_pool.live_count() == batch_before + 1)

	# --- Real flight + real hit through the batch pool, driven by the
	# range's own _process (same wall-clock-wait pattern TestRangeCheck.gd
	# already uses for the real-Projectile path). ---
	var dummy = range_popup._dummy
	var waited = 0.0
	while waited < 3.0 and dummy.hp >= dummy.max_hp:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var dealt = dummy.max_hp - dummy.hp
	_check("a batch-pool shot actually flew and hit the dummy for real damage within 3s (%.0f dealt after %.2fs)" % [dealt, waited],
		dealt > 0.0)

	if failures == 0:
		print("PASS: Test Range's batch-pool toggle is off by default, doesn't touch the real Projectile path, and genuinely fires/hits through the parallel system when enabled")
	get_tree().quit(0 if failures == 0 else 1)
