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
- X-Ray im Player: beim Pausieren die ersten Gesichter, über die Taste X-RAY Besetzung mit Fotos und Rollen (bei Serien mit den Gaststars der Folge) und der Soundtrack des Titels. Songs mit Albumcover. Mit verbundenem Spotify-Konto legt ein Tipp den Song in die eigene Playlist „Frames“ (oder in die Lieblingssongs), ohne Spotify zu öffnen. Ohne Verbindung öffnet er Spotify, auf dem Apple TV per QR-Code
- Wiedergabestand geht zurück ins Stremio-Konto, die Wiedergabe setzt dort fort, wo sie auf einem anderen Gerät endete

- Acht wechselnde Start-Animationen, wählbare App-Symbole und ein Top Shelf mit „Weiter ansehen“ auf dem Apple TV, siehe [docs/start-symbole-top-shelf.md](docs/start-symbole-top-shelf.md)

Als Nächstes: Intro überspringen und nächste Folge, Verteilung über TestFlight.

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

In Xcode das Ziel „Frames“ wählen, ein Gerät aussuchen (iPhone, iPad, Apple TV oder „My Mac“) und starten. Für ein echtes Gerät unter „Signing & Capabilities“ das eigene Team eintragen. Die ausführliche Anleitung mit kostenloser Apple-ID steht in [docs/auf-geraet-installieren.md](docs/auf-geraet-installieren.md).

Tests des Kerns:

```sh
swift test
```

## Prüfen

- `swift test` prüft den Kern mit festen Beispieldaten.
- `swift run frames-check` läuft gegen die echten Server: Anmeldung, Addons, Bibliothek, Kataloge, Suche, Details, Quellen und der Abruf des besten direkten Links. Mit `FRAMES_EMAIL` und `FRAMES_PASSWORD` in der Umgebung nimmt es das eigene Konto, sonst die Grundausstattung von Stremio. In der CI heißt der Lauf „Konto-Check“.
- „Simulator-Tests“ startet die App im iPhone- und im Apple-TV-Simulator, bedient sie, spielt ein Testvideo im Player und legt Bildschirmfotos als Paket am Lauf ab.

Die Zugangsdaten liegen als Secrets `FRAMES_EMAIL` und `FRAMES_PASSWORD` im Repo. In Protokollen stehen weder Links noch Titel aus dem Konto.

## X-Ray und Spotify

Besetzung kommt von [TVmaze](https://www.tvmaze.com/api) (CC BY-SA), der Soundtrack von [MusicBrainz](https://musicbrainz.org), die Cover aus dem [Cover Art Archive](https://coverartarchive.org). Mit Spotify-Verbindung zeigt jeder Song das Cover seines Originalalbums. Beide ohne Schlüssel. Wer in genau dieser Szene spielt oder welcher Song gerade läuft, gibt es als freie Quelle nicht. Das X-Ray zeigt deshalb Besetzung und Soundtrack des Titels.

Ohne Einrichtung öffnet ein Song die Suche in Spotify. Damit Songs mit einem Tipp in der Playlist „Frames“ landen, wie bei Shazam:

1. Auf [developer.spotify.com](https://developer.spotify.com/dashboard) eine App anlegen, API „Web API“. Spotify verlangt dafür ein Premium-Konto.
2. Als Redirect-URI `http://127.0.0.1:43821/spotify` eintragen.
3. Die Client-ID in Frames unter Einstellungen › X-Ray und Spotify einfügen und „Verbinden“ wählen.

Frames nimmt den Rücksprung von Spotify kurz auf 127.0.0.1 an, der Code verlässt das Gerät nicht. Ein Geheimnis braucht die App dank PKCE nicht. Auf dem Apple TV gibt es keinen Browser für die Anmeldung, dort zeigt jeder Song einen QR-Code fürs Handy.

## Hinweise

- Das Passwort geht nur an Stremio. Gespeichert wird allein der Sitzungsschlüssel.
- Die Adressen von Debrid-Addons enthalten den persönlichen Schlüssel. Frames schreibt sie nie in Logs oder Fehlermeldungen.
- Schriften: Space Grotesk und JetBrains Mono, beide unter der SIL Open Font License. Die Lizenztexte liegen neben den Schriftdateien.
- AetherEngine steht unter LGPL-3.0 mit App-Store-Ausnahme, FFmpeg und die übrigen Abhängigkeiten unter ihren eigenen Lizenzen.
- Frames ist kein offizielles Stremio-Produkt.
