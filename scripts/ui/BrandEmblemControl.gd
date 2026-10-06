extends Control

# A Control that draws one brand emblem (see BrandEmblem.gd), centred in its rect.
const Emblem = preload("res://scripts/ui/BrandEmblem.gd")
const Registry = preload("res://scripts/core/BrandRegistry.gd")

var brand_id: String = ""

func _draw() -> void:
	if brand_id == "":
		return
	var r = minf(size.x, size.y) * 0.38
	Emblem.draw(self, brand_id, size * 0.5, r, Registry.accent_color(brand_id))
