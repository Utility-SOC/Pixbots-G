extends Node

# Unit harness for the Garage weapon-mount hover preview
# (MountPreviewPopup.gd): a powered mount must report the simulated
# packet's real numbers (pattern name, damage after mount multipliers,
# element split, bank tag), an unpowered mount must say NO ENERGY, and a
# Mythic Mortar mount must label its pattern.

const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const PopupScript = preload("res://scripts/ui/MountPreviewPopup.gd")

func _ready():
	var failures = 0
	var popup = PopupScript.new()
	add_child(popup)

	# --- powered RARE mount, FIRE-heavy packet, plus a bank entry ---
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	var packet = EnergyPacket.new(100.0)
	packet.synergies.clear()
	packet.synergies[EnergyPacket.SynergyType.FIRE] = 70.0
	packet.synergies[EnergyPacket.SynergyType.RAW] = 30.0
	packet.charge_required = 4.0
	var entries = [
		{"mount": mount, "packet": packet, "step": 0, "bank_mode": ""},
		{"mount": mount, "packet": packet, "step": 0, "bank_mode": "bank"},
	]
	popup.show_for(mount, entries, 0.25, Vector2(100, 100))
	# expected damage: 100 * dmg_mult(1.0) * power_mult(RARE 1.5) = 150
	var txt = popup.info.text
	if not popup.visible or not ("150" in txt) or not ("FIRE 70%" in txt) or not ("+BANK" in txt) or not ("1.0s" in txt):
		push_error("FAIL: powered preview text wrong: '%s'" % txt)
		failures += 1
	else:
		print("1) powered mount: ", txt.replace("\n", " | "))

	# --- unpowered mount ---
	popup.show_for(mount, [], 0.25, Vector2(100, 100))
	if not ("NO ENERGY" in popup.info.text):
		push_error("FAIL: unpowered mount should say NO ENERGY, got '%s'" % popup.info.text)
		failures += 1
	else:
		print("2) unpowered mount reports NO ENERGY")

	# --- the stage hosts a REAL Projectile with combat visuals, neutered ---
	popup.show_for(mount, [{"mount": mount, "packet": packet, "step": 0, "bank_mode": ""}], 0.25, Vector2(100, 100))
	if popup._pool.size() != 1 or not (popup._pool[0] is Projectile):
		push_error("FAIL: stage should host exactly one real Projectile instance")
		failures += 1
	else:
		var proj = popup._pool[0]
		# Combat visuals live under Projectile.visual_node (shape polys,
		# fire/ice particles, trails - whatever this element builds).
		var visuals = proj.visual_node.get_child_count() if proj.get("visual_node") != null else 0
		var neutered = (proj.collision_layer == 0 and not proj.monitoring and not proj.is_in_group("projectile") and not proj.is_physics_processing())
		if visuals == 0 or not neutered:
			push_error("FAIL: preview projectile visual children=%d, neutered=%s" % [visuals, str(neutered)])
			failures += 1
		else:
			print("3) real Projectile on stage: %d combat visual node(s), physics/collision/groups all off" % visuals)

	# --- Mythic Mortar pattern label + shotgun volley count ---
	var mythic = WeaponMountTileScript.new()
	mythic.rarity = HexTile.Rarity.MYTHIC
	mythic.mythic_pattern = 4
	popup.show_for(mythic, [{"mount": mythic, "packet": packet, "step": 0, "bank_mode": ""}], 0.25, Vector2(100, 100))
	if not ("Mortar" in popup.info.text):
		push_error("FAIL: mythic mortar mount should label its pattern, got '%s'" % popup.info.text)
		failures += 1
	else:
		print("4) mortar pattern labeled: ", popup.info.text.split("\n")[0])
	mythic.mythic_pattern = 1
	popup.show_for(mythic, [{"mount": mythic, "packet": packet, "step": 0, "bank_mode": ""}], 0.25, Vector2(100, 100))
	if popup._pool.size() != 3:
		push_error("FAIL: shotgun preview should animate a 3-shot volley, got %d" % popup._pool.size())
		failures += 1
	else:
		print("5) shotgun pattern animates a 3-shot volley of real projectiles")

	if failures == 0:
		print("PASS: mount hover preview reports the simulated truth")
	get_tree().quit(0 if failures == 0 else 1)
