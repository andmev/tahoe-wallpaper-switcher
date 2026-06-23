# Tahoe Wallpaper Switcher

Automatically switches **Tahoe Morning / Day / Evening / Night** wallpapers based on real solar position for your location — and toggles **Dark / Light mode** accordingly.

No third-party apps. Pure JXA (JavaScript for Automation) + python3 (both pre-installed on macOS).

---

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main/install.sh)"
```

## Uninstall

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main/uninstall.sh)"
```

---

## Requirements

- macOS Tahoe (26+)
- All four wallpapers downloaded via **System Settings → Wallpaper**:
  `Tahoe Morning`, `Tahoe Day`, `Tahoe Evening`, `Tahoe Night`

---

## How it works

| Period | Wallpaper | Mode |
|--------|-----------|------|
| Sunrise → +1.5 h | Tahoe Morning | ☀️ Light |
| Morning → 1 h before sunset | Tahoe Day | ☀️ Light |
| 1 h before sunset → +0.5 h | Tahoe Evening | 🌙 Dark |
| After sunset | Tahoe Night | 🌙 Dark |

Sunrise and sunset are calculated daily using your coordinates — **no internet required**, no static schedule. Adapts automatically to every season.

Wallpaper and dark mode are updated **only when the period actually changes** — no unnecessary flickering.

---

## Location

Your coordinates are stored in a single JSON file:

```
~/Library/Scripts/wallpaper-switch-config.json
```

The installer creates this file with **Apple Park, Cupertino CA** as the default. Edit it any time to set your own location:

```json
{
  "lat": 37.3349,
  "lon": -122.0090
}
```

Find your coordinates at [latlong.net](https://www.latlong.net).

**Quick reference:**

| City | lat | lon |
|------|-----|-----|
| Apple Park, Cupertino CA | 37.3349 | -122.0090 |
| New York, USA | 40.7128 | -74.0060 |
| London, UK | 51.5074 | -0.1278 |
| Paris, France | 48.8566 | 2.3522 |
| Tokyo, Japan | 35.6762 | 139.6503 |
| Sydney, Australia | -33.8688 | 151.2093 |

---

## Manual installation

If you prefer not to run remote scripts, follow these steps instead.

### 1 — Download all four Tahoe wallpapers

Open **System Settings → Wallpaper** and download:
`Tahoe Morning`, `Tahoe Day`, `Tahoe Evening`, `Tahoe Night`.

### 2 — Copy the script

```bash
mkdir -p ~/Library/Scripts

curl -fsSL \
  https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/main/wallpaper-switch.js \
  -o ~/Library/Scripts/wallpaper-switch.js

chmod +x ~/Library/Scripts/wallpaper-switch.js
```

### 3 — Create the location config

```bash
cat > ~/Library/Scripts/wallpaper-switch-config.json << 'EOF'
{
  "lat": 37.3349,
  "lon": -122.0090
}
EOF
```

Then open the file in any text editor and replace the coordinates with your own.

### 4 — Create the LaunchAgent

This makes the script run automatically every 15 minutes and at login.

```bash
mkdir -p ~/Library/LaunchAgents

cat > ~/Library/LaunchAgents/com.user.wallpaper-switch.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.wallpaper-switch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/osascript</string>
        <string>-l</string>
        <string>JavaScript</string>
        <string>$HOME/Library/Scripts/wallpaper-switch.js</string>
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
```

### 5 — Load and run

```bash
launchctl load ~/Library/LaunchAgents/com.user.wallpaper-switch.plist

# Run once immediately to verify
osascript -l JavaScript ~/Library/Scripts/wallpaper-switch.js
```

### Manual uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.user.wallpaper-switch.plist

rm ~/Library/LaunchAgents/com.user.wallpaper-switch.plist
rm ~/Library/Scripts/wallpaper-switch.js
rm ~/Library/Scripts/wallpaper-switch-config.json
```

---

## Why not standard macOS dynamic wallpaper?

Apple ships `Tahoe Morning/Day/Evening/Night` as **video files** (`.mov`), not a single dynamic `.heic`. There is no public API to switch aerial/video wallpapers programmatically. This script works by reading wallpaper IDs directly from Apple's manifest (`entries.json`) and updating the wallpaper preference plist, then restarting the wallpaper agent.

---

## Tested on

- macOS Tahoe 26.x, Apple Silicon
