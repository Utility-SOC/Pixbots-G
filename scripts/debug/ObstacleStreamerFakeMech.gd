extends Node2D

# Stand-in for a Mech: just enough surface for the groups the streamer and autoloads read.
var is_boss := false
var is_dead := false
var _cached_separation := Vector2.ZERO
var target = null
