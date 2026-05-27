#!/usr/bin/env osascript -l JavaScript
// wallpaper-switch.js — Tahoe wallpaper switcher based on solar position
// Only updates wallpaper / dark mode when a change is actually needed.

ObjC.import('Foundation');

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  // ── Config: set your coordinates here ─────────────────────────────────────
  const LAT = 50.2649;  // Katowice, Poland  ← change to your latitude
  const LON = 19.0238;  //                   ← change to your longitude

  // ── Paths ──────────────────────────────────────────────────────────────────
  const home     = ObjC.unwrap($.NSHomeDirectory());
  const PLIST    = home + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist";
  const MANIFEST = home + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json";

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

  // ── Solar calculation (pure JS — no network, no python) ───────────────────
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

  // ── Read current assetID via Python ────────────────────────────────────────
  function getCurrentAssetID() {
    const py = [
      "import plistlib,subprocess",
      "r=subprocess.run(['plutil','-convert','xml1','-o','-','" + PLIST + "'],capture_output=True)",
      "d=plistlib.loads(r.stdout)",
      "def f(x):",
      "  if isinstance(x,dict):",
      "    for c in x.get('Choices',[]):",
      "      if isinstance(c,dict) and c.get('Provider')=='com.apple.wallpaper.choice.aerials' and c.get('Configuration'):",
      "        return plistlib.loads(c['Configuration']).get('assetID','')",
      "    for v in x.values():",
      "      r=f(v)",
      "      if r:return r",
      "  elif isinstance(x,list):",
      "    for v in x:",
      "      r=f(v)",
      "      if r:return r",
      "  return ''",
      "print(f(d))",
    ].join("\n");
    $(py).writeToFileAtomicallyEncodingError("/tmp/wp_read.py", true, $.NSUTF8StringEncoding, null);
    try { return app.doShellScript("python3 /tmp/wp_read.py").trim() || null; }
    catch(e) { return null; }
  }

  // ── Update plist + restart agent via Python ────────────────────────────────
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
      "      if isinstance(ch,dict) and ch.get('Provider')=='com.apple.wallpaper.choice.aerials':",
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
    // launchctl kickstart is blocked by SIP — killall is the only working method
    try { app.doShellScript("killall WallpaperAgent"); } catch(_) {}
  }

  // ── Apply only if something actually changed ───────────────────────────────
  const currentID = getCurrentAssetID();
  const wallpaperChanged = currentID !== desiredID;
  if (wallpaperChanged) updatePlist(desiredID);

  const sysEvents   = Application("System Events");
  const currentDark = sysEvents.appearancePreferences.darkMode();
  const darkChanged = wantDark !== currentDark;
  if (darkChanged) sysEvents.appearancePreferences.darkMode = wantDark;

  // ── Log (only on change) ───────────────────────────────────────────────────
  if (wallpaperChanged || darkChanged) {
    const pad = n => String(n).padStart(2, '0');
    const hh  = pad(now.getHours()), mm = pad(now.getMinutes());
    const sr  = `${Math.floor(sunrise)}:${pad(Math.round((sunrise%1)*60))}`;
    const ss  = `${Math.floor(sunset)}:${pad(Math.round((sunset%1)*60))}`;
    const changes = [];
    if (wallpaperChanged) changes.push(`wallpaper→${period}`);
    if (darkChanged)      changes.push(`dark→${wantDark}`);
    return `${hh}:${mm} | ${period} | ${sr}↑ ${ss}↓ | ${changes.join(' ')}`;
  }
}
