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
		[HexTile.BodySlot.LEG_R, HexTile.Rarity.LEGENDARY, "ambusher"]
	]

	print("Testing generate_shape()...")
	for config in test_configs:
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
