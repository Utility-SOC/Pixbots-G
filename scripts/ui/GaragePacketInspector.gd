class_name GaragePacketInspector
extends RefCounted

# Packet Inspector (Status.md queue, paired with the Timeline Scrubber in
# GarageSimulationRunner.gd) - split out following the same composed-
# RefCounted-helper pattern as GarageTileConfigPopup.gd. Click a tile while
# Inspect mode is on (see GarageMenu.sim_inspect_toggle/_on_tile_clicked) to
# get a zoomed-in, animated closeup of that ONE hex: packets visibly
# flowing in along each of the 6 faces, and - for a Mythic Resonator
# specifically - what synergy residue each of its 3 sync paths is currently
# leaving behind for the other paths to pick up (playtest: "I'd click the
# thing, it would zoom in to the hex, it would show the packets moving
# around inside... what they were leaving behind, what they were picking
# up"). The canvas reads live off the tile's own state (packet_history,
# _path_residue for a Resonator) each frame, so if the main Timeline
# Scrubber gets dragged while this popup is still open, the view updates
# with it - no separate refresh needed.

var garage: GarageMenu

const DIRECTION_NAMES = ["East", "South-East", "South-West", "West", "North-West", "North-East"]

func _init(p_garage: GarageMenu):
	garage = p_garage

func on_tile_clicked(tile: HexTile):
	var popup = PopupPanel.new()
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	var title = Label.new()
	var pos_str = "(%d, %d)" % [tile.grid_position.q, tile.grid_position.r] if tile.grid_position else "?"
	title.text = "Packet Inspector: %s @ %s" % [tile.tile_type, pos_str]
	vbox.add_child(title)

	var step_lbl = Label.new()
	var runner = garage.simulation_runner
	var cur_step = garage.grid_renderer.simulation_step if garage.grid_renderer else 0
	var total = runner.total_steps if runner else 0
	step_lbl.text = "As of step %d / %d  (live - drag the main Timeline to update this view)" % [cur_step, total]
	step_lbl.modulate = Color(0.7, 0.85, 1.0)
	step_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(step_lbl)

	# The zoomed-in animated closeup - see PacketFlowCanvas below.
	var canvas = PacketFlowCanvas.new()
	canvas.tile = tile
	canvas.custom_minimum_size = Vector2(340, 340)
	vbox.add_child(canvas)

	# Current composition: whatever this tile is holding right now, if it's
	# an output-type tile with pending_packets (Weapon Mount, Accessory/
	# Torso Return, Drone Bay, ...). Routing/processor tiles pass energy
	# straight through and never accumulate pending output, so they simply
	# don't show this section.
	if "pending_packets" in tile and not tile.pending_packets.is_empty():
		var cur_lbl = Label.new()
		var total_mag = 0.0
		var syn_totals: Dictionary = {}
		for item in tile.pending_packets:
			var p = item.packet
			total_mag += p.magnitude
			for k in p.synergies:
				syn_totals[k] = syn_totals.get(k, 0.0) + p.synergies[k]
		cur_lbl.text = "Current pending output: %s total (%s)" % [GarageSimulationRunner._format_magnitude(total_mag), _format_synergy_breakdown(syn_totals)]
		cur_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(cur_lbl)

	var hist_toggle = CheckButton.new()
	hist_toggle.text = "Show numeric history (last %d per direction)" % HexTile.PACKET_HISTORY_CAP
	vbox.add_child(hist_toggle)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.visible = false
	vbox.add_child(scroll)
	var hist_vbox = VBoxContainer.new()
	hist_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hist_vbox)
	hist_toggle.toggled.connect(func(on): scroll.visible = on)

	for dir in range(6):
		var entries: Array = tile.packet_history.get(dir, [])
		var dir_lbl = Label.new()
		dir_lbl.text = "%s:" % DIRECTION_NAMES[dir]
		dir_lbl.modulate = Color(0.8, 0.8, 0.85) if entries.is_empty() else Color.WHITE
		hist_vbox.add_child(dir_lbl)
		if entries.is_empty():
			var none_lbl = Label.new()
			none_lbl.text = "  (no packets recorded)"
			none_lbl.modulate = Color(0.55, 0.55, 0.6)
			hist_vbox.add_child(none_lbl)
			continue
		# Newest first - what just happened is what you're most likely
		# scrubbing to look at.
		for i in range(entries.size() - 1, -1, -1):
			var snap = entries[i]
			var entry_lbl = Label.new()
			var dom_name = EnergyPacket.element_name(snap.dominant) if snap.dominant >= 0 else "?"
			entry_lbl.text = "  #%d: %s mag, dominant %s%s  (%s)" % [
				entries.size() - i,
				GarageSimulationRunner._format_magnitude(snap.magnitude),
				dom_name,
				"  [carrying a picked-up proc]" if snap.get("picked_up", false) else "",
				_format_synergy_breakdown(snap.synergies),
			]
			entry_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			hist_vbox.add_child(entry_lbl)

	garage.add_child(popup)
	popup.popup_centered(Vector2(400, 560))
	popup.popup_hide.connect(func(): popup.queue_free())

func _format_synergy_breakdown(synergies: Dictionary) -> String:
	if synergies.is_empty():
		return "no energy"
	var parts: Array = []
	for k in synergies:
		if synergies[k] > 0.01:
			parts.append("%s %s" % [EnergyPacket.element_name(k), GarageSimulationRunner._format_magnitude(synergies[k])])
	return ", ".join(parts) if not parts.is_empty() else "no energy"

