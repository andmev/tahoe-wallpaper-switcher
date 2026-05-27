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
# Detect Mac hardware model to choose the better default
HW_MODEL=$(sysctl -n hw.model 2>/dev/null)
if echo "$HW_MODEL" | grep -qi '^MacBook'; then
    IS_PORTABLE=true
else
    IS_PORTABLE=false
fi

if [ "$IS_PORTABLE" = "true" ]; then
    echo "  [1] Auto-detect  (recommended)"
    echo "      Your city is resolved from your IP address — no permissions"
    echo "      needed, works on first run. If you travel (San Francisco →"
    echo "      London), the schedule adapts automatically on the next run."
    echo ""
    echo "  [2] Manual coordinates"
    echo "      Enter latitude/longitude once. Update the config file"
    echo "      manually if you move."
else
    echo "  [1] Auto-detect"
    echo "      Your city is resolved from your IP address — no permissions"
    echo "      needed, works on first run."
    echo ""
    echo "  [2] Manual coordinates  (recommended)"
    echo "      Enter latitude/longitude once. Update the config file"
    echo "      manually if you move."
    echo "      Find your coordinates at https://www.latlong.net"
fi
echo ""
read -p "  Your choice [1/2]: " loc_choice
echo ""

# Helper: resolve location from IP — tries three providers, stops at first success
get_ip_location() {
    local TMP result
    TMP=$(mktemp /tmp/tahoe_geo.XXXXXX) || { echo '{"error":"mktemp"}'; return; }
    result=''

    # 1. ipinfo.io  → {"loc":"lat,lon","city":"...","country":"CC"}  (50k/month free)
    if [ -z "$result" ] && curl -sSL --max-time 5 "https://ipinfo.io/json" -o "$TMP" 2>/dev/null; then
        result=$(python3 -c "
import json
try:
    d=json.load(open('$TMP'))
    loc=d.get('loc','')
    if ',' in loc and not d.get('bogon'):
        a,b=loc.split(',',1)
        print(json.dumps({'latitude':float(a),'longitude':float(b),'city':d.get('city',''),'country_name':d.get('country','')}))
except: pass
" 2>/dev/null || true)
    fi

    # 2. ipapi.co   → {"latitude":N,"longitude":N,"city":"...","country_name":"..."}  (1k/day free)
    if [ -z "$result" ] && curl -sSL --max-time 5 "https://ipapi.co/json/" -o "$TMP" 2>/dev/null; then
        result=$(python3 -c "
import json
try:
    d=json.load(open('$TMP'))
    if not d.get('error') and 'latitude' in d:
        print(json.dumps({'latitude':float(d['latitude']),'longitude':float(d['longitude']),'city':d.get('city',''),'country_name':d.get('country_name','')}))
except: pass
" 2>/dev/null || true)
    fi

    # 3. ip-api.com → {"lat":N,"lon":N,"city":"...","country":"..."}  (45 req/min, free)
    if [ -z "$result" ] && curl -sSL --max-time 5 "http://ip-api.com/json?fields=lat,lon,city,country" -o "$TMP" 2>/dev/null; then
        result=$(python3 -c "
import json
try:
    d=json.load(open('$TMP'))
    if d.get('lat') and d.get('lon'):
        print(json.dumps({'latitude':float(d['lat']),'longitude':float(d['lon']),'city':d.get('city',''),'country_name':d.get('country','')}))
except: pass
" 2>/dev/null || true)
    fi

    rm -f "$TMP"
    if [ -n "$result" ]; then echo "$result"; else echo '{"error":"no_internet"}'; fi
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
    echo "  Detecting your location..."
    LOC_JSON=$(get_ip_location)
    LOC_LAT=$(echo "$LOC_JSON" | json_field latitude)
    LOC_LON=$(echo "$LOC_JSON" | json_field longitude)
    LOC_CITY=$(echo "$LOC_JSON" | json_field city)
    LOC_COUNTRY=$(echo "$LOC_JSON" | json_field country_name)

    if [ -n "$LOC_LAT" ] && [ -n "$LOC_LON" ]; then
        echo "  ✓ Detected: $LOC_CITY, $LOC_COUNTRY  ($LOC_LAT, $LOC_LON)"
        USE_LOCATION_SERVICES="true"
        FINAL_LAT="$LOC_LAT"
        FINAL_LON="$LOC_LON"
    else
        echo ""
        echo "  ⚠️  Could not detect location (no internet or service unavailable)."
        echo "      Falling back to manual coordinates."
    fi
fi

# Manual entry — chosen directly or as fallback
if [ -z "$FINAL_LAT" ] || [ -z "$FINAL_LON" ]; then
    echo "  Enter your coordinates:"
    echo "  (Look up yours at https://www.latlong.net )"
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
