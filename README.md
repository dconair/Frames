# Frames

Ein nativer Stremio-Client für iPhone, iPad, Apple TV und Mac. Frames ist eine andere Oberfläche für dein bestehendes Stremio-Konto: anmelden, die dort installierten Addons werden geladen, fertig.

Frames spielt nur direkte Links ab, wie sie Debrid-Addons liefern. Torrents laufen auf dem Gerät nicht und werden ausgeblendet.

## Stand

Lauffähig von der Anmeldung bis zur Wiedergabe:

- Anmeldung mit dem Stremio-Konto, Sitzung im Schlüsselbund
- Addons und Bibliothek aus dem Konto laden
- Home, Filme, Serien mit Katalogreihen, „Weiter ansehen“, Bibliothek, Suche über alle Addons
- Detailseite mit Staffeln und Folgen
- Quellenliste mit Technik-Badges (Auflösung, Bild, Ton, Größe), beste Quelle zuerst
- Eigener Player auf allen Geräten: MKV und praktisch jedes andere Format, Dolby Vision, HDR10+ und Atmos über die Wege des Systems, Tonspuren, Untertitel
- Skip mit getrennt einstellbaren Intervallen für vor und zurück (5, 10, 20 Sekunden)
- Bildvorschau beim Spulen, aus den schon geladenen Daten und ohne zweite Verbindung zum Debrid-Dienst
- Wiedergabestand geht zurück ins Stremio-Konto, die Wiedergabe setzt dort fort, wo sie auf einem anderen Gerät endete

Als Nächstes: Intro überspringen und nächste Folge, App-Icon, Verteilung über TestFlight.

Den Player treibt [AetherEngine](https://github.com/superuser404notfound/AetherEngine) an (FFmpeg liest, VideoToolbox dekodiert, AVPlayer zeigt). Die Bedienung darüber ist die von Frames.

## Aufbau

| Ort | Inhalt |
| --- | --- |
| `Sources/FramesCore` | Stremio-Konto-API, Addon-Protokoll, Auswertung und Reihenfolge der Streams, Einstellungen. Ohne UI, mit Tests. |
| `Sources/FramesUI` | Das Signal-Design (Farben, Schriften, Fokus, Bewegung) und alle Screens in SwiftUI. |
| `App` | Der Einstiegspunkt der App. |
| `project.yml` | Beschreibung des Xcode-Projekts für iOS, tvOS und macOS. |

## Bauen

Voraussetzungen: Xcode 27 oder neuer, Geräte ab iOS 18, tvOS 18 oder macOS 15, und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Frames.xcodeproj
```

In Xcode das Ziel „Frames“ wählen, ein Gerät aussuchen (iPhone, iPad, Apple TV oder „My Mac“) und starten. Für ein echtes Gerät unter „Signing & Capabilities“ das eigene Team eintragen.

Tests des Kerns:

```sh
swift test
```

## Prüfen

- `swift test` prüft den Kern mit festen Beispieldaten.
- `swift run frames-check` läuft gegen die echten Server: Anmeldung, Addons, Bibliothek, Kataloge, Suche, Details, Quellen und der Abruf des besten direkten Links. Mit `FRAMES_EMAIL` und `FRAMES_PASSWORD` in der Umgebung nimmt es das eigene Konto, sonst die Grundausstattung von Stremio. In der CI heißt der Lauf „Konto-Check“.
- „Simulator-Tests“ startet die App im iPhone- und im Apple-TV-Simulator, bedient sie, spielt ein Testvideo im Player und legt Bildschirmfotos als Paket am Lauf ab.

Die Zugangsdaten liegen als Secrets `FRAMES_EMAIL` und `FRAMES_PASSWORD` im Repo. In Protokollen stehen weder Links noch Titel aus dem Konto.

## Hinweise

- Das Passwort geht nur an Stremio. Gespeichert wird allein der Sitzungsschlüssel.
- Die Adressen von Debrid-Addons enthalten den persönlichen Schlüssel. Frames schreibt sie nie in Logs oder Fehlermeldungen.
- Schriften: Space Grotesk und JetBrains Mono, beide unter der SIL Open Font License. Die Lizenztexte liegen neben den Schriftdateien.
- AetherEngine steht unter LGPL-3.0 mit App-Store-Ausnahme, FFmpeg und die übrigen Abhängigkeiten unter ihren eigenen Lizenzen.
- Frames ist kein offizielles Stremio-Produkt.
