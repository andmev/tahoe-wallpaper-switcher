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
| Sunrise → +1.5h | Tahoe Morning | ☀️ Light |
| Morning → 1h before sunset | Tahoe Day | ☀️ Light |
| 1h before sunset → +0.5h | Tahoe Evening | 🌙 Dark |
| After sunset | Tahoe Night | 🌙 Dark |

Sunrise and sunset are calculated daily using your coordinates — **no internet required**, no static schedule. Adapts automatically to every season.

If you choose **Location Services** during install, the script re-checks your GPS position on every run (every 15 min). Move further than 50 km — say, fly from San Francisco to London — and the schedule automatically recalibrates to the new timezone and solar position.

Wallpaper and dark mode are updated **only when the period actually changes** — no unnecessary flickering.

---

## Configure location

During installation you choose how the script determines your location:

### Option 1 — Auto-detect (recommended)

Your city is resolved from your **IP address** — no permissions or system settings required, works on the very first run.

The script re-checks your position on every run (every 15 min). If you travel further than 50 km — say, fly from San Francisco to London — the schedule automatically recalibrates to the new timezone and solar position.

> Works anywhere. The only case where it won't give your real location is if you are on a VPN that exits in another country — use manual coordinates then.

### Option 2 — Manual coordinates

Enter your latitude/longitude once during installation. To update later, edit:

```
~/Library/Scripts/wallpaper-switch-config.json
```

```json
{
  "useLocationServices": false,
  "lat": 50.2649,
  "lon": 19.0238
}
```

| City | LAT | LON |
|------|-----|-----|
| Katowice, Poland | 50.2649 | 19.0238 |
| Warsaw, Poland | 52.2297 | 21.0122 |
| London, UK | 51.5074 | -0.1278 |
| New York, USA | 40.7128 | -74.0060 |
| Tokyo, Japan | 35.6762 | 139.6503 |
| Sydney, Australia | -33.8688 | 151.2093 |

---

## Why not standard macOS dynamic wallpaper?

Apple ships `Tahoe Morning/Day/Evening/Night` as **video files** (`.mov`), not a single dynamic `.heic`. There is no public API to switch aerial/video wallpapers programmatically. This script works by reading wallpaper IDs directly from Apple's manifest (`entries.json`) and updating the wallpaper preference plist, then restarting the wallpaper agent.

---

## Tested on

- macOS Tahoe 26.x, Apple Silicon
