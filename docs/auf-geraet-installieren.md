# Frames auf iPhone, iPad und Apple TV installieren

Alles hier geht mit einer **kostenlosen Apple-ID**, ohne das bezahlte Developer-Konto.

## Kurz gesagt

| Gerät | Datei aus dem [Release](https://github.com/dconair/Frames/releases/latest) | Einfachster Weg |
| --- | --- | --- |
| iPhone und iPad | `Frames-iOS-<Version>-unsigniert.ipa` | Windows-PC oder Mac mit **Sideloadly** |
| Apple TV | `Frames-tvOS-<Version>-unsigniert.ipa` | nur verlässlich vom **Mac** (Sideloadly oder Xcode) |
| Mac | `Frames-<Version>.dmg` | Doppelklick, siehe unten |

Grenzen der kostenlosen Apple-ID:

- Die App läuft nach dem Aufspielen **7 Tage**, dann startet sie nicht mehr. Erneut aufspielen, die Daten in der App bleiben.
- Höchstens **3 selbst aufgespielte Apps** pro Gerät gleichzeitig.
- Kein TestFlight, kein App Store.

## Einmalig vorbereiten

1. **Apple-ID:** Deine normale Apple-ID geht. Wer sie nicht in ein fremdes Programm eintippen möchte, legt unter [account.apple.com](https://account.apple.com) eine zweite, kostenlose an.
2. **Nur Windows:** iTunes und iCloud **von apple.com** installieren, nicht aus dem Microsoft Store. Sideloadly und AltStore brauchen die Apple-Treiber aus diesen Versionen.
3. **Am iPhone oder iPad:** Einstellungen › Datenschutz & Sicherheit › **Entwicklermodus** einschalten. Der Schalter erscheint erst, nachdem das Gerät einmal mit Sideloadly, AltStore oder Xcode verbunden war. Das Gerät startet dabei neu.

## iPhone und iPad mit Sideloadly (Windows oder Mac)

1. [Sideloadly](https://sideloadly.io) installieren und öffnen.
2. Aus dem [Release](https://github.com/dconair/Frames/releases/latest) die Datei `Frames-iOS-…-unsigniert.ipa` laden. Dieselbe Datei gilt für iPhone und iPad.
3. iPhone per Kabel anschließen und am iPhone „Diesem Computer vertrauen“ bestätigen.
4. In Sideloadly die IPA-Datei ins Fenster ziehen, oben das iPhone wählen, die Apple-ID eintragen und auf **Start** klicken. Beim ersten Mal fragt Sideloadly nach dem Passwort und eventuell nach dem Bestätigungscode von Apple.
5. Am iPhone: Einstellungen › Allgemein › **VPN & Geräteverwaltung** › deine Apple-ID › **Vertrauen**.
6. Frames öffnen.

Meldet Sideloadly, die Kennung sei schon vergeben: unter „Advanced Options“ eine eigene Bundle-ID eintragen, zum Beispiel `app.frames.Frames.deinname`, und noch einmal starten.

## Alle 7 Tage erneuern

Drei Möglichkeiten, von einfach bis bequem:

- **Von Hand mit Sideloadly:** iPhone anschließen, dieselbe IPA noch einmal aufspielen. Dauert etwa eine Minute. Wenn du sowieso eine neue Version aus dem Release nimmst, ist das gleich das Update.
- **AltStore Classic (automatisch, PC muss laufen):** [AltStore](https://altstore.io) mit AltServer auf dem PC oder Mac einrichten und die Frames-IPA in AltStore öffnen. Solange der Rechner an ist und im selben WLAN steht, erneuert AltStore die App im Hintergrund.
- **SideStore (automatisch, ganz ohne PC):** [SideStore](https://sidestore.io) erneuert direkt auf dem iPhone über ein lokales VPN. Die Einrichtung braucht einmal einen Rechner und ist etwas fummeliger, danach läuft es ohne. Gut, wenn der PC selten an ist.

## Apple TV

Mit einer kostenlosen Apple-ID geht das Apple TV nur verlässlich von einem **Mac**. Sideloadly sagt selbst, dass es Apple TV bisher nur am Mac getestet hat und ein Apple TV 4K unter Windows nicht koppeln kann. Automatisches Erneuern gibt es fürs Apple TV kostenlos nicht, also alle 7 Tage von Hand.

### Koppeln (einmal)

1. Apple TV und Mac ins selbe WLAN.
2. Am Mac Xcode starten (kostenlos im Mac App Store), dann Window › Devices and Simulators.
3. Am Apple TV: Einstellungen › Fernbedienungen und Geräte › **Fernbedienung-App und Geräte** öffnen und offen lassen.
4. In Xcode erscheint das Apple TV, auf „Pair“ klicken und den Code vom Fernseher eintippen.

### Aufspielen

- **Mit Sideloadly am Mac:** `Frames-tvOS-…-unsigniert.ipa` aus dem Release ins Fenster ziehen, das Apple TV wählen, Apple-ID eintragen, Start.
- **Mit Xcode:** siehe unten „Aus dem Quellcode“. Das klappt sicher, braucht aber ein paar Schritte mehr.

## Mac

`Frames-<Version>.dmg` aus dem Release laden, öffnen und Frames in den Ordner „Programme“ ziehen. Beim ersten Start meldet macOS, dass die App nicht geprüft ist: Systemeinstellungen › Datenschutz & Sicherheit › **Dennoch öffnen**. Das ist nur einmal nötig. Die Mac-App läuft ohne 7-Tage-Grenze.

## Aus dem Quellcode mit Xcode (Mac)

```sh
brew install xcodegen
git clone https://github.com/dconair/Frames.git
cd Frames
xcodegen generate
open Frames.xcodeproj
```

1. In Xcode: Einstellungen › Accounts › „+“ › Apple-ID hinzufügen.
2. Projekt „Frames“ anklicken, Ziel **Frames**, Reiter **Signing & Capabilities**, „Automatically manage signing“ an, unter **Team** die eigene Apple-ID (Personal Team) wählen.
3. **Bundle Identifier** auf etwas Eigenes ändern, zum Beispiel `app.frames.Frames.deinname`. Kostenlose Konten können keine schon vergebene Kennung nutzen. Für das Apple TV dasselbe beim Ziel **FramesTopShelf** (`app.frames.Frames.deinname.TopShelf`).
4. Oben das Gerät wählen (iPhone, iPad oder das gekoppelte Apple TV) und ▶︎ drücken.

`xcodegen generate` setzt diese Einstellungen zurück. Nach jedem neuen Erzeugen also noch einmal eintragen, oder in `project.yml` unter `PRODUCT_BUNDLE_IDENTIFIER` und `DEVELOPMENT_TEAM` setzen und nicht committen.

## Ohne 7-Tage-Grenze

Das bezahlte Apple Developer Program (99 € im Jahr) hebt die Grenze auf, Apps laufen dann ein Jahr und lassen sich über TestFlight verteilen. Für Frames ist das nicht nötig.
