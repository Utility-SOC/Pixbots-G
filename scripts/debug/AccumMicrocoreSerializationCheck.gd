extends Node

# Investigation harness for: "Accumulator settings don't seem to be getting
# saved/serialized. still same deal for microcore settings and outputs."
# Round-trips both tile types through the EXACT path a named build slot
# uses: _serialize_component -> JSON.stringify -> JSON.parse_string ->
# _deserialize_component (see SaveManager.save_named_loadout/
# load_loadout_file).

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const MicrocoreTileScript = preload("res://scripts/tiles/MicrocoreTile.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0)]
	torso.valid_hexes = hexes
	torso._rebuild_valid_hex_set()

	var acc = AccumulatorTileScript.new()
	acc.rarity = HexTile.Rarity.MYTHIC
	acc.trigger_key = "2"
	acc.auto_dump_threshold = 0.5
	torso.hex_grid.add_tile(HexCoord.new(0, 0), acc)

	var micro = MicrocoreTileScript.new()
	micro.rarity = HexTile.Rarity.MYTHIC
	micro.active_faces.clear()
	micro.active_faces.append(2)
	micro.active_faces.append(4)
	micro.face_outputs[2] = EnergyPacket.SynergyType.FIRE
	micro.face_outputs[4] = EnergyPacket.SynergyType.ICE
	torso.hex_grid.add_tile(HexCoord.new(1, 0), micro)

	var sm = SaveManagerScript.new()
	var json_text = JSON.stringify({"components": {"1": sm._serialize_component(torso)}}, "\t")
	var parsed = JSON.parse_string(json_text)
	var torso2 = sm._deserialize_component(parsed["components"]["1"])

	var acc2 = torso2.hex_grid.get_tile(HexCoord.new(0, 0))
	_check("Accumulator survived the round trip as an Accumulator", acc2 != null and acc2.tile_type == "Accumulator")
	if acc2:
		_check("Accumulator trigger_key '2' survived (got '%s')" % acc2.trigger_key, acc2.trigger_key == "2")
		_check("Accumulator auto_dump_threshold 0.5 survived (got %s)" % acc2.auto_dump_threshold, abs(acc2.auto_dump_threshold - 0.5) < 0.001)

	var micro2 = torso2.hex_grid.get_tile(HexCoord.new(1, 0))
	_check("Microcore survived the round trip as a Microcore", micro2 != null and micro2.tile_type == "Microcore")
	if micro2:
		var faces = micro2.active_faces.duplicate()
		faces.sort()
		_check("Microcore active_faces [2,4] survived (got %s)" % [faces], faces == [2, 4])
		_check("Microcore face 2 output FIRE survived (got %s)" % micro2.get_face_output(2), micro2.get_face_output(2) == EnergyPacket.SynergyType.FIRE)
		_check("Microcore face 4 output ICE survived (got %s)" % micro2.get_face_output(4), micro2.get_face_output(4) == EnergyPacket.SynergyType.ICE)

	if failures == 0:
		print("PASS: Accumulator and Microcore settings survive the named-build-slot JSON round trip")
	get_tree().quit(0 if failures == 0 else 1)
