class_name ShieldGeneratorTile
extends "res://scripts/tiles/ShieldTile.gd"

# DEPRECATED - kept only so saves/builds that serialized this script path
# still load. ShieldGeneratorTile used a LINEAR energy scaling
# (1.0 + rarity * 0.5) that didn't hold up across the rarity range; ShieldTile
# is the canonical Shield Generator, using the tuned per-rarity curve
# ([1.1, 1.5, 2.5, 5.0, 10.0]). This is now a thin subclass so any existing
# ShieldGeneratorTile instance inherits ShieldTile's behavior wholesale (same
# tile_type "Shield Generator", same Mythic Aegis/Deflector toggle, same
# shield-synergy tracking) - no more two-classes-one-tile_type "mixed system".
# New code loads ShieldTile.gd directly; nothing should instantiate this.
