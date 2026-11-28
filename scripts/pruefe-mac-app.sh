#!/bin/bash
# Prüft eine gebaute Mac-App: Liegen alle Frameworks, die sie beim Start sucht, im Paket? Steckt das Icon drin?
# Aufruf: scripts/pruefe-mac-app.sh pfad/zu/Frames.app [--signatur]
# Mit --signatur wird zusätzlich die (Ad-hoc-)Signatur geprüft, nur sinnvoll bei signierten Builds.
set -u
APP="${1:?Pfad zur .app fehlt}"
SIGNATUR="${2:-}"
BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"
fehler=0

[ -x "$BIN" ] || { echo "FEHLER: Programmdatei fehlt: $BIN"; exit 1; }

# Suchpfade (rpath) der Programmdatei, aufgelöst gegen den Ort der Programmdatei
rpaths=()
while IFS= read -r p; do
  p="${p//@executable_path/$(dirname "$BIN")}"
  p="${p//@loader_path/$(dirname "$BIN")}"
  rpaths+=("$p")
done < <(otool -l "$BIN" | awk '/cmd LC_RPATH/{f=1} f && /path /{print $2; f=0}')
echo "Suchpfade: ${rpaths[*]:-keine}"

# Jede @rpath-Bibliothek muss in einem dieser Pfade liegen
while IFS= read -r lib; do
  rel="${lib#@rpath/}"
  gefunden=0
  for r in "${rpaths[@]:-}"; do
    [ -e "$r/$rel" ] && gefunden=1 && break
  done
  if [ $gefunden -eq 1 ]; then echo "ok      $rel"; else echo "FEHLER: $rel wird beim Start gesucht, liegt aber in keinem Suchpfad"; fehler=1; fi
done < <(otool -L "$BIN" | awk '/@rpath\//{print $1}')

echo "--- Inhalt von Contents/Frameworks:"
ls "$APP/Contents/Frameworks" 2>/dev/null || { echo "FEHLER: Contents/Frameworks fehlt"; fehler=1; }

# Icon
if [ -e "$APP/Contents/Resources/Assets.car" ] && /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  echo "ok      App-Icon (Assets.car, CFBundleIconName)"
elif ls "$APP/Contents/Resources/"*.icns >/dev/null 2>&1; then
  echo "ok      App-Icon (.icns)"
else
  echo "FEHLER: App-Icon fehlt im Paket"; fehler=1
fi

# Signatur
if [ "$SIGNATUR" = "--signatur" ]; then
  codesign --verify --deep --strict "$APP" 2>&1 && echo "ok      Signatur stimmig" || { echo "FEHLER: Signatur ungültig"; fehler=1; }
fi

exit $fehler
