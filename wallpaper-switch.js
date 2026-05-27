#!/usr/bin/env osascript -l JavaScript
// wallpaper-switch.js
// Switches Tahoe Morning/Day/Evening/Night based on solar position.
// Only updates wallpaper or dark mode when a change is actually needed — no blinks.

ObjC.import('Foundation');

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  // ── Config ─────────────────────────────────────────────────────────────────
  const LAT = 50.2649;   // Katowice, Poland  ← change to your location
  const LON = 19.0238;

  const home     = ObjC.unwrap($.NSHomeDirectory());
  const PLIST    = home + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist";
  const MANIFEST = home + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json";

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

  const sysEvents  = Application("System Events");
  const currentDark = sysEvents.appearancePreferences.darkMode();
  const darkChanged = wantDark !== currentDark;
  if (darkChanged) sysEvents.appearancePreferences.darkMode = wantDark;

  // ── Log ────────────────────────────────────────────────────────────────────
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const sr = `${Math.floor(sunrise)}:${String(Math.round((sunrise % 1) * 60)).padStart(2,'0')}`;
  const ss = `${Math.floor(sunset)}:${String(Math.round((sunset  % 1) * 60)).padStart(2,'0')}`;

  return [
    `${hh}:${mm} | ${period} | sunrise=${sr} sunset=${ss}`,
    `  wallpaper: ${wallpaperChanged ? `updated → ${period}` : "no change"}`,
    `  dark mode: ${darkChanged      ? `updated → ${wantDark}` : "no change"}`,
  ].join("\n");
}
