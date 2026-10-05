extends Node
# Which enemy-role starter torsos (role x rarity) are non-viable, and why?
const V = preload("res://scripts/core/ComponentViability.gd")
const C = preload("res://scripts/core/ComponentEquipment.gd")
func _ready():
	var roles = ["", "sniper", "brawler", "scout", "diver", "ambusher", "flamethrower", "jammer", "support", "commander", "anti_missile", "remediation"]
	var bad = 0
	var total = 0
	for role in roles:
		for rarity in range(5):
			total += 1
			var t = C.create_starter_torso(role, rarity)
			var probs = V.problems(t)
			if not probs.is_empty():
				bad += 1
				print("SWEEP role=%-12s rarity=%d  %s" % [role if role != "" else "(player)", rarity, str(probs)])
	print("SWEEP total=%d non-viable=%d" % [total, bad])
	get_tree().quit()
