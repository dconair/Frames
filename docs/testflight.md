# Frames über TestFlight verteilen

Der Workflow `TestFlight` baut Frames für iPhone/iPad und Apple TV auf einem Mac-Runner bei GitHub, signiert die App automatisch und lädt sie zu TestFlight hoch. Du brauchst dafür keinen eigenen Mac.

## Was du brauchst

1. **Apple Developer Program** (99 USD pro Jahr): https://developer.apple.com/programs/ — ohne diese Mitgliedschaft gibt es kein TestFlight.
2. **App in App Store Connect anlegen** (https://appstoreconnect.apple.com › Apps › „+“ › Neue App):
   - Plattformen: iOS und tvOS
   - Name: Frames, Bundle-ID: `app.frames.Frames` (vorher unter Developer › Identifiers registrieren, falls sie nicht in der Liste auftaucht)
3. **API-Schlüssel**: App Store Connect › Benutzer und Zugriff › Integrationen › App Store Connect API › „+“.
   - Zugriff: **Admin** (nötig, damit Zertifikate automatisch angelegt werden dürfen)
   - Die `.p8`-Datei lässt sich nur **einmal** laden, gut aufbewahren.
   - Oben auf der Seite stehen die **Issuer-ID**, in der Liste die **Key-ID**.
4. **Team-ID**: https://developer.apple.com/account › Mitgliedschaftsdetails.

## Secrets im Repo anlegen

GitHub › dconair/Frames › Settings › Secrets and variables › Actions › „New repository secret":

| Name | Inhalt |
| --- | --- |
| `ASC_KEY_ID` | Key-ID des API-Schlüssels |
| `ASC_ISSUER_ID` | Issuer-ID |
| `ASC_KEY_P8` | Inhalt der `.p8`-Datei **base64-kodiert** (macOS/Linux: `base64 -i AuthKey_XXXX.p8`, Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`) |
| `APPLE_TEAM_ID` | Team-ID (10 Zeichen) |

## Hochladen

- **Von Hand:** Actions › TestFlight › Run workflow, Version eintragen (oder leer lassen).
- **Per Tag:** `git tag v0.2.0 && git push origin v0.2.0`.

Die Build-Nummer ist die Nummer des Workflow-Laufs und steigt damit automatisch. Nach 5 bis 30 Minuten Verarbeitung durch Apple erscheint der Build in App Store Connect › TestFlight. Dort dich selbst als internen Tester eintragen (bis 100 Personen ohne Prüfung), dann die TestFlight-App auf iPhone oder Apple TV öffnen.

## Hinweise

- Beim allerersten Build muss in App Store Connect einmalig die Frage zur Verschlüsselung beantwortet werden (Frames nutzt nur Standard-HTTPS). Mit dem Schlüssel `ITSAppUsesNonExemptEncryption = NO` in `project.yml` entfällt sie später.
- Der Mac-Build läuft weiter über den Workflow `Release` als unsignierte DMG.
- Externe Tester brauchen eine kurze Prüfung durch Apple (Beta App Review).
- Frames spielt Inhalte über Stremio-Addons ab. Für eine Veröffentlichung im App Store gelten Apples Regeln; TestFlight für den Eigengebrauch ist davon unberührt.
