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

# ── Configure location ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Location Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Sunrise/sunset times are calculated from your coordinates."
echo "  Choose how the script should determine your location:"
echo ""
echo "  [1] Location Services  (recommended)"
echo "      macOS detects your GPS position automatically."
echo "      If you travel (e.g. San Francisco → London), the wallpaper"
echo "      schedule adapts to your new timezone on the next run."
echo ""
echo "  [2] Manual coordinates"
echo "      Enter latitude/longitude once. Won't change automatically"
echo "      if you travel — update the config file manually."
echo ""
read -p "  Your choice [1/2]: " loc_choice
echo ""

# Helper: call CoreLocation via a JXA one-liner, returns JSON
try_corelocation() {
    osascript -l JavaScript << 'JXAEOF'
ObjC.import('CoreLocation');
ObjC.import('Foundation');
(function() {
    try {
        if (!$.CLLocationManager.locationServicesEnabled) {
            return JSON.stringify({error: 'disabled'});
        }
        var status = $.CLLocationManager.authorizationStatus;
        if (status === 2) return JSON.stringify({error: 'denied'});
        if (status === 1) return JSON.stringify({error: 'restricted'});
        var mgr = $.CLLocationManager.alloc.init;
        var loc = mgr.location;
        if (!loc || loc.isNil()) return JSON.stringify({error: 'not_available'});
        var c = loc.coordinate;
        if (Math.abs(c.latitude) < 0.001 && Math.abs(c.longitude) < 0.001) {
            return JSON.stringify({error: 'invalid'});
        }
        return JSON.stringify({lat: c.latitude, lon: c.longitude});
    } catch(e) {
        return JSON.stringify({error: String(e)});
    }
})()
JXAEOF
}

# Helper: extract one field from a JSON string via Python (always exits 0)
json_field() {
    local field="$1"
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('$field', ''))
except:
    pass
" 2>/dev/null
}

USE_LOCATION_SERVICES="false"
FINAL_LAT=""
FINAL_LON=""

if [[ "$loc_choice" == "1" ]]; then
    echo "  Contacting macOS Location Services..."
    LOC_JSON=$(try_corelocation 2>/dev/null || echo '{"error":"script_failed"}')
    LOC_LAT=$(echo "$LOC_JSON" | json_field lat)
    LOC_LON=$(echo "$LOC_JSON" | json_field lon)
    LOC_ERR=$(echo "$LOC_JSON" | json_field error)

    if [ -n "$LOC_LAT" ] && [ -n "$LOC_LON" ]; then
        echo "  ✓ Location detected: $LOC_LAT, $LOC_LON"
        USE_LOCATION_SERVICES="true"
        FINAL_LAT="$LOC_LAT"
        FINAL_LON="$LOC_LON"
    else
        echo ""
        case "$LOC_ERR" in
            disabled)
                echo "  ⚠️  Location Services are disabled system-wide."
                echo "      Enable: System Settings → Privacy & Security → Location Services"
                ;;
            denied)
                echo "  ⚠️  Terminal does not have location access."
                echo "      Fix:    System Settings → Privacy & Security → Location Services"
                echo "              → enable your terminal app (Terminal / iTerm2 / etc.)"
                ;;
            restricted)
                echo "  ⚠️  Location access is restricted on this device."
                ;;
            not_available|invalid)
                echo "  ⚠️  No location fix cached yet."
                echo "      Tip: open Maps or Weather once so macOS caches a location, then retry."
                ;;
            *)
                echo "  ⚠️  Location unavailable: $LOC_ERR"
                ;;
        esac
        echo ""
        read -p "  Retry? [y/N] " retry_yn
        if [[ "$retry_yn" =~ ^[Yy]$ ]]; then
            echo ""
            echo "  Retrying..."
            LOC_JSON=$(try_corelocation 2>/dev/null || echo '{"error":"script_failed"}')
            LOC_LAT=$(echo "$LOC_JSON" | json_field lat)
            LOC_LON=$(echo "$LOC_JSON" | json_field lon)
            if [ -n "$LOC_LAT" ] && [ -n "$LOC_LON" ]; then
                echo "  ✓ Location detected: $LOC_LAT, $LOC_LON"
                USE_LOCATION_SERVICES="true"
                FINAL_LAT="$LOC_LAT"
                FINAL_LON="$LOC_LON"
            fi
        fi
        if [ -z "$FINAL_LAT" ]; then
            echo ""
            echo "  Falling back to manual coordinates."
        fi
    fi
fi

# Manual entry — chosen directly or as fallback after failed Location Services
if [ -z "$FINAL_LAT" ] || [ -z "$FINAL_LON" ]; then
    echo "  Enter your coordinates (look up yours at https://www.latlong.net)"
    echo ""
    read -p "  Latitude  (e.g.  50.2649 for Katowice): " FINAL_LAT
    read -p "  Longitude (e.g.  19.0238 for Katowice): " FINAL_LON
    USE_LOCATION_SERVICES="false"
fi
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

# Write location config (read by wallpaper-switch.js on every run)
cat > "$SCRIPTS_DIR/wallpaper-switch-config.json" << JSONCFG
{
  "useLocationServices": $USE_LOCATION_SERVICES,
  "lat": $FINAL_LAT,
  "lon": $FINAL_LON
}
JSONCFG
echo "  ✓ Config  → $SCRIPTS_DIR/wallpaper-switch-config.json"

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
