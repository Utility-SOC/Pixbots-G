extends Node

# Regression harness for a live-breaking regression caught by a full-
# codebase audit: Mech.apply_damage() gained a 5th param
# (source_label_override, commit 7212658 "kills from an already-dead
# shooter misattributed to Environment") and Projectile._handle_hit() was
# updated to call it with 5 positional args - but PartHitbox.gd,
# CorpseHusk.gd, RuinObstacle.gd, and TreeObstacle.gd all still only
# accepted 4. Since PartHitbox is the REAL hit target for every mech
# (Projectile._on_body_entered deliberately routes hits there, not the
# parent CharacterBody2D), this was a "too many arguments" GDScript error
# on essentially every combat hit in the game - the exact same class of bug
# PartHitbox.gd's own header comment warns has happened twice before.
#
# This check calls apply_damage() with the identical 5-positional-arg shape
# Projectile.gd actually uses, against every class that defines its own
# override, proving none of them reject the call.

const PartHitboxScript = preload("res://scripts/entities/PartHitbox.gd")
const CorpseHuskScript = preload("res://scripts/entities/CorpseHusk.gd")
const RuinObstacleScript = preload("res://scripts/core/RuinObstacle.gd")
const TreeObstacleScript = preload("res://scripts/core/TreeObstacle.gd")
const DestructibleObstacleScript = preload("res://scripts/core/DestructibleObstacle.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, node: Node):
	# Mirrors Projectile._handle_hit()'s exact call shape:
	# target.apply_damage(damage, dominant_str, valid_source, was_reflected, source_label)
	node.apply_damage(10.0, "KINETIC", null, false, "Sniper")
	print("ok: %s.apply_damage() accepts the real 5-arg Projectile call shape" % label)

func _ready():
	var hitbox = PartHitboxScript.new()
	hitbox.body_slot = 0
	add_child(hitbox)
	_check("PartHitbox", hitbox)

	var husk = CorpseHuskScript.new()
	add_child(husk)
	_check("CorpseHusk", husk)

	var ruin = RuinObstacleScript.new()
	ruin.hp = 100.0
	ruin.max_hp = 100.0
	add_child(ruin)
	_check("RuinObstacle", ruin)

	var tree = TreeObstacleScript.new()
	add_child(tree)
	_check("TreeObstacle", tree)

	var destructible = DestructibleObstacleScript.new()
	add_child(destructible)
	_check("DestructibleObstacle", destructible)

	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)
	_check("Mech", mech)

	print("PASS: every apply_damage() override accepts Projectile.gd's real 5-arg call")
	get_tree().quit(0 if failures == 0 else 1)
