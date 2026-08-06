extends Node

# Regression harness for the paperdoll paint-color fix (playtest report:
# "the paperdoll does not change color to match the paint rack selection").
# Root cause: MechRenderer only applies a paint override when `"paint_color"
# in mech` passes (duck-typed check) - PreviewMechContext (the paperdoll's
# stand-in mech) never declared that field at all, so it silently always
# fell through to the default hero color.
#
# `player` below mimics Main.gd's own `player` field BY NAME - ComponentDiagramView.
# refresh() looks up the real player via get_tree().current_scene.get("player"),
# and in this headless run current_scene IS this check's own root node, so
# declaring the same field name here exercises the REAL lookup path instead
# of a synthetic substitute for it.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentDiagramViewScript = preload("res://scripts/ui/ComponentDiagramView.gd")

var player: Node = null
var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	player = MechScript.new()
	player.is_player = true
	player.paint_color = Color(0.9, 0.1, 0.1, 1.0) # a distinctive red, unlikely to collide with any default profile color
	add_child(player)

	var diagram = ComponentDiagramViewScript.new()
	diagram.size = Vector2(900, 500)
	add_child(diagram)
	await get_tree().process_frame

	diagram.refresh({})
	await get_tree().process_frame

	_check("refresh() syncs the real player's Paint Rack color onto the preview's stand-in mech",
		diagram._preview_context.paint_color.is_equal_approx(player.paint_color))

	var sig_after_first_refresh = diagram._last_preview_signature
	_check("the preview signature reflects the synced paint color", sig_after_first_refresh.contains(player.paint_color.to_html(true)))

	# Repaint (same loadout, no component change at all) - the signature
	# must still pick this up, or a same-build repaint would silently never
	# refresh the preview until some UNRELATED equip change happened to
	# also trigger a rebuild.
	player.paint_color = Color(0.1, 0.2, 0.9, 1.0) # a distinctive blue
	diagram.refresh({})
	await get_tree().process_frame

	_check("a repaint with an unchanged loadout still updates the preview's color",
		diagram._preview_context.paint_color.is_equal_approx(player.paint_color))
	_check("the signature changed on repaint alone (same components, different paint - would NOT have been caught before paint was part of the signature)",
		diagram._last_preview_signature != sig_after_first_refresh)

	diagram.queue_free()
	player.queue_free()
	await get_tree().process_frame

	if failures == 0:
		print("PASS: paperdoll preview now tracks the real player's Paint Rack color, including on a same-loadout repaint")
	get_tree().quit(0 if failures == 0 else 1)
