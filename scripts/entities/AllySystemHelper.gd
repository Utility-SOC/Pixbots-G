class_name AllySystemHelper
extends RefCounted

# Shared by AegisShieldPulseSystem/HealBeaconSystem/CloakSystem (all
# composed-RefCounted-helper classes taking `mech: Mech`) - each one had its
# own byte-for-byte copy of "which allies does this ability affect" (the
# player's own beacon/pulse/cloak-share reaches their companion drones; an AI
# mech's reaches its squad, the "enemy" group). Split out after a full-
# codebase audit flagged the triplication; HealBeaconSystem's copy was also
# missing the is_inside_tree() guard the other two had, a real (if unlikely)
# null-deref risk on a mech that's been queue_free'd but not yet removed from
# the tree - fixed here for all three at once.
static func get_allies(mech: Mech) -> Array:
	if mech.is_player:
		var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
		if main and "drone_nodes" in main:
			return main.drone_nodes.values()
		return []
	return EntityCache.get_group("enemy")
