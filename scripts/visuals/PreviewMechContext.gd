class_name PreviewMechContext
extends Node2D

# Minimal stand-in "mech" for MechRenderer to read from when it's being used
# purely as a Garage preview (ComponentDiagramView) rather than attached to a
# real, physics-simulated Mech.gd instance. MechRenderer._rebuild_visuals()
# reads a handful of properties straight off get_parent() ("is_player" in
# mech, mech.combat_role, "is_boss" in mech, mech.visual_seed) via safe
# `"prop" in mech` checks - a bare Node2D fails all of those checks and falls
# through to the generic gray-blue default profile, which is exactly the
# flat "little grey guy" look this class exists to get away from. Exposing
# the same properties here (always is_player = true, since this only ever
# previews the PLAYER's own mech) makes the preview pick up the real hero
# color/scale/accent profile, so it actually looks like the bot you'll see
# on the battlefield.
var is_player: bool = true
var combat_role: String = ""
var is_boss: bool = false
var visual_seed: int = 0
