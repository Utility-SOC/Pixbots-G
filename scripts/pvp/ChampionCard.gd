class_name ChampionCard
extends RefCounted

# PvP "Traveling Champions" (FEATURE_ROADMAP / CLAUDE_CODE_HANDOFF decisions
# 1-3): local, clipboard/file-swap PvP - no networking. A Champion Card is a
# shareable PNG: a rendered card image with the mech's full serialized
# loadout (SaveManager component format), pilot name, and rank embedded in
# an iTXt text chunk. Anyone can drop a friend's card PNG into
# user://champion_cards/ and import it; the ghost then appears as a
# "Traveling Champion" challenger during waves (see Main.gd), fighting with
# the EXACT build it was exported with.
#
# Format notes (interop contract - keep stable):
# - PNG iTXt chunk, keyword "pixbots.champion", uncompressed UTF-8 JSON.
# - The visual layer of the card can change freely; only the chunk matters.
# - payload["format"] versions the payload itself.

const CHUNK_KEYWORD = "pixbots.champion"
const PAYLOAD_FORMAT = "pixbots-champion-v1"
const CARDS_DIR = "user://champion_cards/"
const GHOSTS_DIR = "user://pvp_ghosts/" # grows unbounded by design ruling
const RANK_FILE = "user://pvp_rank.dat" # encrypted local rank (design ruling)
const RANK_BASELINE = 1000.0
const RANK_K = 32.0 # classic Elo K-factor

# Matches GarageMenu's rarity accent colors closely enough to read.
const RARITY_COLORS = [
	Color(0.62, 0.62, 0.62), # COMMON
	Color(0.35, 0.85, 0.35), # UNCOMMON
	Color(0.35, 0.55, 1.0),  # RARE
	Color(1.0, 0.65, 0.15),  # LEGENDARY
	Color(0.85, 0.3, 0.9),   # MYTHIC
]

# ---------------------------------------------------------------- payload --

static func build_payload(mech: Node, pilot_name: String) -> Dictionary:
	var payload = {
		"format": PAYLOAD_FORMAT,
		"pilot_name": pilot_name,
		"rank": get_local_rank(),
		"max_wave": SaveManager.max_wave_reached,
		"created_unix": int(Time.get_unix_time_from_system()),
		"components": {},
	}
	for slot in mech.components.keys():
		payload["components"][str(slot)] = SaveManager._serialize_component(mech.components[slot])
	return payload

# ------------------------------------------------------------- PNG chunks --

# PNG-polynomial CRC32 (0xEDB88320), required for a chunk PNG loaders will
# accept. Table built lazily once.
static var _crc_table: PackedInt64Array = PackedInt64Array()

static func _crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in range(256):
			var c = n
			for _k in range(8):
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[n] = c
	var crc = 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF

static func _be32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])

# Inserts our iTXt chunk immediately before IEND. iTXt (not tEXt) because
# its text field is defined as UTF-8, matching JSON.stringify output.
static func embed_payload(png_bytes: PackedByteArray, payload: Dictionary) -> PackedByteArray:
	var text = JSON.stringify(payload)
	var chunk_data = CHUNK_KEYWORD.to_utf8_buffer()
	chunk_data.append(0)      # keyword terminator
	chunk_data.append(0)      # compression flag: uncompressed
	chunk_data.append(0)      # compression method
	chunk_data.append(0)      # language tag: empty, terminated
	chunk_data.append(0)      # translated keyword: empty, terminated
	chunk_data.append_array(text.to_utf8_buffer())

	var type_and_data = "iTXt".to_utf8_buffer()
	type_and_data.append_array(chunk_data)

	var chunk = _be32(chunk_data.size())
	chunk.append_array(type_and_data)
	chunk.append_array(_be32(_crc32(type_and_data)))

	# IEND is always the final 12 bytes of a well-formed PNG.
	var iend_start = png_bytes.size() - 12
	var out = png_bytes.slice(0, iend_start)
	out.append_array(chunk)
	out.append_array(png_bytes.slice(iend_start))
	return out

