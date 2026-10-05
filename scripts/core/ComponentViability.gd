extends RefCounted

# "Viable construction" for a body part: every part that exists in the game (dropped,
# bought, saved) must be fully wired and routable, because nothing in the garage lets the
# player fix a broken one by hand.
#
#   Torso:    Core Reactor at (0,0); the full 6-neighbour hub around it; a link for each of the
#             six limbs (both arms, both legs, head, backpack) on its own hex; an Accessory
#             Return (inbound sink for head/backpack energy); every one of those REACHABLE from
#             the core through open (untiled) hexes without crossing another tile - links are
#             opaque, so each needs its own corridor.
#   Others:   Energy Intake at (0,0) pointing into the shape, plus the slot's payload sink
#             (arm: Weapon Mount, leg: Actuator, head/backpack: Torso Return), reachable from
#             the intake through the footprint.
#
# problems(comp) lists what is wrong; ensure(comp) repairs it (idempotent, only touches broken
# parts) and returns what is still wrong (should be empty).

const POWER_SOURCES = ["Energy Intake", "Microcore", "Core Reactor"]
const SPOKES = {
	HexTile.BodySlot.ARM_R: 0, HexTile.BodySlot.LEG_R: 1, HexTile.BodySlot.LEG_L: 2,
	HexTile.BodySlot.ARM_L: 3, HexTile.BodySlot.HEAD: 4, HexTile.BodySlot.BACKPACK: 5,
}
# The six hexes at distance 2 BETWEEN the spokes: off every spoke ray, adjacent to two hub hexes.
const BETWEEN_SPOKES = [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(-1, 2)]

static func _in_shape(comp, q: int, r: int) -> bool:
	return comp._valid_hex_set.has(comp._hex_key(q, r))

static func _force_add(comp, q: int, r: int) -> void:
	if _in_shape(comp, q, r):
		return
	comp.valid_hexes.append(HexCoord.new(q, r))
	comp._valid_hex_set[comp._hex_key(q, r)] = true

# Opaque tiles that energy stops at: every registered sink (limb links, core, mounts) and the
# Accessory Return. Conduits, splitters, amplifiers etc. are NOT blockers - they are routing
# the player or solver places ON the corridors.
static func _is_blocker(comp, h: HexCoord) -> bool:
	if not comp.hex_grid.has_tile(h):
		return false
	if comp.is_fixed_sink(h):
		return true
	return comp.hex_grid.get_tile(h).tile_type == "Accessory Return"

# BFS from `start` through the footprint, never stepping onto an opaque tile; true if `goal`
# (a hex, usually itself a sink) is reached. So a sink only counts as routable when it has its
# own corridor that does not run through another sink.
static func reachable(comp, start: HexCoord, goal: HexCoord) -> bool:
	var seen = {Vector2i(start.q, start.r): true}
	var queue = [start]
	var head = 0
	while head < queue.size():
		var curr = queue[head]
		head += 1
		for d in range(6):
			var n = curr.neighbor(d)
			var key = Vector2i(n.q, n.r)
			if seen.has(key):
				continue
			if not _in_shape(comp, n.q, n.r):
				continue
			if n.q == goal.q and n.r == goal.r:
				return true
			if _is_blocker(comp, n):
				continue
			seen[key] = true
			queue.append(n)
	return false

static func _tile_at_origin(comp):
	return comp.hex_grid.get_tile(HexCoord.new(0, 0)) if comp.hex_grid.has_tile(HexCoord.new(0, 0)) else null

static func _link_for(comp, slot: int):
	for t in comp.hex_grid.get_all_tiles():
		if "target_slot" in t and t.target_slot == slot and t.tile_type != "Accessory Return" and t.tile_type != "Torso Return" and t.tile_type != "Energy Intake":
			return t
	return null

static func _first_of_type(comp, tile_type: String):
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type == tile_type:
			return t
	return null

