extends SceneTree

func _init():
	print("--- ProceduralShapeParityCheck ---")
	if not ClassDB.class_exists("ProceduralShapeGen"):
		print("ERROR: ProceduralShapeGen not loaded in ClassDB.")
		quit(1)
		return

	var gen = ClassDB.instantiate("ProceduralShapeGen")
	var comp = ComponentEquipment.new()
	var test_configs = [
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "brawler"],
		[HexTile.BodySlot.HEAD, HexTile.Rarity.COMMON, "sniper"],
		[HexTile.BodySlot.ARM_L, HexTile.Rarity.RARE, "scout"],
		[HexTile.BodySlot.LEG_R, HexTile.Rarity.LEGENDARY, "ambusher"],
		# Class-constrained torso shapes (2026-08-10) - exercise all four
		# new role-specific torso branches, plus a couple of rarities each
		# so the budget-driven while-loop termination stays in parity too.
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "scout"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.RARE, "scout"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "scout"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "sniper"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.LEGENDARY, "sniper"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "brawler"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.RARE, "brawler"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "ambusher"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "ambusher"],
		# Jammer/anti_missile/diver/remediation (2026-08-11) - exercise the
		# jammer-family alias onto Scout's shape, the diver diagonal-band
		# variant, and remediation's new boxy-fill rectangle.
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "jammer"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "jammer"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.RARE, "anti_missile"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "diver"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "diver"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "remediation"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "remediation"],
		# Support/commander/flamethrower (2026-08-11) - exercise the rounded
		# non-boxy shield, the tall boxy monument, and the first genuinely
		# horizontally-asymmetric shape (flamethrower's forward wedge).
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "support"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "support"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "commander"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "commander"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, "flamethrower"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC, "flamethrower"],
		# Torso for a role with no special-cased shape - must still hit the
		# unchanged default disc-growth branch identically.
		[HexTile.BodySlot.TORSO, HexTile.Rarity.RARE, "melee"],
		[HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON, ""]
	]

	print("Testing generate_shape()...")
	for config in test_configs:
		# comp is reused across every config in this loop - without clearing
		# here, an earlier config's hexes silently accumulate into the
		# next one's result (found 2026-08-10: masked until now because
		# the very first config used to mismatch under the OLD torso
		# algorithm and the loop exited before ever reaching config 2+).
		# Mirrors what the real generate_shape() wrapper does before
		# delegating to Rust.
		comp.valid_hexes.clear()
		comp._valid_hex_set.clear()
		comp.slot_type = config[0]
		comp.rarity = config[1]
		comp.role_variant = config[2]

		var result = gen.generate_shape(comp.slot_type, comp.rarity, comp.role_variant, comp.grid_width, comp.grid_height)
		
		comp._generate_shape_fallback()
		var fallback_hexes = comp.valid_hexes
		
		if not _compare(result, fallback_hexes):
			print("MISMATCH in generate_shape() for config: ", config)
			print("Rust: ", _arr_to_str(result))
			print("GDScript: ", _hexes_to_str(fallback_hexes))
			quit(1)
			return

	print("Testing generate_procedural_shape()...")
	var seeds = [42, 1337, 9999, 12345, 888]
	for s in seeds:
		for config in test_configs:
			comp.slot_type = config[0]
			comp.rarity = config[1]
			comp.role_variant = config[2]

			var result = gen.generate_procedural_shape(comp.slot_type, comp.rarity, comp.role_variant, s)

			# Same "clear before calling the low-level fallback directly"
			# fix the generate_shape() loop above already applies (see its
			# own comment) - _generate_procedural_shape_fallback appends to
			# valid_hexes/_valid_hex_set without clearing them itself (its
			# real caller, _generate_procedural_shape_with_seed, does that).
			# Without this, the very first iteration here silently inherited
			# leftover hexes from the LAST generate_shape() config above,
			# corrupting valid_hexes.size() (used by the RNG attach-point
			# pick) and every result from the first RNG call onward - a
			# test-harness bug, not a real Rust/GDScript RNG divergence
			# (confirmed 2026-08-11: both sides use the same engine
			# RandomNumberGenerator, no cross-language algorithm mismatch).
			comp.valid_hexes.clear()
			comp._valid_hex_set.clear()
			comp._generate_procedural_shape_fallback(s)
			var fallback_hexes = comp.valid_hexes
			
			if not _compare(result, fallback_hexes):
				print("MISMATCH in generate_procedural_shape() for config: ", config, " seed: ", s)
				print("Rust: ", _arr_to_str(result))
				print("GDScript: ", _hexes_to_str(fallback_hexes))
				quit(1)
				return

	print("All shapes perfectly match (100% parity).")
	quit(0)

func _compare(rust_result: Array, gd_hexes: Array) -> bool:
	if rust_result.size() != gd_hexes.size():
		return false
	
	# Order doesn't strictly matter for the final set, but we can verify set equality.
	for d in rust_result:
		var found = false
		for h in gd_hexes:
			if h.q == d.get("q") and h.r == d.get("r"):
				found = true
				break
		if not found:
			return false
	return true

func _arr_to_str(arr: Array) -> String:
	var s = "["
	for d in arr:
		s += "(%s,%s) " % [d.get("q"), d.get("r")]
	return s + "]"

func _hexes_to_str(arr: Array) -> String:
	var s = "["
	for h in arr:
		s += "(%s,%s) " % [h.q, h.r]
	return s + "]"
