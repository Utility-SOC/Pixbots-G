extends Node

# Manual visual tool (not a regression check): renders the Garage grid with the conduit animation at two moments and
# saves PNGs. Run windowed: godot --path . res://scripts/debug/ConduitFlowShot.tscn -- --out=/tmp/conduit

const ParityScript = preload("res://scripts/debug/RustGridSimParityCheck.gd")
const RustGridSimScript = preload("res://scripts/core/RustGridSim.gd")
const RendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")

func _ready():
	var out := "/tmp/conduit"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var par = ParityScript.new()
	var comp = par._build_component_a()
	RustGridSimScript.try_simulate(comp.hex_grid, par._gen_packets(comp), true)
	comp.hex_grid.flow_ready = true
	var holder := Control.new()
	holder.size = Vector2(900, 600)
	add_child(holder)
	var r = RendererScript.new()
	r.size = holder.size
	r.active_component = comp
	holder.add_child(r)
	# The power overlay only shows for a live, clean player grid: stand in for Main (.player) and the garage menu.
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar player\nvar is_grid_dirty := false\n"
	gs.reload()
	var fake_main := Node.new()
	fake_main.set_script(gs)
	var fake_player := Node.new()
	fake_player.set_script(gs)
	fake_main.player = fake_player
	var fake_menu := Node.new()
	fake_main.add_child(fake_menu)
	add_child(fake_main)
	r.setup(comp.hex_grid, fake_menu, comp.valid_hexes)
	for i in range(3):
		await get_tree().process_frame
	for t in [0.0, 0.18]:
		r.time_elapsed = 1.0 + t
		r.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		var img = get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [out, int(t * 100)])
		print("saved ", out, "_", int(t * 100), ".png entries=", comp.hex_grid.flow_entries.size())
	get_tree().quit()
