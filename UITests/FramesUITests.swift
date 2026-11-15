import XCTest

/// Startet Frames im Simulator und bedient die App wie ein Mensch. Alles läuft gegen die echten Server.
/// Zeilen mit „FRAMES-UI“ landen im Protokoll der CI, die Bilder im Ergebnispaket.
final class FramesUITests: XCTestCase {
    private let sections = ["Home", "Filme", "Serien", "Bibliothek", "Suche", "Addons", "Einstellungen"]
    private let sampleMP4 = "https://media.w3.org/2010/05/sintel/trailer.mp4"
    private let sampleMKV = "https://test-videos.co.uk/vids/jellyfish/mkv/1080/Jellyfish_1080_10s_5MB.mkv"

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Rundgang ohne Konto

    /// Home mit den Katalogen der Standard-Addons, eine Detailseite, dann die übrigen Bereiche.
    func testRundgangOhneKonto() {
        let app = XCUIApplication()
        app.launchArguments = ["-frames-gast"]
        app.launch()

        XCTAssertTrue(waitForContent(in: app, seconds: 60), "Auf Home sind keine Kataloge erschienen.")
        sleep(5)
        snap("01-Home")
        note("Home", texts(in: app))

        openFirstTitle(in: app)
        sleep(6)
        snap("02-Detail")
        let detail = texts(in: app)
        note("Detail", detail)
        XCTAssertFalse(detail.isEmpty, "Die Detailseite ist leer.")

        let play = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ABSPIELEN'")).firstMatch
        if play.exists {
            activate(play, in: app)
            sleep(8)
            snap("03-Quellen")
            note("Quellen", texts(in: app))
            goBack(in: app)
        }
        goBack(in: app)

        for (index, name) in ["Suche", "Addons", "Einstellungen"].enumerated() {
            guard openSection(name, in: app) else {
                note(name, ["nicht erreicht"])
                continue
            }
            sleep(3)
            snap("0\(index + 4)-\(name)")
            note(name, texts(in: app))
        }
    }

    // MARK: Echtes Konto

    /// Meldet sich mit dem Konto aus den Secrets an. Es werden weder Bilder noch Titel festgehalten.
    func testAnmeldungMitKonto() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["FRAMES_EMAIL"], !email.isEmpty,
              let password = environment["FRAMES_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Keine Zugangsdaten hinterlegt.")
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["FRAMES_TEST_EMAIL": email, "FRAMES_TEST_PASSWORD": password]
        app.launch()

        let loaded = waitForContent(in: app, seconds: 90)
        let stillAtLogin = app.staticTexts["Mit Stremio anmelden"].exists
        XCTAssertFalse(stillAtLogin, "Die App steht nach der Anmeldung noch auf der Anmeldeseite.")
        XCTAssertTrue(loaded, "Nach der Anmeldung sind keine Kataloge erschienen.")
        print("FRAMES-UI Konto: angemeldet=\(!stillAtLogin) Elemente auf Home=\(app.buttons.count - sections.count)")

