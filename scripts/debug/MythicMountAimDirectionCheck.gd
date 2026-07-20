extends Node

# Regression harness for: "for mythic weapon mounts, I want to choose the
# direction relative to the mouse that projectiles come from (making it so
# mythics can be mounted anywhere easily)."
#
# WeaponMountTile.mythic_aim_direction (0-5, Mythic-only, same 6-direction
# convention as every other directional tile config) now REPLACES the
# usual wiring-derived angle_offset in HexTile._fire_combined_projectile -
# a Mythic mount fires at the player's chosen fixed offset from the mouse
# regardless of which hex face happens to route power into it. Verifies:
# non-Mythic mounts are unaffected, direction 0 matches the old dead-on
# behavior, non-zero directions override the wiring-derived offset
# entirely (proven by feeding two DIFFERENT entry directions and getting
# the SAME fired angle), Beam mode is never affected, and the field
# survives serialization.

const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _fire_and_get_angle(mount, mech, entry_dir: int) -> float:
	var pkt = EnergyPacket.new(50.0, HexCoord.new(0, 0))
	pkt.direction = entry_dir
	var before = mech.get_children().filter(func(c): return c is ProjectileScript)
	mount._fire_combined_projectile(mech, pkt, 0)
	var after = mech.get_children().filter(func(c): return c is ProjectileScript)
	var new_ones = after.filter(func(p): return not before.has(p))
	if new_ones.is_empty():
		return -999.0
	return new_ones[0].direction.angle()

func _ready():
	# Deliberately NOT added to the scene tree: HexTile._fire_combined_
	# projectile does `if mech.get_parent(): mech.get_parent().add_child(proj)
	# else: mech.add_child(proj)` - keeping mech parentless routes fired
	# projectiles onto mech itself, the simplest place to read them back
	# from without needing a real running scene.
	var mech = MechScript.new()
	mech.is_player = true
	mech.global_position = Vector2.ZERO
	mech.last_aim_position = Vector2(0, -200) # mouse straight "up" (screen-space -Y)

	var mount = WeaponMountTileScript.new()
	mount.grid_position = HexCoord.new(0, 0)
	mount.body_slot = HexTile.BodySlot.TORSO

	# 1. Non-Mythic: aim direction field exists but must have NO effect -
	# wiring-derived offset still governs.
	mount.rarity = HexTile.Rarity.RARE
	mount.mythic_aim_direction = 3 # would be "fire backward" if honored
	var angle_common_dir0 = _fire_and_get_angle(mount, mech, 4) # forward_dir for TORSO is 4 (South)
	var angle_common_dir1 = _fire_and_get_angle(mount, mech, 0) # different entry -> different wiring offset
	_check("non-Mythic mount ignores mythic_aim_direction (wiring-derived offset still varies by entry dir)",
		abs(angle_common_dir0 - angle_common_dir1) > 0.01)

	# 2. Mythic, direction 0 (Mouse) matches the pre-existing dead-on-ish
	# behavior for the default forward-dir entry (no offset).
	mount.rarity = HexTile.Rarity.MYTHIC
	mount.mythic_aim_direction = 0
	var angle_mythic_dir0 = _fire_and_get_angle(mount, mech, 4)
	var mouse_angle = (mech.last_aim_position - mech.global_position).normalized().angle()
	_check("Mythic aim direction 0 fires dead-on at the mouse (%.3f vs mouse %.3f)" % [angle_mythic_dir0, mouse_angle],
		abs(angle_mythic_dir0 - mouse_angle) < 0.01)

	# 3. Mythic, non-zero direction OVERRIDES wiring entirely: two
	# DIFFERENT entry directions must now produce the SAME fired angle.
	mount.mythic_aim_direction = 2
	var angle_a = _fire_and_get_angle(mount, mech, 4)
	var angle_b = _fire_and_get_angle(mount, mech, 1)
	_check("Mythic aim direction 2 fires identically regardless of entry direction (wiring-independent)",
		abs(angle_a - angle_b) < 0.01)
	_check("...and that angle is actually offset from the mouse (not accidentally dead-on)",
		abs(angle_a - mouse_angle) > 0.5)

	# 4. Beam mode (pattern 3) always aims dead-on, aim_direction or not.
	mount.mythic_pattern = 3
	mount.mythic_aim_direction = 4
	var angle_beam = _fire_and_get_angle(mount, mech, 1)
	_check("Beam mode still always fires dead-on at the mouse regardless of aim direction",
		abs(angle_beam - mouse_angle) < 0.01)
	mount.mythic_pattern = 0

	# 5. Serialization round trip.
	var sm = SaveManagerScript.new()
	mount.mythic_aim_direction = 5
	var restored = sm._deserialize_tile(JSON.parse_string(JSON.stringify(sm._serialize_tile(mount))))
	_check("mythic_aim_direction survives the save/load round trip",
		restored != null and restored.mythic_aim_direction == 5)

	# 6. cycle_mythic_aim_direction wraps 0..5.
	mount.mythic_aim_direction = 5
	mount.cycle_mythic_aim_direction()
	_check("cycle_mythic_aim_direction wraps 5 -> 0", mount.mythic_aim_direction == 0)

	if failures == 0:
		print("PASS: Mythic weapon mounts fire at a player-chosen, wiring-independent angle relative to the mouse")
	get_tree().quit(0 if failures == 0 else 1)
