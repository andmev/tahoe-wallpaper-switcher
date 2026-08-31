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

if ! TAHOE_IDS=$(python3 - "$MANIFEST" "$VIDEOS" << 'PY'
import json, os, sys

manifest_path, videos_dir = sys.argv[1:]
period_aliases = {
    "MORNING": {"morning", "sunrise", "dawn"},
    "DAY": {"day"},
    "EVENING": {"evening", "sunset", "dusk"},
    "NIGHT": {"night"},
}

def normalized(value):
    return " ".join(str(value or "").lower().replace("_", " ").replace("-", " ").split())

def period_for(asset):
    label = normalized(asset.get("accessibilityLabel"))
    for period in period_aliases:
        if label == "tahoe " + period.lower():
            return period

    names = " ".join(normalized(asset.get(key)) for key in
                      ("accessibilityLabel", "localizedNameKey", "name", "title"))
    if "tahoe" not in names:
        return None

    time_of_day = normalized(asset.get("timeOfDay"))
    for period, aliases in period_aliases.items():
        if time_of_day in aliases:
            return period

    # Fallback for manifests that omit timeOfDay but retain an English key.
    for period, aliases in period_aliases.items():
        if any(" " + alias in " " + names for alias in aliases):
            return period
    return None

def is_downloaded(asset_id):
    return any(os.path.isfile(os.path.join(videos_dir, asset_id + ext))
               for ext in (".mov", ".mp4", ".m4v"))

with open(manifest_path, encoding="utf-8") as manifest_file:
    assets = json.load(manifest_file).get("assets", [])

for period in period_aliases:
    candidates = [asset for asset in assets if period_for(asset) == period]
    # Prefer the cached asset when the manifest contains duplicate/localized entries.
    selected = next((asset for asset in candidates if is_downloaded(asset.get("id", ""))),
                    candidates[0] if candidates else None)
    print(selected.get("id", "") if selected else "-", end=" ")
PY
); then
    echo "ERROR: Could not read wallpaper manifest."
    exit 1
fi
read -r TAHOE_ID_MORNING TAHOE_ID_DAY TAHOE_ID_EVENING TAHOE_ID_NIGHT <<< "$TAHOE_IDS"

echo ""
echo "Checking wallpapers..."
MISSING=0
for NAME in "Tahoe Morning" "Tahoe Day" "Tahoe Evening" "Tahoe Night"; do
    case "$NAME" in
        "Tahoe Morning") ID="$TAHOE_ID_MORNING" ;;
        "Tahoe Day")     ID="$TAHOE_ID_DAY" ;;
        "Tahoe Evening") ID="$TAHOE_ID_EVENING" ;;
        "Tahoe Night")   ID="$TAHOE_ID_NIGHT" ;;
    esac
    if [ -z "$ID" ] || [ "$ID" = "-" ]; then
        echo "  ✗ $NAME — not found in manifest"
        MISSING=1
    elif [ -f "$VIDEOS/$ID.mov" ] || [ -f "$VIDEOS/$ID.mp4" ] || [ -f "$VIDEOS/$ID.m4v" ]; then
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
    <key>StandardOutputPath</key>
    <string>/tmp/wallpaper-switch.log</string>
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
