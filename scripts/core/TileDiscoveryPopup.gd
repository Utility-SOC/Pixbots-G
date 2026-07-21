extends CanvasLayer

# Autoload: "pop up any time someone got a new tile (or new tiles) - it
# should have explanation and maybe a graphic" (the user, describing what
# they wanted out of Test Range/Tutorial polish). Shown the FIRST time a
# given tile_type is ever added to the player's real inventory this save -
# SaveManager.note_tile_discovered() is the persistent "have I seen this
# before" gate, called from announce_if_new() below so every trigger site
# (loot pickup, Garage Market purchase, debug grants) shares one choke
# point instead of each re-deriving "is this actually new."
#
# The graphic reuses GarageGridRenderer wholesale (a tiny throwaway
# ComponentEquipment holding one clone of the tile at (0,0), rendered by a
# small GarageGridRenderer instance) rather than building a second icon
# system - there's no pre-rendered texture asset per tile type (icons are
# drawn live, see GarageGridRenderer._draw_descriptive_icon), and this way
# the popup automatically stays visually consistent with the Garage grid
# forever with zero duplicated drawing code. HexTile extends Resource (not
# Node - there's no scene-tree reparenting risk here), but
# HexGridComponent.add_tile() DOES stamp tile.grid_position onto whatever
# it's given - using a clone (not the real tile instance) for the preview
# keeps the real tile's own grid_position untouched, since it may already
# be equipped somewhere, or about to be, by the time this shows.
#
# Queued, not shown immediately per call: picking up several new tile types
# in the same instant (a big loot drop, or an old save's first session after
# this feature landed touching several types at once) shouldn't stack
# overlapping cards.
#
# Deliberately NON-blocking: this can trigger mid-combat (a loot pickup),
# and unlike a Black Market/dialogue prompt there's no natural pause to
# piggyback on - a full-screen modal would yank the player's attention (and
# mouse focus) away from a live fight. So this is a corner card, same
# always-visible-during-gameplay spirit as FpsCounter, not an interactive
# blocker: it never captures mouse input over the world, and auto-dismisses
# on a timer so it can never get "stuck" waiting for a click the player has
# no safe moment to make.

const GarageInventoryPanelScript = preload("res://scripts/ui/GarageInventoryPanel.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")

const DISPLAY_SECONDS = 7.0

var _queue: Array = [] # Array of HexTile (the real tiles, only read from - never mutated/reparented)
var _showing: bool = false
var _card: Control = null

func _ready():
	layer = 500 # above the HUD (5), below War Room (99)/Debug Menu (100)/FpsCounter (999)
	process_mode = Node.PROCESS_MODE_ALWAYS

# Call right after a tile genuinely enters the player's possession. No-ops
# silently (no card, no queue entry) if this tile_type has already been
# seen on this save - safe to call unconditionally at every acquisition site.
func announce_if_new(tile):
	if not tile or not SaveManager.note_tile_discovered(tile.tile_type):
		return
	_queue.append(tile)
	_try_show_next()

func _try_show_next():
	if _showing or _queue.is_empty():
		return
	_showing = true
	_build_card(_queue.pop_front())

func _build_card(tile):
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.position = Vector2(16, -190)
	_card.custom_minimum_size = Vector2(300, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE # never blocks clicks into the world behind it
	add_child(_card)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(vbox)

	var title = Label.new()
	title.text = "NEW TILE DISCOVERED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hbox)

	# Icon preview: a throwaway 1-hex component holding a disconnected clone
	# of the tile (same rarity), rendered by a real GarageGridRenderer -
	# see this file's header comment for why a clone, not the real instance.
	var preview_holder = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, tile.rarity)
	preview_holder.valid_hexes.append(HexCoord.new(0, 0)) # valid_hexes is Array[HexCoord] - can't assign a plain untyped literal
	var clone = tile.get_script().new()
	clone.rarity = tile.rarity
	preview_holder.hex_grid.add_tile(HexCoord.new(0, 0), clone)

	var icon_view = GarageGridRendererScript.new()
	icon_view.custom_minimum_size = Vector2(90, 90)
	icon_view.show_static_paths = false
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_view)
	icon_view.setup(preview_holder.hex_grid, null)
	icon_view.active_component = preview_holder
	icon_view.camera_offset = icon_view.custom_minimum_size / 2.0
	icon_view.zoom = 1.6 # a lone tile in an otherwise-empty 1-hex frame reads small at the default zoom

	var blurb = Label.new()
	blurb.text = GarageInventoryPanelScript.build_tile_tooltip_text(tile)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(blurb)

	var timer = Timer.new()
	timer.wait_time = DISPLAY_SECONDS
	timer.one_shot = true
	timer.timeout.connect(_dismiss)
	_card.add_child(timer)
	timer.start()

func _dismiss():
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_showing = false
	_try_show_next()
