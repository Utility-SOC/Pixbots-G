extends Control
# Screenshot of the sponsor banners with their emblems.  godot --path . res://scripts/debug/SponsorBannerShot.tscn -- --out=/path.png
const PopupScript = preload("res://scripts/ui/GarageSponsorPopup.gd")
func _ready():
	var out = "/tmp/banners.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.split("=")[1]
	var bg = ColorRect.new(); bg.color = Color(0.12, 0.12, 0.15); bg.size = Vector2(1000, 600); add_child(bg)
	var grid = GridContainer.new(); grid.columns = 2; grid.position = Vector2(20, 20); add_child(grid)
	var helper = PopupScript.new(null)
	var ids = ["sniper", "defensive", "cloak", "mobility", "sensors", "efficiency", "power"]
	for i in range(ids.size()):
		grid.add_child(helper._make_banner(self, ids[i], i == 2, null))
	for f in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
