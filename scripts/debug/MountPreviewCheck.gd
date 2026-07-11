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

	# --- Mythic Mortar pattern label ---
	var mythic = WeaponMountTileScript.new()
	mythic.rarity = HexTile.Rarity.MYTHIC
	mythic.mythic_pattern = 4
	popup.show_for(mythic, [{"mount": mythic, "packet": packet, "step": 0, "bank_mode": ""}], 0.25, Vector2(100, 100))
	if not ("Mortar" in popup.info.text):
		push_error("FAIL: mythic mortar mount should label its pattern, got '%s'" % popup.info.text)
		failures += 1
	else:
		print("3) mortar pattern labeled: ", popup.info.text.split("\n")[0])

	if failures == 0:
		print("PASS: mount hover preview reports the simulated truth")
	get_tree().quit(0 if failures == 0 else 1)
