

# Tahoe Wallpaper Switcher

Cambia automáticamente los fondos de pantalla **Tahoe Morning / Day / Evening / Night** según la posición real del sol para tu ubicación — y alterna el **modo Oscuro / Claro** en consecuencia.

Sin aplicaciones de terceros. Solo JXA (JavaScript for Automation) + python3. JXA viene preinstalado en macOS; instala Python mediante Xcode Command Line Tools u otra distribución compatible si no está disponible.

---

## Instalación

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/31c7eea079bbb46ee098b5dab2b804c77ea88684/install.sh)"
```

## Desinstalación

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/31c7eea079bbb46ee098b5dab2b804c77ea88684/uninstall.sh)"
```

---

## Requisitos

- macOS Tahoe (26+)
- Todos los fondos descargados desde **Ajustes del sistema → Fondo de pantalla**:
  `Tahoe Morning`, `Tahoe Day`, `Tahoe Evening`, `Tahoe Night`

---

## Cómo funciona

| Período | Fondo de pantalla | Modo |
|--------|-----------|------|
| Amanecer → +1.5 h | Tahoe Morning | ☀️ Claro |
| Día → 1 h antes del atardecer | Tahoe Day | ☀️ Claro |
| 1 h antes del atardecer → +0.5 h | Tahoe Evening | 🌙 Oscuro |
| Tras el atardecer | Tahoe Night | 🌙 Oscuro |

El amanecer y el atardecer se calculan diariamente con tus coordenadas: **no requiere conexión a Internet**, ni horario estático. Se adapta automáticamente a cada estación.

El fondo de pantalla se actualiza **solo cuando cambia el período o el identificador del fondo deseado**, y el modo oscuro se evalúa y actualiza de forma independiente: sin parpadeos innecesarios.

---

## Ubicación

Tus coordenadas se almacenan en un único archivo JSON:

```text
~/Library/Scripts/wallpaper-switch-config.json
```

El instalador crea este archivo con **Apple Park, Cupertino CA** como valor predeterminado. Edítalo en cualquier momento para establecer tu propia ubicación:

```json
{
  "lat": 37.3349,
  "lon": -122.0090
}
```

Encuentra tus coordenadas en [latlong.net](https://www.latlong.net).

**Referencia rápida:**

| Ciudad | lat | lon |
|------|-----|-----|
| Apple Park, Cupertino CA | 37.3349 | -122.0090 |
| Nueva York, EE. UU. | 40.7128 | -74.0060 |
| Londres, Reino Unido | 51.5074 | -0.1278 |
| París, Francia | 48.8566 | 2.3522 |
| Tokio, Japón | 35.6762 | 139.6503 |
| Sídney, Australia | -33.8688 | 151.2093 |

---

## Instalación manual

Si prefieres no ejecutar scripts remotos, sigue estos pasos en su lugar.

### 1 — Descarga los cuatro fondos Tahoe

Abre **Ajustes del sistema → Fondo de pantalla** y descarga:
`Tahoe Morning`, `Tahoe Day`, `Tahoe Evening`, `Tahoe Night`.

### 2 — Copia el script

```bash
mkdir -p ~/Library/Scripts

curl -fsSL \
  https://raw.githubusercontent.com/andmev/tahoe-wallpaper-switcher/31c7eea079bbb46ee098b5dab2b804c77ea88684/wallpaper-switch.js \
  -o ~/Library/Scripts/wallpaper-switch.js

chmod +x ~/Library/Scripts/wallpaper-switch.js
```

### 3 — Crea la configuración de ubicación

```bash
cat > ~/Library/Scripts/wallpaper-switch-config.json << 'EOF'
{
  "lat": 37.3349,
  "lon": -122.0090
}
EOF
```

Luego abre el archivo en cualquier editor de texto y reemplaza las coordenadas por las tuyas.

### 4 — Crea el LaunchAgent

Esto hace que el script se ejecute automáticamente cada 15 minutos y al iniciar sesión.

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
    <key>StandardOutputPath</key>
    <string>/tmp/wallpaper-switch.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wallpaper-switch.err</string>
</dict>
</plist>
EOF
```

### 5 — Carga y ejecuta

```bash
launchctl load ~/Library/LaunchAgents/com.user.wallpaper-switch.plist

# Ejecuta una vez inmediatamente para verificar
osascript -l JavaScript ~/Library/Scripts/wallpaper-switch.js
```

### Desinstalación manual

```bash
launchctl unload ~/Library/LaunchAgents/com.user.wallpaper-switch.plist

rm ~/Library/LaunchAgents/com.user.wallpaper-switch.plist
rm ~/Library/Scripts/wallpaper-switch.js
rm ~/Library/Scripts/wallpaper-switch-config.json
rm -f ~/Library/Scripts/wallpaper-switch-state.json
```

---

## ¿Por qué no usar el fondo dinámico estándar de macOS?

Apple distribuye `Tahoe Morning/Day/Evening/Night` como **archivos de vídeo** (`.mov`), no como un único `.heic` dinámico. No existe una API pública para cambiar fondos aéreos/de vídeo programáticamente. Este script funciona leyendo los IDs de los fondos directamente desde el manifiesto de Apple (`entries.json`) y actualizando el plist de preferencias de fondo, para luego reiniciar el agente de fondos de pantalla.

---

## Probado en

- macOS Tahoe 26.x, Apple Silicon
