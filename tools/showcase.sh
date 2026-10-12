#!/usr/bin/env bash
# Opens the graphics showcase (every new map type, war era, set piece and shop backdrop). Keys are listed on screen.
#   tools/showcase.sh [--vulkan]
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/pixbots/Godot_v4.6.3-stable_linux.x86_64}"
RENDERER=gl_compatibility
[ "$1" = "--vulkan" ] && RENDERER=forward_plus
exec "$GODOT" --path "$HERE" --rendering-method "$RENDERER" res://scripts/debug/GraphicsShowcase.tscn