static func problems(comp) -> Array:
	var out: Array = []
	if comp == null or comp.hex_grid == null:
		return ["no grid"]
	var origin = HexCoord.new(0, 0)
	if comp.slot_type == HexTile.BodySlot.TORSO:
		var core = _tile_at_origin(comp)
		if core == null or core.tile_type != "Core Reactor":
			out.append("no Core Reactor at the origin")
		for d in range(6):
			var n = origin.neighbor(d)
			if not _in_shape(comp, n.q, n.r):
				out.append("hub hex %d missing from the footprint" % d)
		for slot in SPOKES:
			var link = _link_for(comp, slot)
			if link == null:
				out.append("no link for slot %d" % slot)
			elif not reachable(comp, origin, link.grid_position):
				out.append("link for slot %d is not routable from the core" % slot)
			elif not comp.is_fixed_sink(link.grid_position):
				out.append("link for slot %d is not registered as a sink" % slot)
		var ret = _first_of_type(comp, "Accessory Return")
		if ret == null:
			out.append("no Accessory Return")
		elif not reachable(comp, origin, ret.grid_position):
			out.append("Accessory Return is not routable from the core")
	else:
		var intake = _tile_at_origin(comp)
		if intake == null or not (intake.tile_type in POWER_SOURCES):
			out.append("no power source (Energy Intake / Microcore) at the origin")
		else:
			var faces_ok = false
			for f in intake.active_faces:
				var n = origin.neighbor(int(f))
				if _in_shape(comp, n.q, n.r):
					faces_ok = true
			if not faces_ok:
				out.append("the power source at the origin points at empty space")
		var need = _payload_type(comp.slot_type)
		var sink = _first_of_type(comp, need) if need != "" else null
		if need != "" and sink == null:
			out.append("no %s sink" % need)
		for s in comp.fixed_sinks:
			if s.q == 0 and s.r == 0:
				continue
			if not reachable(comp, origin, s):
				out.append("sink at (%d,%d) is not routable from the intake" % [s.q, s.r])
	return out

static func _payload_type(slot: int) -> String:
	match slot:
		HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R:
			return "Weapon Mount"
		HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R:
			return "Actuator"
		HexTile.BodySlot.HEAD:
			return "Torso Return"
	return ""

# ---------------------------------------------------------------------------------------------
# Repair
# ---------------------------------------------------------------------------------------------

static func ensure(comp) -> Array:
	if comp == null or comp.hex_grid == null:
		return ["no grid"]
	for attempt in range(3):
		if problems(comp).is_empty():
			break
		if comp.slot_type == HexTile.BodySlot.TORSO:
			_ensure_torso(comp)
		else:
			_ensure_part(comp)
	return problems(comp)

static func _remove_sink_tile(comp, h: HexCoord) -> void:
	comp.hex_grid.remove_tile(h)
	for i in range(comp.fixed_sinks.size() - 1, -1, -1):
		if comp.fixed_sinks[i].q == h.q and comp.fixed_sinks[i].r == h.r:
			comp.fixed_sinks.remove_at(i)

static func _register_sink(comp, h: HexCoord) -> void:
	if not comp.is_fixed_sink(h):
		comp.fixed_sinks.append(HexCoord.new(h.q, h.r))

static func _on_own_ray(pos: HexCoord, dir: int) -> bool:
	var u = HexCoord.new(0, 0).neighbor(dir)
	for k in range(2, 12):
		if pos.q == u.q * k and pos.r == u.r * k:
			return true
	return false

