#!/usr/bin/env osascript -l JavaScript
// wallpaper-switch.js
// Switches Tahoe Morning/Day/Evening/Night based on solar position.
// Only updates wallpaper or dark mode when a change is actually needed — no blinks.

ObjC.import('Foundation');

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  // ── Paths ──────────────────────────────────────────────────────────────────
  const home     = ObjC.unwrap($.NSHomeDirectory());
  const CONFIG   = home + "/Library/Scripts/wallpaper-switch-config.json";
  const PLIST    = home + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist";
  const MANIFEST = home + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json";

  // ── Location ───────────────────────────────────────────────────────────────
  // Reads config written by install.sh.
  // Falls back to Katowice defaults if the config file is missing.
  function loadConfig() {
    const data = $.NSData.dataWithContentsOfFile($(CONFIG));
    if (data.isNil()) return { useLocationServices: false, lat: 50.2649, lon: 19.0238 };
    const str = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
    try { return JSON.parse(str); }
    catch(e) { return { useLocationServices: false, lat: 50.2649, lon: 19.0238 }; }
  }

  // Persist updated coordinates (e.g. after travel detection)
  function saveConfig(cfg) {
    try {
      const data = $(JSON.stringify(cfg, null, 2) + '\n').dataUsingEncoding($.NSUTF8StringEncoding);
      data.writeToFileAtomically($(CONFIG), true);
    } catch(e) {}
  }

  // Haversine distance in km — detects when user has traveled far enough
  function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  // Fetch current location from IP geolocation (no permissions required).
  // Uses ipinfo.io (50k req/month free — safe at 96 runs/day).
  // Falls back silently to cached config coords when offline or rate-limited.
  function getLocationFromIPGeo() {
    try {
      const json = app.doShellScript(
        "/usr/bin/curl -fsSL --max-time 3 'https://ipinfo.io/json'"
      );
      const d = JSON.parse(json);
      // bogon = true means a private/reserved IP (no real geo)
      if (!d.loc || d.bogon) return null;
      const parts = d.loc.split(',');
      if (parts.length !== 2) return null;
      const lat = parseFloat(parts[0]);
      const lon = parseFloat(parts[1]);
      if (isNaN(lat) || isNaN(lon)) return null;
      return { lat, lon };
    } catch(e) { return null; }
  }

  const config = loadConfig();
  let LAT = config.lat;
  let LON = config.lon;
  let locationUpdated = false;

  if (config.useLocationServices) {
    const loc = getLocationFromIPGeo();
    if (loc) {
      const dist = haversineKm(config.lat, config.lon, loc.lat, loc.lon);
      if (dist > 50) {
        // User traveled — update cached coordinates so next run is instant
        config.lat = loc.lat;
        config.lon = loc.lon;
        saveConfig(config);
        locationUpdated = true;
      }
      LAT = loc.lat;
      LON = loc.lon;
    }
    // If IP geo is unavailable (offline / rate-limited), fall back to cached coordinates from config
  }

  // ── Read Tahoe IDs from Apple's manifest (stays correct after re-downloads) ─
  function loadTahoeIDs() {
    const data = $.NSData.dataWithContentsOfFile($(MANIFEST));
    if (data.isNil()) return null;

    const json = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
    const assets = JSON.parse(json).assets || [];

    const map = { morning: null, day: null, evening: null, night: null };
    const keys = {
      "Tahoe Morning": "morning",
      "Tahoe Day":     "day",
      "Tahoe Evening": "evening",
      "Tahoe Night":   "night",
    };
    for (const a of assets) {
      const period = keys[a.accessibilityLabel];
      if (period) map[period] = a.id;
    }
    return map;
  }

  const IDS = loadTahoeIDs();
  if (!IDS || Object.values(IDS).some(v => !v)) {
    return "ERROR: Could not find Tahoe wallpaper IDs in manifest.\nMake sure all 4 wallpapers are downloaded in System Settings → Wallpaper.";
  }

  // ── Solar calculation (pure JS Math — no python needed here) ───────────────
  const now = new Date();
  const N   = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);

  const toRad = d => d * Math.PI / 180;
  const B     = toRad(360 / 365.0 * (N - 81));
  const decl  = toRad(23.45 * Math.sin(B));
  const latR  = toRad(LAT);

  const cosHA  = (Math.sin(toRad(-0.8333)) - Math.sin(latR) * Math.sin(decl))
               / (Math.cos(latR) * Math.cos(decl));
  const ha     = Math.acos(Math.max(-1, Math.min(1, cosHA))) * 180 / Math.PI / 15.0;
  const eot    = (9.87 * Math.sin(2*B) - 7.53 * Math.cos(B) - 1.5 * Math.sin(B)) / 60.0;
  const tz     = -now.getTimezoneOffset() / 60;
  const sunrise = 12.0 - LON / 15.0 - eot - ha + tz;
  const sunset  = 12.0 - LON / 15.0 - eot + ha + tz;

  const h = now.getHours() + now.getMinutes() / 60.0;

  let period;
  if      (h < sunrise)          period = "night";
  else if (h < sunrise + 1.5)    period = "morning";
  else if (h < sunset  - 1.0)    period = "day";
  else if (h < sunset  + 0.5)    period = "evening";
  else                            period = "night";

  const wantDark  = (period === "evening" || period === "night");
  const desiredID = IDS[period];

  // ── Read current assetID directly via ObjC (no shell) ─────────────────────
  function getCurrentAssetID() {
    const data = $.NSData.dataWithContentsOfFile($(PLIST));
    if (data.isNil()) return null;

    const plist = $.NSPropertyListSerialization
      .propertyListWithDataOptionsFormatError(data, 0, null, null);
    if (plist.isNil()) return null;

    // Traverse the NSDictionary tree looking for aerials Choice with Configuration
    function find(obj) {
      if (obj.isNil && obj.isNil()) return null;

      if (obj.isKindOfClass($.NSDictionary)) {
        const choices = obj.objectForKey('Choices');
        if (!choices.isNil()) {
          const count = ObjC.unwrap(choices.count);
          for (let i = 0; i < count; i++) {
            const c = choices.objectAtIndex(i);
            if (!c.isNil() &&
                ObjC.unwrap(c.objectForKey('Provider')) === 'com.apple.wallpaper.choice.aerials') {
              const cfgData = c.objectForKey('Configuration');
              if (!cfgData.isNil() && ObjC.unwrap(cfgData.length) > 0) {
                const cfg = $.NSPropertyListSerialization
                  .propertyListWithDataOptionsFormatError(cfgData, 0, null, null);
                if (!cfg.isNil()) {
                  const assetID = cfg.objectForKey('assetID');
                  if (!assetID.isNil()) return ObjC.unwrap(assetID);
                }
              }
            }
          }
        }
        // Recurse into all values
        const keys = obj.allKeys;
        const kCount = ObjC.unwrap(keys.count);
        for (let i = 0; i < kCount; i++) {
          const r = find(obj.objectForKey(keys.objectAtIndex(i)));
          if (r) return r;
        }
      } else if (obj.isKindOfClass($.NSArray)) {
        const count = ObjC.unwrap(obj.count);
        for (let i = 0; i < count; i++) {
          const r = find(obj.objectAtIndex(i));
          if (r) return r;
        }
      }
      return null;
    }

    return find(plist);
  }

  // ── Update plist via Python helper written to /tmp ─────────────────────────
  function updatePlist(newID) {
    const py = [
      "import sys,plistlib,subprocess,os",
      "p,i=sys.argv[1],sys.argv[2]",
      "r=subprocess.run(['plutil','-convert','xml1','-o','-',p],capture_output=True)",
      "d=plistlib.loads(r.stdout)",
      "c=plistlib.dumps({'assetID':i},fmt=plistlib.FMT_BINARY)",
      "def u(x):",
      "  if isinstance(x,dict):",
      "    [x.__setitem__('Configuration',c) for ch in x.get('Choices',[]) if isinstance(ch,dict) and ch.get('Provider')=='com.apple.wallpaper.choice.aerials']",
      "    [u(v) for v in x.values()]",
      "  elif isinstance(x,list):[u(v) for v in x]",
      "u(d)",
      "t=p+'.tmp'",
      "open(t,'wb').write(plistlib.dumps(d,fmt=plistlib.FMT_BINARY))",
      "os.replace(t,p)",
    ].join("\n");

    $(py).writeToFileAtomicallyEncodingError(
      "/tmp/wp_update.py", true, $.NSUTF8StringEncoding, null);

    app.doShellScript(`python3 /tmp/wp_update.py '${PLIST}' '${newID}'`);

    // Restart wallpaper agent
    try {
      app.doShellScript("launchctl kickstart -k \"gui/$(id -u)/com.apple.wallpaper.agent\"");
    } catch(e) {
      try { app.doShellScript("killall WallpaperAgent"); } catch(_) {}
    }
  }

  // ── Apply changes only if needed (fixes the blink bug) ────────────────────
  const currentID = getCurrentAssetID();
  const wallpaperChanged = currentID !== desiredID;
  if (wallpaperChanged) updatePlist(desiredID);

  const sysEvents   = Application("System Events");
  const currentDark = sysEvents.appearancePreferences.darkMode();
  const darkChanged = wantDark !== currentDark;
  if (darkChanged) sysEvents.appearancePreferences.darkMode = wantDark;

  // ── Log: only on change, rotate daily ─────────────────────────────────────
  const LOG = "/tmp/wallpaper-switch.log";

  // Delete log file if it is older than 24 h (keeps /tmp clean forever)
  try {
    app.doShellScript(
      `find '${LOG}' -maxdepth 0 -mtime +0 -delete 2>/dev/null; true`
    );
  } catch(_) {}

  // Write only when something actually changed
  if (wallpaperChanged || darkChanged || locationUpdated) {
    const pad = n => String(n).padStart(2, '0');
    const dt  = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    const hh  = pad(now.getHours());
    const mm  = pad(now.getMinutes());
    const sr  = `${Math.floor(sunrise)}:${pad(Math.round((sunrise % 1) * 60))}`;
    const ss  = `${Math.floor(sunset)}:${pad(Math.round((sunset  % 1) * 60))}`;

    const changes = [];
    if (wallpaperChanged)  changes.push(`wallpaper→${period}`);
    if (darkChanged)       changes.push(`dark→${wantDark}`);
    if (locationUpdated)   changes.push(`location→${LAT.toFixed(4)},${LON.toFixed(4)}`);

    const line =
      `[${dt} ${hh}:${mm}] ${period} | sunrise=${sr} sunset=${ss} | ${changes.join(', ')}\n`;

    const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
    const fh   = $.NSFileHandle.fileHandleForWritingAtPath($(LOG));
    if (!fh.isNil()) {
      fh.seekToEndOfFile;
      fh.writeData(data);
      fh.closeFile;
    } else {
      $.NSFileManager.defaultManager
        .createFileAtPathContentsAttributes($(LOG), data, null);
    }
  }
}
