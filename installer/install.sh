#!/usr/bin/env bash
# Pixbots-G Linux installer - run from inside the extracted release
# archive (next to Pixbots-G.x86_64 and icon.png). Mirrors what the
# Windows Inno Setup installer does (a real launcher entry, chosen
# install location) without needing any packaging tooling beyond what's
# already on a normal Linux desktop - no root required, installs to the
# user's own home directory like any other well-behaved desktop app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${PIXBOTS_INSTALL_DIR:-$HOME/.local/share/Pixbots-G}"
DESKTOP_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"

echo "Installing Pixbots-G to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/. "$INSTALL_DIR"/
rm -f "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/Pixbots-G.x86_64"

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/pixbots-g.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Pixbots-G
Comment=Pixbots-G
Exec=$INSTALL_DIR/Pixbots-G.x86_64
Icon=$INSTALL_DIR/icon.png
Terminal=false
Categories=Game;
EOF
chmod +x "$DESKTOP_DIR/pixbots-g.desktop"

mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/Pixbots-G.x86_64" "$BIN_DIR/pixbots-g"

echo ""
echo "Done. Launch Pixbots-G from your application menu, or run 'pixbots-g'"
echo "from a terminal if $BIN_DIR is on your PATH."
