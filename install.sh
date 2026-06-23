#!/bin/bash
# install.sh — Works both ways:
#   curl install:  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main/install.sh)"
#   local install: bash install.sh
set -e

RAW="https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main"
SCRIPTS_DIR="$HOME/Library/Scripts"
AGENTS_DIR="$HOME/Library/LaunchAgents"
LABEL="com.user.wallpaper-switch"
MANIFEST="$HOME/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"
VIDEOS="$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Tahoe Wallpaper Switcher — Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Check macOS version ──────────────────────────────────────────────────────
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 26 ]; then
    echo "⚠️  Warning: macOS Tahoe (26+) required. Detected: $(sw_vers -productVersion)"
    read -p "   Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# ── Check wallpapers are downloaded ─────────────────────────────────────────
if [ ! -f "$MANIFEST" ]; then
    echo "⚠️  Wallpaper manifest not found."
    echo "   Please open System Settings → Wallpaper to initialise the wallpaper system."
    exit 1
fi

eval "$(python3 - "$MANIFEST" << 'PY'
import json, sys
for a in json.load(open(sys.argv[1])).get('assets', []):
    if a.get('accessibilityLabel') in ["Tahoe Morning","Tahoe Day","Tahoe Evening","Tahoe Night"]:
        key = a['accessibilityLabel'].upper().replace(' ', '_')
        print(f"TAHOE_ID_{key}='{a['id']}'")
PY
)"

echo ""
echo "Checking wallpapers..."
MISSING=0
for NAME in "Tahoe Morning" "Tahoe Day" "Tahoe Evening" "Tahoe Night"; do
    KEY="TAHOE_ID_$(echo "$NAME" | tr '[:lower:] ' '[:upper:]_')"
    ID="${!KEY}"
    if [ -z "$ID" ]; then
        echo "  ✗ $NAME — not found in manifest"
        MISSING=1
    elif [ -f "$VIDEOS/$ID.mov" ]; then
        echo "  ✓ $NAME"
    else
        echo "  ✗ $NAME — NOT downloaded"
        MISSING=1
    fi
done

if [ "$MISSING" = "1" ]; then
    echo ""
    echo "⚠️  Some wallpapers are missing."
    echo "   Open System Settings → Wallpaper and download:"
    echo "   Tahoe Morning, Tahoe Day, Tahoe Evening, Tahoe Night"
    echo "   Then re-run this installer."
    exit 1
fi

# ── Location config ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Location Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Sunrise/sunset times are calculated from your coordinates."
echo "  A config file with Apple Park defaults will be created at:"
echo ""
echo "    $SCRIPTS_DIR/wallpaper-switch-config.json"
echo ""
echo "  To set your own location, edit that file and update lat/lon."
echo "  Find your coordinates at: https://www.latlong.net"
echo ""

# ── Download & install script ────────────────────────────────────────────────
echo ""
echo "Installing..."
mkdir -p "$SCRIPTS_DIR"

# Use local file if running from cloned repo, otherwise download
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)/wallpaper-switch.js"
if [ -f "$SCRIPT_SRC" ]; then
    cp "$SCRIPT_SRC" "$SCRIPTS_DIR/wallpaper-switch.js"
else
    curl -fsSL "$RAW/wallpaper-switch.js" -o "$SCRIPTS_DIR/wallpaper-switch.js"
fi
chmod +x "$SCRIPTS_DIR/wallpaper-switch.js"
echo "  ✓ Script → $SCRIPTS_DIR/wallpaper-switch.js"

# Write location config — defaults to Apple Park, Cupertino CA (preserve on reinstall)
if [ ! -f "$SCRIPTS_DIR/wallpaper-switch-config.json" ]; then
    cat > "$SCRIPTS_DIR/wallpaper-switch-config.json" << 'JSONCFG'
{
  "lat": 37.3349,
  "lon": -122.0090
}
JSONCFG
    echo "  ✓ Config  → $SCRIPTS_DIR/wallpaper-switch-config.json  (Apple Park defaults)"
else
    echo "  ✓ Config  → $SCRIPTS_DIR/wallpaper-switch-config.json  (existing, preserved)"
fi

# ── Install launchd agent ────────────────────────────────────────────────────
mkdir -p "$AGENTS_DIR"
cat > "$AGENTS_DIR/$LABEL.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/osascript</string>
        <string>-l</string>
        <string>JavaScript</string>
        <string>$SCRIPTS_DIR/wallpaper-switch.js</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardErrorPath</key>
    <string>/tmp/wallpaper-switch.err</string>
</dict>
</plist>
EOF
echo "  ✓ LaunchAgent → $AGENTS_DIR/$LABEL.plist"

launchctl unload "$AGENTS_DIR/$LABEL.plist" 2>/dev/null || true
launchctl load   "$AGENTS_DIR/$LABEL.plist"
echo "  ✓ LaunchAgent loaded (runs every 15 min + at login)"

# ── Run once now ─────────────────────────────────────────────────────────────
echo ""
echo "Running now..."
osascript -l JavaScript "$SCRIPTS_DIR/wallpaper-switch.js"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Installation complete!"
echo ""
echo "  Location config: $SCRIPTS_DIR/wallpaper-switch-config.json"
echo ""
echo "  View log:   cat /tmp/wallpaper-switch.log"
echo "  Uninstall:  /bin/bash -c \"\$(curl -fsSL $RAW/uninstall.sh)\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
