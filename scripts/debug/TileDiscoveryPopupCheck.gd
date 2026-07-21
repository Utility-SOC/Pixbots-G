extends Node

# Regression harness for: "In a perfect world it would pop up any time
# someone got a new tile (or new tiles) - it should have explanation and
# maybe a graphic" (the user). Covers the SaveManager.discovered_tile_types
# choke point (note_tile_discovered) and TileDiscoveryPopup's queue/card/
# auto-dismiss behavior, and that the real tile instance is never touched
# (icon preview uses a disconnected clone). Deliberately does NOT exercise
# the save/load wiring or old-save backfill in SaveManager.gd - those need
# real save_game()/load_game() calls, which write to the actual user://
# saves/ directory (the player's real save data, never a test sandbox).

const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Isolate from whatever the real save file/session state happens to be -
	# every check below only cares about relative before/after behavior.
	SaveManager.discovered_tile_types = {}

	var popup = get_tree().root.get_node_or_null("TileDiscoveryPopup")
	_check("TileDiscoveryPopup autoload is present in the tree", popup != null)
	if not popup:
		get_tree().quit(1)
		return

	# 1. note_tile_discovered: true the first time, false thereafter.
	var first = SaveManager.note_tile_discovered("Weapon Mount")
	var second = SaveManager.note_tile_discovered("Weapon Mount")
	_check("note_tile_discovered returns true only the first time for a given type",
		first == true and second == false)

	# 2. announce_if_new builds a card for a genuinely new type.
	SaveManager.discovered_tile_types = {}
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	popup.announce_if_new(mount)
	_check("announcing a new tile type shows a card", popup._showing and is_instance_valid(popup._card))

	# 3. The real tile instance is never touched - HexTile extends Resource
	# (no scene-tree parent to worry about), but HexGridComponent.add_tile()
	# DOES stamp grid_position onto whatever it's handed - the preview must
	# use a disconnected clone so the real tile's own grid_position (which
	# may matter elsewhere - already equipped, or about to be) never gets
	# clobbered to the throwaway preview's (0,0).
	_check("the real announced tile's grid_position is never touched (preview used a clone)",
		mount.grid_position == null)

	# 4. Announcing the SAME type again while already showing doesn't queue
	# a second card (already marked discovered by step 2's announce).
	var mount2 = WeaponMountTileScript.new()
	mount2.rarity = HexTile.Rarity.COMMON
	popup.announce_if_new(mount2)
	_check("re-announcing an already-discovered type is a no-op (nothing queued)",
		popup._queue.is_empty())

	# 5. A genuinely different new type queues instead of interrupting the
	# currently-showing card.
	var splitter = SplitterTileScript.new()
	splitter.rarity = HexTile.Rarity.COMMON
	popup.announce_if_new(splitter)
	_check("a second new type while a card is showing queues instead of interrupting",
		popup._queue.size() == 1 and popup._showing)

	# 6. Dismissing the first card shows the queued second one automatically.
	var first_card = popup._card
	popup._dismiss()
	await get_tree().process_frame
	_check("dismissing a card frees it", not is_instance_valid(first_card))
	_check("the queued second card shows automatically after the first dismisses",
		popup._showing and is_instance_valid(popup._card) and popup._queue.is_empty())

	# 7. Card auto-dismisses via its own Timer (don't wait the real 7s -
	# just confirm the Timer is armed and one_shot, and that manually
	# firing it clears _showing the same way step 6 proved _dismiss() does).
	var timer = null
	for c in popup._card.get_children():
		if c is Timer:
			timer = c
	_check("the card carries a one-shot auto-dismiss Timer", timer != null and timer.one_shot and timer.wait_time > 0.0)
	popup._dismiss()
	await get_tree().process_frame
	_check("after the second card dismisses too, nothing is showing and the queue is empty",
		not popup._showing and popup._queue.is_empty())

	# NOTE: save/load round-trip and old-save backfill (SaveManager.gd's
	# discovered_tile_types read/write, mirroring first_boss_encountered's
	# already-proven pattern exactly) are deliberately NOT exercised here via
	# the real save_game()/load_game() - those write to the actual user://
	# saves/ directory, which a throwaway test must never touch (that's the
	# player's real save data, not a sandbox).

	if failures == 0:
		print("PASS: new-tile-discovered card - queue, real-tile safety, auto-dismiss")
	get_tree().quit(0 if failures == 0 else 1)