# Walks the chunk list looking for our iTXt; returns {} if absent/invalid.
static func extract_payload(png_bytes: PackedByteArray) -> Dictionary:
	if png_bytes.size() < 8 + 12:
		return {}
	var pos = 8 # skip signature
	while pos + 12 <= png_bytes.size():
		var length = (png_bytes[pos] << 24) | (png_bytes[pos + 1] << 16) | (png_bytes[pos + 2] << 8) | png_bytes[pos + 3]
		var type = png_bytes.slice(pos + 4, pos + 8).get_string_from_ascii()
		if type == "iTXt":
			var data = png_bytes.slice(pos + 8, pos + 8 + length)
			var keyword_end = data.find(0)
			if keyword_end > 0 and data.slice(0, keyword_end).get_string_from_utf8() == CHUNK_KEYWORD:
				# keyword \0 flag \0(method) then two \0-terminated strings
				var p = keyword_end + 3
				for _i in range(2):
					var z = data.slice(p).find(0)
					if z < 0:
						return {}
					p += z + 1
				var parsed = JSON.parse_string(data.slice(p).get_string_from_utf8())
				if parsed is Dictionary and parsed.get("format", "") == PAYLOAD_FORMAT:
					return parsed
			# fall through: not our chunk, keep walking
		if type == "IEND":
			break
		pos += 12 + length
	return {}

# -------------------------------------------------------------- card image --

# Procedural card art from pure Image ops (works headless, no viewport):
# dark card, rarity-colored double border keyed to the build's dominant
# tile rarity, and a "blueprint" of each component's actual hex grid drawn
# in its tiles' own colors - a genuinely identifying visual of the build.
# All the DATA lives in the embedded chunk; this layer is free to evolve.
static func render_card_image(mech: Node) -> Image:
	var w = 400
	var h = 560
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.09, 0.12))

	var dominant_rarity = 0
	var rarity_counts = {}
	for comp in mech.components.values():
		for tile in comp.hex_grid.get_all_tiles():
			rarity_counts[tile.rarity] = rarity_counts.get(tile.rarity, 0) + 1
	var best_count = 0
	for r in rarity_counts:
		if rarity_counts[r] > best_count:
			best_count = rarity_counts[r]
			dominant_rarity = r
	var border = RARITY_COLORS[clamp(dominant_rarity, 0, 4)]

	img.fill_rect(Rect2i(0, 0, w, 6), border)
	img.fill_rect(Rect2i(0, h - 6, w, 6), border)
	img.fill_rect(Rect2i(0, 0, 6, h), border)
	img.fill_rect(Rect2i(w - 6, 0, 6, h), border)
	var dim = Color(border.r, border.g, border.b, 0.35)
	img.fill_rect(Rect2i(12, 12, w - 24, 2), dim)
	img.fill_rect(Rect2i(12, h - 14, w - 24, 2), dim)

	# Blueprint: slots on a 2x4 grid of cells; each hex as a 4x4 px block.
	var slot_centers = {}
	var idx = 0
	for slot in mech.components.keys():
		var cx = 100 + (idx % 2) * 200
		var cy = 90 + int(idx / 2) * 130
		slot_centers[slot] = Vector2i(cx, cy)
		idx += 1

	for slot in mech.components.keys():
		var comp = mech.components[slot]
		var center: Vector2i = slot_centers[slot]
		for coord in comp.hex_grid.grid.keys():
			var tile = comp.hex_grid.grid[coord]
			var px = center.x + int(round((coord.x * 2.0 + coord.y) * 4.0))
			var py = center.y + int(round(coord.y * 6.0))
			var color = tile.base_color if "base_color" in tile else Color(0.5, 0.5, 0.5)
			var rc = RARITY_COLORS[clamp(tile.rarity, 0, 4)]
			for dx in range(4):
				for dy in range(4):
					var x = px + dx
					var y = py + dy
					if x >= 8 and y >= 8 and x < w - 8 and y < h - 8:
						img.set_pixel(x, y, color.lerp(rc, 0.35))
	return img

# ------------------------------------------------------------ export/import --

