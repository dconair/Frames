# Frames über Xcode auf iPhone, iPad und Apple TV installieren

Das geht mit einer **kostenlosen Apple-ID**, ohne bezahltes Developer-Konto. Du brauchst einen Mac mit Xcode 27 oder neuer.

Grenzen des kostenlosen Zugangs: Die App läuft nach der Installation **7 Tage** und muss dann neu aus Xcode installiert werden. Bis zu 3 selbst installierte Apps pro Gerät. Kein TestFlight.

## Einmalig vorbereiten

```sh
brew install xcodegen
git clone https://github.com/dconair/Frames.git
cd Frames
xcodegen generate
open Frames.xcodeproj
```

In Xcode: Einstellungen › Accounts › „+“ › Apple-ID hinzufügen.

## Signierung eintragen

1. Links das Projekt „Frames“ anklicken, Ziel **Frames** wählen, Reiter **Signing & Capabilities**.
2. „Automatically manage signing“ einschalten und unter **Team** die eigene Apple-ID (Personal Team) wählen.
3. Die **Bundle Identifier** `app.frames.Frames` auf etwas Eigenes ändern, zum Beispiel `app.frames.Frames.deinname`. Kostenlose Konten können eine schon vergebene Kennung nicht nutzen.

`xcodegen generate` überschreibt diese Einstellung. Nach jedem erneuten Erzeugen also noch einmal eintragen, oder dauerhaft in `project.yml` unter `PRODUCT_BUNDLE_IDENTIFIER` und `DEVELOPMENT_TEAM` setzen (nicht committen).

## iPhone und iPad

1. Gerät per Kabel anschließen, am Gerät „Diesem Computer vertrauen“ bestätigen.
2. Am Gerät: Einstellungen › Datenschutz & Sicherheit › **Entwicklermodus** einschalten (Neustart).
3. In Xcode oben das Gerät auswählen und auf ▶︎ drücken.
4. Beim ersten Start meldet iOS einen nicht vertrauenswürdigen Entwickler: Einstellungen › Allgemein › VPN & Geräteverwaltung › eigene Apple-ID › Vertrauen.

Später ohne Kabel: In Xcode unter Window › Devices and Simulators das Gerät auswählen und „Connect via network“ anhaken.

## Apple TV

1. Apple TV und Mac im selben WLAN.
2. Apple TV: Einstellungen › Fernbedienungen und Geräte › **Fernbedienung-App und Geräte** ansehen. Der Mac muss in Xcode unter Window › Devices and Simulators › „+“ das Apple TV finden. Den Code, der auf dem Fernseher erscheint, in Xcode eintragen.
3. Apple TV als Ziel wählen und ▶︎ drücken.

## Mac

Fertige App ohne Xcode: unter Releases die `.dmg` laden. Beim ersten Start in Systemeinstellungen › Datenschutz & Sicherheit auf „Dennoch öffnen“ klicken.

## Alle 7 Tage erneuern

Gerät verbinden, in Xcode erneut ▶︎ drücken. Die Daten in der App bleiben erhalten.

## Auf Dauer ohne Ablauf

Das bezahlte Apple Developer Program (99 USD/Jahr) hebt die 7-Tage-Grenze auf und ermöglicht TestFlight.
