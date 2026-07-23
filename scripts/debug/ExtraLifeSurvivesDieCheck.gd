extends Node

# Regression harness for: "this is not working, in the screenshot I sent
# you I had two lives left but was dead dead."
#
# Root cause: Mech.die() emits `died` (which Main._on_player_died()
# listens to and revives in place - synchronously resetting is_dead back
# to false and restoring HP - when player_lives_remaining > 1), but die()
# never checked whether that happened. It just kept running past the
# signal emission and unconditionally called queue_free() a few lines
# later regardless of what any `died` listener just did. So the extra-life
# revival correctly reset is_dead/HP... and then the mech got destroyed
# anyway a moment later - "dead dead" with lives still showing on the HUD.
#
# The previous ExtraLivesCheck.gd only ever did SOURCE-TEXT string matching
# on Main.gd (grepping for the right lines existing) - it never actually
# simulated a death, which is exactly how this slipped through. This check
# exercises the real die() behavior end to end instead.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	_test_revived_mech_survives_die()
	_test_unrevived_mech_still_dies_normally()

	if failures == 0:
		print("PASS: a mech revived by a `died` signal listener (extra lives) actually survives die() now")
	get_tree().quit(0 if failures == 0 else 1)

# Mirrors exactly what Main._on_player_died() does when player_lives_
# remaining > 1: reset is_dead back to false, synchronously, in response
# to the `died` signal - simulating an extra life being consumed.
func _test_revived_mech_survives_die():
	var mech = Mech.new()
	mech.is_player = true
	mech.components = {}
	add_child(mech)

	mech.died.connect(func():
		mech.is_dead = false
		mech.hp = mech.max_hp
	)

	mech.die()

	_check("a mech revived by its `died` listener is NOT queued for deletion",
		not mech.is_queued_for_deletion())
	_check("is_dead correctly reflects the revival (false), not the destroyed state",
		not mech.is_dead)

	mech.queue_free()

# Sanity check that the fix didn't break the NORMAL (no extra life left)
# death path - a mech with no listener resetting is_dead must still die.
func _test_unrevived_mech_still_dies_normally():
	var mech = Mech.new()
	mech.is_player = false
	mech.components = {}
	add_child(mech)

	mech.die()

	_check("a mech with no revival listener IS queued for deletion (normal death still works)",
		mech.is_queued_for_deletion())
	_check("is_dead stays true for a normal (non-revived) death",
		mech.is_dead)
