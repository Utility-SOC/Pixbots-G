class_name GaragePacketInspector
extends RefCounted

# Packet Inspector (Status.md queue, paired with the Timeline Scrubber in
# GarageSimulationRunner.gd) - split out following the same composed-
# RefCounted-helper pattern as GarageTileConfigPopup.gd. Click a tile while
# the scrubber is visible (see GarageMenu._on_tile_clicked) to see exactly
# what has flowed through it up to whatever step the scrubber is parked on:
# current pending output (if it's an output-type tile) and, for each of the
# 6 hex directions, the last 5 packets that entered through that face -
# recorded live during simulation by HexTile.record_packet_history (called
# from GarageSimulationRunner._advance_step, the same engine both the live
# view and the scrubber's replay use).

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
	step_lbl.text = "As of step %d / %d" % [cur_step, total]
	step_lbl.modulate = Color(0.7, 0.85, 1.0)
	vbox.add_child(step_lbl)

	vbox.add_child(HSeparator.new())

	# Current composition: whatever this tile is holding right now, if it's
	# an output-type tile with pending_packets (Weapon Mount, Accessory/
	# Torso Return, Drone Bay, ...). Routing/processor tiles pass energy
	# straight through and never accumulate pending output, so they simply
	# don't show this section.
	if "pending_packets" in tile and not tile.pending_packets.is_empty():
		var cur_title = Label.new()
		cur_title.text = "Current pending output:"
		vbox.add_child(cur_title)
		var total_mag = 0.0
		var syn_totals: Dictionary = {}
		for item in tile.pending_packets:
			var p = item.packet
			total_mag += p.magnitude
			for k in p.synergies:
				syn_totals[k] = syn_totals.get(k, 0.0) + p.synergies[k]
		var cur_lbl = Label.new()
		cur_lbl.text = "  %s total  (%s)" % [GarageSimulationRunner._format_magnitude(total_mag), _format_synergy_breakdown(syn_totals)]
		cur_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(cur_lbl)
		vbox.add_child(HSeparator.new())

	var hist_title = Label.new()
	hist_title.text = "Entry history (last %d per direction):" % HexTile.PACKET_HISTORY_CAP
	vbox.add_child(hist_title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(scroll)
	var hist_vbox = VBoxContainer.new()
	hist_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hist_vbox)

	var any_history = false
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
		any_history = true
		# Newest first - what just happened is what you're most likely
		# scrubbing to look at.
		for i in range(entries.size() - 1, -1, -1):
			var snap = entries[i]
			var entry_lbl = Label.new()
			var dom_name = EnergyPacket.element_name(snap.dominant) if snap.dominant >= 0 else "?"
			entry_lbl.text = "  #%d: %s mag, dominant %s  (%s)" % [
				entries.size() - i,
				GarageSimulationRunner._format_magnitude(snap.magnitude),
				dom_name,
				_format_synergy_breakdown(snap.synergies),
			]
			entry_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			hist_vbox.add_child(entry_lbl)

	if not any_history:
		var hint = Label.new()
		hint.text = "Nothing has entered this tile yet at this step - drag the scrubber forward."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.modulate = Color(0.7, 0.7, 0.75)
		vbox.add_child(hint)

	garage.add_child(popup)
	popup.popup_centered(Vector2(420, 420))
	popup.popup_hide.connect(func(): popup.queue_free())

func _format_synergy_breakdown(synergies: Dictionary) -> String:
	if synergies.is_empty():
		return "no energy"
	var parts: Array = []
	for k in synergies:
		if synergies[k] > 0.01:
			parts.append("%s %s" % [EnergyPacket.element_name(k), GarageSimulationRunner._format_magnitude(synergies[k])])
	return ", ".join(parts) if not parts.is_empty() else "no energy"
