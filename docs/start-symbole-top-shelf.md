# Start-Animationen, App-Symbole und Top Shelf

## Start-Animationen

Es gibt acht: Stapel, Filmstreifen, Auffächern, Zeichnen, Blitz, Abtaster, Countdown und Hüpfer. Alle enden beim Logo „Einzelbilder“ mit der Wortmarke.

Unter Einstellungen › Start wählt man **Wechselnd** (jeder Start nimmt eine andere, nie dieselbe wie zuvor) oder eine feste. Ein Tipp auf einen Namen spielt die Animation direkt in der Einstellung ab.

Für Tests lässt sich eine erzwingen: `-frames-start blitz` als Startargument (nur in Debug-Builds).

## App-Symbole

Sieben zur Auswahl: Einzelbilder (Standard), Einzelbilder Limette, Schrägstrich, Sucher, Balken-F, Zeitleiste, Kontaktbogen. Sie entstehen aus `scripts/erzeuge-symbole.py` (`python3 scripts/erzeuge-symbole.py`, braucht Pillow).

| Gerät | Verhalten |
| --- | --- |
| iPhone, iPad | Echte alternative Symbole. Das System fragt beim Wechsel kurz nach, das lässt sich nicht abschalten. |
| Mac | macOS kennt keine alternativen Symbole. Frames setzt das Dock-Symbol beim Start selbst, es gilt nur, solange die App läuft. Im Finder bleibt das Standardsymbol. |
| Apple TV | Kein Wechsel möglich. tvOS hat keine Schnittstelle dafür. Das feste Symbol besteht aus drei Schichtbildern (die drei Einzelbilder), sodass es beim Fokussieren gegeneinander wandert. |

## Top Shelf auf dem Apple TV

Liegt Frames in der obersten Reihe, zeigt der Home-Bildschirm darüber „Weiter ansehen“: ein Karussell mit breiten Bildern, Titel, Folge und Fortschritt. Ein Tipp öffnet die Detailseite des Titels. Fehlt zu einem Titel das breite Bild, zeigt die Erweiterung stattdessen eine Reihe Poster.

So kommen die Daten dorthin: Die App schreibt nach jedem Abgleich mit dem Stremio-Konto die acht zuletzt angefangenen Titel nach `topshelf.json` in einen gemeinsamen Ordner (App Group `group.app.frames.Frames`). Die Erweiterung `FramesTopShelf` liest die Datei. Ohne Daten bleibt das feste Top-Shelf-Bild.

### Grenze beim kostenlosen Apple-Konto

Der gemeinsame Ordner ist eine Fähigkeit (App Groups), die nur das bezahlte Developer Program freischaltet. Deshalb gilt:

- **Simulator:** funktioniert. Die Berechtigung ist in `project.yml` für den Apple-TV-Simulator eingetragen.
- **Apple TV mit kostenlosem Konto:** Die App läuft, die Erweiterung wird mitinstalliert, kann aber die Daten der App nicht lesen und zeigt nur das feste Bild. Die Berechtigung steht dort bewusst nicht in den Einstellungen, sonst ließe sich die App mit dem kostenlosen Konto gar nicht mehr signieren.
- **Mit bezahltem Konto:** In `project.yml` die beiden Zeilen `"CODE_SIGN_ENTITLEMENTS[sdk=appletvsimulator*]"` zu `CODE_SIGN_ENTITLEMENTS` ohne Bedingung machen (Frames und FramesTopShelf), `xcodegen generate`, in Xcode die App Group `group.app.frames.Frames` für beide Ziele anlegen. Dann läuft es auch auf dem Gerät.
