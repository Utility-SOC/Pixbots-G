class_name BrandRegistry
extends RefCounted

# Corporate Sponsorships (Status.md queue item, task #17). Seven brands, each
# with its own signature tile(s) - see scripts/tiles/brands/ for the actual
# tile classes. Design locked with Natalia 2026-07-16:
#   - Brand tiles are plain Mythic rarity (no separate tier) - just rendered
#     BRAND_COLOR (dark blue) with the company's logo instead of the normal
#     Mythic tint, so they read as a distinct "corporate" tier visually
#     without needing a 6th rarity value threaded through every rarity-
#     indexed table in the codebase (TileStatsRegistry, DROP_RATES, etc.).
#   - Loot bias via WEIGHTS only, never a hard filter (locked ruling): every
#     boss from wave 100+ is affiliated with a random brand and its kill
#     drops ONE tile from that brand's set regardless of the player's own
#     sponsorship - that's how an unaligned/differently-aligned player can
#     still eventually get any brand's tiles. A player sponsored by a brand
#     ALSO gets a bonus drip-feed tile from their OWN brand on every boss
#     kill that ISN'T already their own brand's boss (no double-dip when you
#     beat your own sponsor's champion - see LootManager.generate_loot_for_mech).
#   - Sponsorship itself unlocks at wave 125 (GarageMenu/WarRoomMenu UI, not
#     built yet - see task tracker), freely re-selectable later, no penalty,
#     "Free Agent" (no sponsorship) always stays a valid choice.
# Sprite art deferred - logos are placeholder procedural marks for now, per
# the locked "procedural visuals are the default" ruling.

const BRAND_COLOR = Color(0.08, 0.12, 0.4) # shared dark blue for every brand's tiles

const BRAND_IDS = ["sniper", "defensive", "cloak", "mobility", "sensors", "efficiency", "power"]

# Placeholder display names - easy to reskin later, not load-bearing anywhere
# except UI text.
const BRAND_NAMES = {
	"sniper": "Farsight Optics",
	"defensive": "Aegis Dynamics",
	"cloak": "Umbra Systems",
	"mobility": "Velocity Works",
	"sensors": "Keeneye Sensing",
	"efficiency": "Prime Circuits",
	"power": "Gridwork Distribution",
}

# One-letter placeholder "logo" mark drawn on brand tiles until real sprite
# art lands - see MechRenderer/GarageGridRenderer's tile-drawing code.
const BRAND_LOGO_LETTER = {
	"sniper": "F",
	"defensive": "A",
	"cloak": "U",
	"mobility": "V",
	"sensors": "K",
	"efficiency": "P",
	"power": "G",
}

static func is_valid_brand(id: String) -> bool:
	return BRAND_IDS.has(id)

static func random_brand() -> String:
	return BRAND_IDS[randi() % BRAND_IDS.size()]

static func display_name(id: String) -> String:
	return BRAND_NAMES.get(id, "Unknown")

static func logo_letter(id: String) -> String:
	return BRAND_LOGO_LETTER.get(id, "?")