# --- Zoomed-in animated hex closeup -----------------------------------
# A standalone Control (inner class, same convention as MinimapOverlay.gd's
# MinimapView) drawing ONE hex big, with the 6 faces as flow "stubs":
# colored by the most recent packet's dominant synergy, with small dots
# continuously animating inward along each stub for every recorded history
# entry (staggered so a face with several recent packets reads as a little
# stream, not one pulsing dot). Direction angles use the SAME convention as
# HexCoord.get_directions()/GarageGridRenderer's pointy-top layout (dir 0 =
# East = 0 degrees, +60 degrees per direction index) so "East" here always
# points the same way it does on the main grid.
class PacketFlowCanvas:
	extends Control

	var tile: HexTile = null

	const HEX_R = 60.0
	const STUB_LEN = 60.0
	const DOT_SPEED = 0.5 # full edge-to-center traversals per second
	const DOT_STAGGER = 0.22

	func _ready():
		set_process(true)

	func _process(_delta):
		queue_redraw() # continuous animation - see the dot phase math in _draw()

	func _draw():
		var center = size / 2.0

		var hex_pts = PackedVector2Array()
		for i in range(6):
			var a = deg_to_rad(60 * i - 30) # flat-edge vertex offset, matches the pointy-top hex outline drawn elsewhere in the Garage
			hex_pts.append(center + Vector2(cos(a), sin(a)) * HEX_R)
		draw_polyline(hex_pts + PackedVector2Array([hex_pts[0]]), Color(0.6, 0.65, 0.72), 2.0, true)

		if not tile:
			return

		# Resonator Sync (Mythic only): the 3 diameters + what each path is
		# currently leaving behind as residue - see ResonatorTile._path_residue.
		# get() (dynamic Object property access) rather than a bare
		# tile._path_residue - `tile` is statically typed HexTile, which
		# doesn't declare that field (only ResonatorTile does), so a bare
		# reference fails to compile the exact way a bare pending_packets
		# reference did in HexTile.reset_simulation_state().
		if "_path_residue" in tile:
			var residue_map = tile.get("_path_residue")
			var path_names = ["E-W", "SE-NW", "SW-NE"]
			for path_id in range(3):
				var pa = center + Vector2.RIGHT.rotated(deg_to_rad(60 * path_id)) * HEX_R
				var pb = center + Vector2.RIGHT.rotated(deg_to_rad(60 * (path_id + 3))) * HEX_R
				draw_line(pa, pb, Color(0.5, 0.5, 0.58, 0.5), 1.5)
				var residue = residue_map.get(path_id, null) if residue_map is Dictionary else null
				var mid = (pa + pb) / 2.0
				if residue:
					var col = EnergyPacket.get_color_for_synergy(residue.synergy)
					var pulse = 1.0 + sin(Time.get_ticks_msec() / 200.0) * 0.15
					draw_circle(mid, 10.0 * pulse, col)
					draw_string(ThemeDB.fallback_font, mid + Vector2(-14, 22), "%s (%d)" % [EnergyPacket.element_name(residue.synergy), residue.steps_left], HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)
				else:
					draw_string(ThemeDB.fallback_font, mid + Vector2(-16, 4), path_names[path_id], HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(0.5, 0.5, 0.55))

		# Per-direction stubs + animated inbound dots.
		for dir in range(6):
			var dir_vec = Vector2.RIGHT.rotated(deg_to_rad(60 * dir))
			var outer_pt = center + dir_vec * (HEX_R + STUB_LEN)
			var edge_pt = center + dir_vec * HEX_R
			var entries: Array = tile.packet_history.get(dir, [])

			var stub_col = Color(0.4, 0.4, 0.46)
			if not entries.is_empty():
				var latest = entries[entries.size() - 1]
				stub_col = EnergyPacket.get_color_for_synergy(latest.dominant) if latest.dominant >= 0 else Color(0.85, 0.85, 0.9)
			draw_line(outer_pt, edge_pt, stub_col, 2.5)

			var label_pt = outer_pt + dir_vec * 14.0
			draw_string(ThemeDB.fallback_font, label_pt - Vector2(24, -4), DIRECTION_NAMES[dir], HORIZONTAL_ALIGNMENT_CENTER, 48, 10, Color(0.6, 0.6, 0.65))

			for i in range(entries.size()):
				var snap = entries[i]
				var phase = fmod(Time.get_ticks_msec() / 1000.0 * DOT_SPEED + i * DOT_STAGGER, 1.0)
				var pos = outer_pt.lerp(edge_pt, phase)
				var col = EnergyPacket.get_color_for_synergy(snap.dominant) if snap.dominant >= 0 else Color.WHITE
				var r = clamp(2.5 + sqrt(max(0.0, snap.magnitude)) * 0.05, 2.5, 9.0)
				draw_circle(pos, r, col)
				# "Picked up" indicator - a bright ring around any dot whose
				# packet is carrying a status-effect proc (see
				# HexTile.record_packet_history's picked_up field).
				if snap.get("picked_up", false):
					draw_arc(pos, r + 3.0, 0, TAU, 14, Color(1.0, 1.0, 1.0, 0.85), 1.5)
