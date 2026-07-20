extends Node

# Regression harness for: "auto-generated torsos need a way to place all the
# peripheral links - if it's single rows of hex slots, links are opaque, you
# can't stack them in a straight line, you need space to get around, so even
# with the correct number of hexes the geometry can stop you linking to all."
#
# Two guarantees under test, across every role variant and rarity:
#   1. The torso footprint includes the full 6-neighbour hub around the core
#      (routing room for a Splitter to fan power out).
#   2. All six OUTBOUND peripheral links (both arms, both legs, head,
#      backpack) exist, sit on distinct hexes, and each is REACHABLE from the
#      core through open (untiled) hexes without passing through another
#      opaque link - i.e. every limb can actually be powered.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

# BFS from the core through hexes that are EMPTY (open routing space); the
# target link hex itself is the goal. Never steps onto another tile, so a
# link only counts as reachable if it has its own open corridor.
func _reachable_through_open(torso, target: HexCoord) -> bool:
	var origin = HexCoord.new(0, 0)
	var seen = {"%d,%d" % [origin.q, origin.r]: true}
	var queue = [origin]
	var head = 0
	while head < queue.size():
		var curr = queue[head]
		head += 1
		for d in range(6):
			var n = curr.neighbor(d)
			var key = "%d,%d" % [n.q, n.r]
			if seen.has(key):
				continue
			if not torso._valid_hex_set.has(torso._hex_key(n.q, n.r)):
				continue
			if n.q == target.q and n.r == target.r:
				return true # reached the goal link
			if torso.hex_grid.has_tile(n):
				continue # some other tile - opaque, can't route through it
			seen[key] = true
			queue.append(n)
	return false

func _find_link_hex(torso, target_slot: int) -> HexCoord:
	# ComponentLinkTile sets tile_type to "<slot> Link" (e.g. "L. Arm Link"),
	# so match on the reliable target_slot field, not a type string.
	for tile in torso.hex_grid.get_all_tiles():
		if "target_slot" in tile and tile.target_slot == target_slot:
			return tile.grid_position
	return null

func _ready():
	var HexTileCls = load("res://scripts/core/HexTile.gd")
	var limbs = [HexTileCls.BodySlot.ARM_L, HexTileCls.BodySlot.ARM_R, HexTileCls.BodySlot.LEG_L,
		HexTileCls.BodySlot.LEG_R, HexTileCls.BodySlot.HEAD, HexTileCls.BodySlot.BACKPACK]
	var roles = ["", "scout", "brawler", "sniper"]
	for role in roles:
		for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]:
			var torso = ComponentEquipmentScript.create_starter_torso(role, rarity)
			var tag = "role='%s' rarity=%d" % [role if role != "" else "default", rarity]

			# 1. Full 6-neighbour hub present.
			var hub_ok = true
			for d in range(6):
				var n = HexCoord.new(0, 0).neighbor(d)
				if not torso._valid_hex_set.has(torso._hex_key(n.q, n.r)):
					hub_ok = false
			_check("[%s] core hub: all 6 neighbours in the footprint" % tag, hub_ok)

			# 2. Every limb link exists, distinct, and independently reachable.
			var seen_hexes = {}
			var all_present = true
			var all_reachable = true
			var all_distinct = true
			for limb in limbs:
				var h = _find_link_hex(torso, limb)
				if h == null:
					all_present = false
					continue
				var hk = "%d,%d" % [h.q, h.r]
				if seen_hexes.has(hk):
					all_distinct = false
				seen_hexes[hk] = true
				if not _reachable_through_open(torso, h):
					all_reachable = false
			_check("[%s] all 6 limb links present" % tag, all_present)
			_check("[%s] all 6 limb links on distinct hexes" % tag, all_distinct)
			_check("[%s] every limb link reachable from core through open hexes" % tag, all_reachable)

	if failures == 0:
		print("PASS: auto-generated torsos give every peripheral link its own reachable corridor")
	get_tree().quit(0 if failures == 0 else 1)
