#!/usr/bin/env osascript -l JavaScript
// wallpaper-switch.js — Tahoe wallpaper switcher based on solar position
// Location is read from ~/Library/Scripts/wallpaper-switch-config.json.
// Only updates wallpaper / dark mode when a change is actually needed.

ObjC.import('Foundation');

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  // ── Paths ──────────────────────────────────────────────────────────────────
  const home     = ObjC.unwrap($.NSHomeDirectory());
  const CONFIG   = home + "/Library/Scripts/wallpaper-switch-config.json";
  const STATE    = home + "/Library/Scripts/wallpaper-switch-state.json";
  const PLIST    = home + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist";
  const MANIFEST = home + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json";

  // ── Config ────────────────────────────────────────────────────────────────
  function readConfig() {
    try {
      const data = $.NSData.dataWithContentsOfFile($(CONFIG));
      if (data.isNil()) return null;
      const str = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
      return JSON.parse(str);
    } catch(e) { return null; }
  }

  // ── Resolve current coordinates ────────────────────────────────────────────
  // Default: Apple Park, Cupertino CA — edit the config file to change
  const DEFAULTS = { lat: 37.3349, lon: -122.0090 };

  const cfg = readConfig() || {};
  const LAT = typeof cfg.lat === 'number' ? cfg.lat : DEFAULTS.lat;
  const LON = typeof cfg.lon === 'number' ? cfg.lon : DEFAULTS.lon;
  const locLabel = cfg.city ? `${cfg.city}` : `${LAT.toFixed(2)},${LON.toFixed(2)}`;

  // ── Read Tahoe IDs from Apple's manifest (no hardcoded values) ─────────────
  function loadTahoeIDs() {
    try {
      const raw = app.doShellScript(
        "python3 -c \"import json; d=json.load(open('" + MANIFEST + "')); " +
        "print(' '.join(a['id'] for n in ['Tahoe Morning','Tahoe Day','Tahoe Evening','Tahoe Night'] " +
        "for a in d['assets'] if a.get('accessibilityLabel')==n))\""
      );
      const parts = raw.trim().split(' ');
      if (parts.length !== 4) return null;
      return { morning: parts[0], day: parts[1], evening: parts[2], night: parts[3] };
    } catch(e) { return null; }
  }

  const IDS = loadTahoeIDs();
  if (!IDS) {
    return "ERROR: Could not read Tahoe IDs from manifest.\n" +
           "Make sure all 4 wallpapers are downloaded in System Settings → Wallpaper.";
  }

  // ── Solar calculation (pure JS Math) ──────────────────────────────────────
  const now    = new Date();
  const N      = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
  const toRad  = d => d * Math.PI / 180;
  const B      = toRad(360 / 365.0 * (N - 81));
  const decl   = toRad(23.45 * Math.sin(B));
  const latR   = toRad(LAT);
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

  // ── State file: persist last-applied period so we skip no-op runs ──────────
  // (The plist-based assetID read is unreliable: macOS stores Provider='default'
  //  after WallpaperAgent restarts, so it never matches 'aerials' and the old
  //  guard always returned null → always triggered a reload every 15 min.)
  function readState() {
    try {
      const data = $.NSData.dataWithContentsOfFile($(STATE));
      if (data.isNil()) return {};
      const str = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
      return JSON.parse(str);
    } catch(e) { return {}; }
  }

  function writeState(s) {
    $(JSON.stringify(s)).writeToFileAtomicallyEncodingError(
      STATE, true, $.NSUTF8StringEncoding, null
    );
  }

  // ── Update wallpaper plist + restart agent ────────────────────────────────
  function updatePlist(newID) {
    const py = [
      "import sys,plistlib,subprocess,os",
      "p,i=sys.argv[1],sys.argv[2]",
      "r=subprocess.run(['plutil','-convert','xml1','-o','-',p],capture_output=True)",
      "d=plistlib.loads(r.stdout)",
      "c=plistlib.dumps({'assetID':i},fmt=plistlib.FMT_BINARY)",
      "def u(x):",
      "  if isinstance(x,dict):",
      "    for ch in x.get('Choices',[]):",
      "      if isinstance(ch,dict):",
      "        ch['Provider']='com.apple.wallpaper.choice.aerials'",
      "        ch['Configuration']=c",
      "    for v in x.values():u(v)",
      "  elif isinstance(x,list):",
      "    for v in x:u(v)",
      "u(d)",
      "t=p+'.tmp'",
      "open(t,'wb').write(plistlib.dumps(d,fmt=plistlib.FMT_BINARY))",
      "os.replace(t,p)",
    ].join("\n");
    $(py).writeToFileAtomicallyEncodingError("/tmp/wp_update.py", true, $.NSUTF8StringEncoding, null);
    app.doShellScript("python3 /tmp/wp_update.py '" + PLIST + "' '" + newID + "'");
    try { app.doShellScript("killall WallpaperAgent"); } catch(_) {}
  }

  // ── Apply only if something actually changed ───────────────────────────────
  const state            = readState();
  const wallpaperChanged = state.period !== period || state.desiredID !== desiredID;

  // Dark-mode: read live from System Events (always reliable)
  const sysEvents   = Application("System Events");
  const currentDark = sysEvents.appearancePreferences.darkMode();
  const darkChanged = wantDark !== currentDark;

  // Nothing to do — exit silently without touching WallpaperAgent
  if (!wallpaperChanged && !darkChanged) return;

  if (wallpaperChanged) updatePlist(desiredID);
  if (darkChanged)      sysEvents.appearancePreferences.darkMode = wantDark;

  // Persist applied state so next run can skip if period hasn't changed
  if (wallpaperChanged) writeState({ period, desiredID });

  // ── Log (only on change) ───────────────────────────────────────────────────
  if (wallpaperChanged || darkChanged) {
    const pad = n => String(n).padStart(2, '0');
    const hh  = pad(now.getHours()), mm = pad(now.getMinutes());
    const sr  = `${Math.floor(sunrise)}:${pad(Math.round((sunrise%1)*60))}`;
    const ss  = `${Math.floor(sunset)}:${pad(Math.round((sunset%1)*60))}`;
    const changes = [];
    if (wallpaperChanged) changes.push(`wallpaper→${period}`);
    if (darkChanged)      changes.push(`dark→${wantDark}`);
    return `${hh}:${mm} | ${locLabel} | ${period} | ${sr}↑ ${ss}↓ | ${changes.join(' ')}`;
  }
}
