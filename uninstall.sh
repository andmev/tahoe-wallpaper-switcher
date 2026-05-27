#!/bin/bash
# uninstall.sh
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main/uninstall.sh)"
set -e

LABEL="com.user.wallpaper-switch"
AGENTS_DIR="$HOME/Library/LaunchAgents"
SCRIPTS_DIR="$HOME/Library/Scripts"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Tahoe Wallpaper Switcher — Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

launchctl unload "$AGENTS_DIR/$LABEL.plist" 2>/dev/null \
    && echo "  ✓ LaunchAgent unloaded" || true
rm -f "$AGENTS_DIR/$LABEL.plist"        && echo "  ✓ Removed plist"
rm -f "$SCRIPTS_DIR/wallpaper-switch.js" && echo "  ✓ Removed script"
rm -f /tmp/wallpaper-switch.log /tmp/wallpaper-switch.err /tmp/wp_update.py

echo ""
echo "  ✅ Uninstalled. Wallpaper settings are unchanged."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
