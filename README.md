# Frames

Ein nativer Stremio-Client für iPhone, iPad, Apple TV und Mac. Frames ist eine andere Oberfläche für dein bestehendes Stremio-Konto: anmelden, die dort installierten Addons werden geladen, fertig.

Frames spielt nur direkte Links ab, wie sie Debrid-Addons liefern. Torrents laufen auf dem Gerät nicht und werden ausgeblendet.

## Stand

Erster Abschnitt, lauffähig von der Anmeldung bis zur Wiedergabe:

- Anmeldung mit dem Stremio-Konto, Sitzung im Schlüsselbund
- Addons und Bibliothek aus dem Konto laden
- Home, Filme, Serien mit Katalogreihen, „Weiter ansehen“, Bibliothek, Suche über alle Addons
- Detailseite mit Staffeln und Folgen
- Quellenliste mit Technik-Badges (Auflösung, Bild, Ton, Größe), beste Quelle zuerst
- Einstellungen mit getrennten Skip-Intervallen für vor und zurück (5, 10, 20 Sekunden)
- Player auf Basis des Systemplayers

Als Nächstes: eigener Player auf libmpv (MKV, Dolby Vision, Tonspuren, Untertitel) mit Bildvorschau beim Spulen und Skip-Tasten auch auf dem Apple TV, Wiedergabestand zurück ins Konto schreiben, App-Icon.

## Aufbau

| Ort | Inhalt |
| --- | --- |
| `Sources/FramesCore` | Stremio-Konto-API, Addon-Protokoll, Auswertung und Reihenfolge der Streams, Einstellungen. Ohne UI, mit Tests. |
| `Sources/FramesUI` | Das Signal-Design (Farben, Schriften, Fokus, Bewegung) und alle Screens in SwiftUI. |
| `App` | Der Einstiegspunkt der App. |
| `project.yml` | Beschreibung des Xcode-Projekts für iOS, tvOS und macOS. |

## Bauen

Voraussetzungen: Xcode 16 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Frames.xcodeproj
```

In Xcode das Ziel „Frames“ wählen, ein Gerät aussuchen (iPhone, iPad, Apple TV oder „My Mac“) und starten. Für ein echtes Gerät unter „Signing & Capabilities“ das eigene Team eintragen.

Tests des Kerns:

```sh
swift test
```

## Hinweise

- Das Passwort geht nur an Stremio. Gespeichert wird allein der Sitzungsschlüssel.
- Die Adressen von Debrid-Addons enthalten den persönlichen Schlüssel. Frames schreibt sie nie in Logs oder Fehlermeldungen.
- Schriften: Space Grotesk und JetBrains Mono, beide unter der SIL Open Font License. Die Lizenztexte liegen neben den Schriftdateien.
- Frames ist kein offizielles Stremio-Produkt.