static func _ensure_torso(comp) -> void:
	var origin = HexCoord.new(0, 0)
	if not comp.hex_grid.has_tile(origin):
		var core = load("res://scripts/tiles/CoreTile.gd").new()
		core.body_slot = HexTile.BodySlot.TORSO
		core.rarity = comp.rarity
		_force_add(comp, 0, 0)
		comp.hex_grid.add_tile(origin, core)
	_register_sink(comp, origin)
	for d in range(6):
		var n = origin.neighbor(d)
		_force_add(comp, n.q, n.r)

	# Pass 1: a link that is not on ITS OWN spoke (distance >= 2) can sit on another limb's
	# corridor and block it, so pull every such link off the board before placing any.
	for slot in SPOKES:
		var link0 = _link_for(comp, slot)
		if link0 != null and not (_on_own_ray(link0.grid_position, SPOKES[slot]) and comp.is_fixed_sink(link0.grid_position)):
			_remove_sink_tile(comp, link0.grid_position)

	for slot in SPOKES:
		var dir = SPOKES[slot]
		var link = _link_for(comp, slot)
		if link != null and reachable(comp, origin, link.grid_position):
			continue
		if link != null:
			_remove_sink_tile(comp, link.grid_position)
		# Each limb gets its own radial corridor: guarantee the ray reaches distance 2 (one open
		# hex between the hub and the link), then put the link on the farthest free hex of it.
		var curr = HexCoord.new(0, 0)
		var ray: Array = []
		for k in range(2):
			curr = curr.neighbor(dir)
			_force_add(comp, curr.q, curr.r)
		var probe = HexCoord.new(0, 0)
		while true:
			var n = probe.neighbor(dir)
			if not _in_shape(comp, n.q, n.r):
				break
			ray.append(n)
			probe = n
		var spot = null
		for i in range(ray.size() - 1, 0, -1): # distance >= 2 only
			if not comp.hex_grid.has_tile(ray[i]):
				spot = ray[i]
				break
		if spot == null: # corridor full of tiles: extend the ray one hex
			var beyond = ray[ray.size() - 1].neighbor(dir)
			_force_add(comp, beyond.q, beyond.r)
			spot = beyond
		var new_link = load("res://scripts/tiles/ComponentLinkTile.gd").new(slot, true)
		new_link.body_slot = HexTile.BodySlot.TORSO
		new_link.rarity = comp.rarity
		comp.hex_grid.add_tile(spot, new_link)
		_register_sink(comp, spot)

	var ret = _first_of_type(comp, "Accessory Return")
	if ret != null and reachable(comp, origin, ret.grid_position):
		return
	if ret != null:
		comp.hex_grid.remove_tile(ret.grid_position)
	var ret_spot = null
	for v in BETWEEN_SPOKES:
		if not comp.hex_grid.has_tile(HexCoord.new(v.x, v.y)):
			ret_spot = HexCoord.new(v.x, v.y)
			_force_add(comp, v.x, v.y)
			break
	if ret_spot == null:
		ret_spot = comp.get_script()._first_free_off_axis_hex(comp)
	if ret_spot != null:
		var new_ret = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
		new_ret.tile_type = "Accessory Return"
		new_ret.body_slot = HexTile.BodySlot.TORSO
		new_ret.rarity = comp.rarity
		comp.hex_grid.add_tile(ret_spot, new_ret)

# Straight hex line a -> b (cube-coordinate lerp), used to bridge a disconnected sink.
static func _hex_line(a: HexCoord, b: HexCoord) -> Array:
	var dist = max(abs(a.q - b.q), abs(a.r - b.r), abs((a.q + a.r) - (b.q + b.r)))
	var out: Array = []
	for i in range(dist + 1):
		var t = float(i) / float(max(dist, 1))
		var fq = lerp(float(a.q), float(b.q), t)
		var fr = lerp(float(a.r), float(b.r), t)
		var fs = lerp(float(-a.q - a.r), float(-b.q - b.r), t)
		var rq = round(fq)
		var rr = round(fr)
		var rs = round(fs)
		var dq = abs(rq - fq)
		var dr = abs(rr - fr)
		var ds = abs(rs - fs)
		if dq > dr and dq > ds:
			rq = -rr - rs
		elif dr > ds:
			rr = -rq - rs
		out.append(Vector2i(int(rq), int(rr)))
	return out

static func _ensure_part(comp) -> void:
	var origin = HexCoord.new(0, 0)
	var script = comp.get_script()
	var origin_tile = _tile_at_origin(comp)
	if origin_tile == null:
		var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
		intake.tile_type = "Energy Intake"
		intake.body_slot = comp.slot_type
		_force_add(comp, 0, 0)
		comp.hex_grid.add_tile(origin, intake)
		origin_tile = intake
	_register_sink(comp, origin)
	if origin_tile.tile_type == "Energy Intake":
		script._orient_intake_to_shape(comp, origin_tile)
	var need = _payload_type(comp.slot_type)
	if need != "" and _first_of_type(comp, need) == null:
		script._add_procedural_payload_sink(comp, comp.rarity)
	# Bridge any sink the footprint does not connect to the origin.
	for s in comp.fixed_sinks.duplicate():
		if s.q == 0 and s.r == 0:
			continue
		if reachable(comp, origin, s):
			continue
		for v in _hex_line(origin, s):
			_force_add(comp, v.x, v.y)