        if openSection("Bibliothek", in: app) {
            sleep(5)
            print("FRAMES-UI Konto: Einträge in der Bibliothek sichtbar=\(max(0, app.buttons.count - sections.count))")
        }
    }

    // MARK: Player

    /// Spielt eine frei verfügbare MKV-Datei an. Das ist der Behälter, in dem die meisten Debrid-Dateien kommen.
    func testPlayerSpieltMKV() {
        let app = XCUIApplication()
        app.launchArguments = ["-frames-gast"]
        app.launchEnvironment = ["FRAMES_TEST_VIDEO": sampleMKV]
        app.launch()

        let status = app.descendants(matching: .any)["player-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), "Der Player ist nicht erschienen.")
        var hasPicture = false
        for _ in 0..<60 where !hasPicture {
            hasPicture = status.label.contains("bild=true")
            if !hasPicture { sleep(1) }
        }
        print("FRAMES-UI MKV nach dem Start: \(status.label)")
        XCTAssertTrue(hasPicture, "Der Player zeigt kein Bild: \(status.label)")
        snap("20-Player-MKV")
    }

    /// Spielt ein frei verfügbares Video ab und prüft, dass Bild und Zeit laufen.
    func testPlayerSpieltVideo() {
        let app = XCUIApplication()
        app.launchArguments = ["-frames-gast"]
        app.launchEnvironment = ["FRAMES_TEST_VIDEO": sampleMP4]
        app.launch()

        let status = app.descendants(matching: .any)["player-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), "Der Player ist nicht erschienen.")

        var hasPicture = false
        for _ in 0..<60 where !hasPicture {
            hasPicture = status.label.contains("bild=true")
            if !hasPicture { sleep(1) }
        }
        print("FRAMES-UI Player nach dem Start: \(status.label)")
        XCTAssertTrue(hasPicture, "Der Player zeigt kein Bild: \(status.label)")
        snap("10-Player-Start")

        let before = time(in: status.label)
        sleep(6)
        let after = time(in: status.label)
        print("FRAMES-UI Player nach 6 s: \(status.label)")
        XCTAssertGreaterThan(after, before, "Die Wiedergabe läuft nicht weiter.")
        snap("11-Player-läuft")

        #if os(tvOS)
        XCUIRemote.shared.press(.right)
        sleep(3)
        print("FRAMES-UI Player nach Skip vor: \(status.label) (vorher zeit=\(after))")
        snap("12-Player-Skip")
        XCUIRemote.shared.press(.select)
        sleep(2)
        print("FRAMES-UI Player nach Pause: \(status.label)")
        snap("13-Player-Pause")
        #endif
    }

    // MARK: Hilfen

    private func time(in label: String) -> Int {
        guard let part = label.split(separator: " ").first(where: { $0.hasPrefix("zeit=") }) else { return -1 }
        return Int(part.dropFirst(5)) ?? -1
    }

    /// Wartet, bis neben der Navigation auch Kacheln da sind.
    private func waitForContent(in app: XCUIApplication, seconds: Int) -> Bool {
        for _ in 0..<seconds {
            if app.buttons.count >= sections.count + 3 { return true }
            sleep(1)
        }
        return false
    }

    private func texts(in app: XCUIApplication) -> [String] {
        let labels = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map(\.label)
        return (labels + buttons).filter { !$0.isEmpty && !sections.contains($0) }
    }

    private func note(_ title: String, _ lines: [String]) {
        print("FRAMES-UI \(title): \(lines.prefix(30).joined(separator: " | "))")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(tvOS)
    private func focusedLabel(in app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label : ""
    }

    private func openFirstTitle(in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            let label = focusedLabel(in: app)
            if !label.isEmpty, !sections.contains(label) { break }
            remote.press(.right)
            sleep(1)
        }
        print("FRAMES-UI Fokus vor dem Öffnen: \(focusedLabel(in: app))")
        remote.press(.select)
    }

    private func activate(_ element: XCUIElement, in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        for _ in 0..<6 where !element.hasFocus {
            remote.press(.down)
            sleep(1)
        }
        remote.press(.select)
    }

    private func goBack(in app: XCUIApplication) {
        XCUIRemote.shared.press(.menu)
        sleep(2)
    }

    private func openSection(_ name: String, in app: XCUIApplication) -> Bool {
        let remote = XCUIRemote.shared
        for _ in 0..<8 where !sections.contains(focusedLabel(in: app)) {
            print("FRAMES-UI Fokus auf dem Weg zur Seitenleiste: „\(focusedLabel(in: app))“")
            remote.press(.left)
            sleep(1)
        }
        print("FRAMES-UI Fokus in der Seitenleiste: „\(focusedLabel(in: app))“, gesucht \(name)")
        for _ in 0..<8 where focusedLabel(in: app) != name {
            remote.press(.down)
            sleep(1)
        }
        guard focusedLabel(in: app) == name else {
            for _ in 0..<8 where focusedLabel(in: app) != name {
                remote.press(.up)
                sleep(1)
            }
            guard focusedLabel(in: app) == name else { return false }
            remote.press(.select)
            return true
        }
        remote.press(.select)
        return true
    }
    #else
    private func openFirstTitle(in app: XCUIApplication) {
        let candidates = app.buttons.allElementsBoundByIndex.prefix(30)
        guard let card = candidates.first(where: { !sections.contains($0.label) && $0.isHittable }) else {
            XCTFail("Keine Kachel zum Antippen gefunden.")
            return
        }
        print("FRAMES-UI Tippe auf: \(card.label)")
        card.tap()
    }

    private func activate(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.isHittable { app.swipeUp() }
        element.tap()
    }

    private func goBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable {
            back.tap()
        } else {
            app.swipeRight()
        }
        sleep(2)
    }

    private func openSection(_ name: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[name].firstMatch
        guard button.waitForExistence(timeout: 5), button.isHittable else { return false }
        button.tap()
        return true
    }
    #endif
}