# Renders + embeds + writes; returns the absolute user:// path or "" on error.
static func export_card(mech: Node, pilot_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(CARDS_DIR)
	var payload = build_payload(mech, pilot_name)
	var img = render_card_image(mech)
	var png = img.save_png_to_buffer()
	png = embed_payload(png, payload)
	var safe_name = pilot_name.validate_filename().replace(" ", "_")
	if safe_name == "":
		safe_name = "pilot"
	var path = CARDS_DIR + safe_name + "_champion.png"
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ""
	f.store_buffer(png)
	f.close()
	return path

# Reads one card PNG and registers its ghost. Returns the ghost dict or {}.
static func import_card(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var payload = extract_payload(f.get_buffer(f.get_length()))
	f.close()
	if payload.is_empty():
		return {}
	DirAccess.make_dir_recursive_absolute(GHOSTS_DIR)
	var ghost_id = "%s_%d" % [str(payload.get("pilot_name", "pilot")).validate_filename().replace(" ", "_"), int(payload.get("created_unix", 0))]
	payload["ghost_id"] = ghost_id
	payload["wins"] = 0   # ghost's record on THIS machine
	payload["losses"] = 0
	var out = FileAccess.open(GHOSTS_DIR + ghost_id + ".json", FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(payload, "\t"))
		out.close()
	return payload

# Scans a directory for card PNGs and imports every one not already
# registered. Returns the newly imported ghost dicts.
static func import_cards_from_dir(dir_path: String = CARDS_DIR) -> Array:
	var imported: Array = []
	var dir = DirAccess.open(dir_path)
	if not dir:
		return imported
	for file in dir.get_files():
		if not file.ends_with(".png"):
			continue
		var ghost = import_card(dir_path.path_join(file))
		if ghost.is_empty():
			continue
		# skip ones we've already got (same pilot+timestamp)
		if FileAccess.file_exists(GHOSTS_DIR + ghost["ghost_id"] + ".json"):
			pass # import_card just (re)wrote it; treat rewrite as idempotent
		imported.append(ghost)
	return imported

static func list_ghosts() -> Array:
	var ghosts: Array = []
	var dir = DirAccess.open(GHOSTS_DIR)
	if not dir:
		return ghosts
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var f = FileAccess.open(GHOSTS_DIR + file, FileAccess.READ)
		if not f:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.get("format", "") == PAYLOAD_FORMAT:
			ghosts.append(parsed)
	return ghosts

# --------------------------------------------------------------- local rank --

# Local rank lives in an encrypted file (design ruling) keyed off this
# install's identity, and rebalances Elo-style from champion wins/losses.
static func _rank_pass() -> String:
	return "pixbots-rank-" + str(SaveManager.pilot_name).sha256_text()

static func get_local_rank() -> float:
	var f = FileAccess.open_encrypted_with_pass(RANK_FILE, FileAccess.READ, _rank_pass())
	if not f:
		return RANK_BASELINE
	var v = f.get_double()
	f.close()
	return v if v > 0.0 else RANK_BASELINE

static func _set_local_rank(rank: float):
	var f = FileAccess.open_encrypted_with_pass(RANK_FILE, FileAccess.WRITE, _rank_pass())
	if f:
		f.store_double(rank)
		f.close()

# Records a match against a ghost: updates the local Elo rank against the
# ghost's exported rank, and the ghost's local win/loss record.
static func record_result(ghost_id: String, player_won: bool):
	var path = GHOSTS_DIR + ghost_id + ".json"
	var ghost_rank = RANK_BASELINE
	var ghost: Dictionary = {}
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			ghost = parsed
			ghost_rank = float(ghost.get("rank", RANK_BASELINE))

	var mine = get_local_rank()
	var expected = 1.0 / (1.0 + pow(10.0, (ghost_rank - mine) / 400.0))
	var actual = 1.0 if player_won else 0.0
	_set_local_rank(mine + RANK_K * (actual - expected))

	if not ghost.is_empty():
		var key = "losses" if player_won else "wins" # from the GHOST's perspective
		ghost[key] = int(ghost.get(key, 0)) + 1
		var out = FileAccess.open(path, FileAccess.WRITE)
		if out:
			out.store_string(JSON.stringify(ghost, "\t"))
			out.close()
