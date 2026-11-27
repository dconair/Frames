import XCTest

/// Startet Frames im Simulator und bedient die App wie ein Mensch. Alles läuft gegen die echten Server.
/// Zeilen mit „FRAMES-UI“ landen im Protokoll der CI, die Bilder im Ergebnispaket.
final class FramesUITests: XCTestCase {
    #if os(tvOS)
    private let sections = ["Home", "Filme", "Serien", "Bibliothek", "Suche", "Addons", "Einstellungen"]
    #else
    /// Untere Leiste und die Auswahl oben auf der Seite.
    private let sections = ["Home", "Suche", "Bibliothek", "Mehr", "ALLE", "FILME", "SERIEN", "EINSTELLUNGEN", "ADDONS"]
    #endif
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
        snap("00-Start")

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

    // MARK: Sortieren und Filtern

    /// Öffnet die Quellenliste mit einer festen Beispielliste, sortiert nach Bitrate, filtert auf 1080p und Webtor
    /// und spielt die erste verbliebene Quelle. Die Beispielzeilen führen alle auf ein frei verfügbares Testvideo.
    func testQuellenSortierenUndFiltern() {
        let app = XCUIApplication()
        app.launchArguments = ["-frames-gast", "-frames-beispielquellen"]
        app.launch()
        XCTAssertTrue(waitForContent(in: app, seconds: 60), "Auf Home sind keine Kataloge erschienen.")
        sleep(4)
        openFirstTitle(in: app)
        sleep(5)
        let play = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ABSPIELEN'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Auf der Detailseite fehlt „Abspielen“.")
        activate(play, in: app)

        let toggle = app.buttons["quellen-filter"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "Über der Quellenliste fehlt „Sortieren & Filtern“.")
        let state = app.staticTexts["quellen-stand"]
        sleep(3)
        snap("30-Quellen")
        print("FRAMES-UI Filter vorher: \(state.label)")
        XCTAssertTrue(state.label.contains("10 QUELLEN"), "Die Beispielliste ist nicht vollständig: \(state.label)")

        openFilters(toggle, in: app)
        sleep(2)
        snap("31-Filter-offen")
        let choices = [
            ("BITRATE", ["BESTE ZUERST", "BITRATE", "KLEINSTE", "TON", "FASSUNG"]),
            ("1080p", ["2160p", "1080p", "720p"]),
            ("WEBTOR", ["RD", "WEBTOR"]),
        ]
        for (step, (label, row)) in choices.enumerated() {
            let found = choose(label, among: row, in: app)
            XCTAssertTrue(found, "Die Auswahl „\(label)“ ließ sich nicht treffen.")
            sleep(2)
            snap("3\(step + 2)-Filter-\(label)")
            print("FRAMES-UI Filter nach \(label): \(state.label)")
        }
        XCTAssertTrue(state.label.contains("BITRATE"), "Die Sortierung steht nicht im Stand: \(state.label)")
        XCTAssertTrue(state.label.contains("2 FILTER"), "Die Filter stehen nicht im Stand: \(state.label)")
        XCTAssertTrue(state.label.contains("2 VON 10 QUELLEN"), "1080p von Webtor sind genau zwei Zeilen: \(state.label)")

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Webtor.io'")).firstMatch
        XCTAssertTrue(row.exists, "Nach dem Filtern fehlt die Webtor-Zeile.")
        print("FRAMES-UI Filter erste Zeile: \(row.label)")
        XCTAssertTrue(row.label.contains("6,4 GB"), "Mit Sortierung nach Bitrate steht die größere Datei oben: \(row.label)")
        openRow(row, in: app)

        let status = app.descendants(matching: .any)["player-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), "Der Player ist nicht erschienen.")
        var hasPicture = false
        for _ in 0..<60 where !hasPicture {
            hasPicture = status.label.contains("bild=true")
            if !hasPicture { sleep(1) }
        }
        print("FRAMES-UI Filter Player: \(status.label)")
        XCTAssertTrue(hasPicture, "Die gefilterte Quelle spielt nicht: \(status.label)")
        sleep(4)
        snap("35-Player-aus-gefilterter-Liste")
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

    // MARK: Vorschau

    /// Ein Rundgang mit dem echten Konto für die Bildschirmaufnahme: Start, Home, Filme, Detail, Quellen, Player.
    /// Läuft nur, wenn die Aufnahme ausdrücklich verlangt ist.
    func testVorschauMitKonto() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FRAMES_VORSCHAU"] == "1",
              let email = environment["FRAMES_EMAIL"], !email.isEmpty,
              let password = environment["FRAMES_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Keine Vorschau verlangt.")
        }
        let app = XCUIApplication()
        app.launchEnvironment = ["FRAMES_TEST_EMAIL": email, "FRAMES_TEST_PASSWORD": password]
        app.launch()
        XCTAssertTrue(waitForContent(in: app, seconds: 90), "Nach der Anmeldung sind keine Kataloge erschienen.")
        sleep(5)
        browse(in: app)

        XCTAssertTrue(openSection("Filme", in: app), "Der Bereich Filme ließ sich nicht öffnen.")
        sleep(5)
        openFirstTitle(in: app)
        sleep(6)

        let play = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ABSPIELEN'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Auf der Detailseite fehlt „Abspielen“.")
        activate(play, in: app)

        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'EMPFOHLEN'")).firstMatch
        let hasSource = source.waitForExistence(timeout: 40)
        print("FRAMES-UI Vorschau: Quellen gefunden=\(hasSource)")
        XCTAssertTrue(hasSource, "Für den Film kam keine abspielbare Quelle.")
        sleep(4)
        guard hasSource else { return }
        select(source, in: app)

        var picture = false
        for _ in 0..<90 where !picture {
            picture = app.activityIndicators.count == 0 && !app.staticTexts["WIEDERGABE NICHT MÖGLICH"].exists
            sleep(1)
        }
        sleep(25)
        print("FRAMES-UI Vorschau: Fehlermeldung im Player=\(app.staticTexts["WIEDERGABE NICHT MÖGLICH"].exists)")
        #if os(tvOS)
        XCUIRemote.shared.press(.right)
        sleep(6)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        sleep(8)
        XCUIRemote.shared.press(.select)
        sleep(4)
        #else
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(2)
        let forward = app.buttons.matching(NSPredicate(format: "label CONTAINS '»'")).firstMatch
        if forward.exists, forward.isHittable {
            forward.tap()
            sleep(6)
        }
        sleep(6)
        #endif
        XCTAssertFalse(app.staticTexts["WIEDERGABE NICHT MÖGLICH"].exists, "Der Player meldet einen Fehler.")
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

    // MARK: Start-Animationen und App-Symbol

    /// Startet die App einmal je Start-Animation und hält sie mit Bildschirmfotos fest. Die CI nimmt dazu ein Video auf.
    func testStartanimationen() {
        let styles = ["stapel", "filmstreifen", "auffaechern", "zeichnen", "blitz", "abtaster", "countdown", "huepfer"]
        for style in styles {
            let app = XCUIApplication()
            app.launchArguments = ["-frames-gast", "-frames-start", style]
            app.launch()
            usleep(900_000)
            snap("20-Start-\(style)-1")
            usleep(900_000)
            snap("20-Start-\(style)-2")
            sleep(2)
            print("FRAMES-UI Start-Animation \(style) gelaufen")
            app.terminate()
        }
    }

    /// Zeigt unter Einstellungen den Bereich „Start“ mit der Wahl der Animation und der App-Symbole.
    func testStartEinstellungen() {
        let app = XCUIApplication()
        app.launchArguments = ["-frames-gast"]
        app.launch()
        XCTAssertTrue(waitForContent(in: app, seconds: 60), "Home ist nicht erschienen.")
        guard openSection("Einstellungen", in: app) else {
            XCTFail("Einstellungen nicht erreicht")
            return
        }
        sleep(2)
        #if os(tvOS)
        let remote = XCUIRemote.shared
        for _ in 0..<9 {
            remote.press(.down)
            usleep(300_000)
        }
        #else
        app.swipeUp()
        app.swipeUp()
        #endif
        sleep(2)
        snap("30-Einstellungen-Start-1")
        let chip = app.buttons["BLITZ"].firstMatch
        if chip.waitForExistence(timeout: 5) {
            #if os(tvOS)
            for _ in 0..<4 where !chip.hasFocus {
                XCUIRemote.shared.press(.right)
                usleep(300_000)
            }
            XCUIRemote.shared.press(.select)
            #else
            chip.tap()
            #endif
            sleep(2)
            snap("31-Einstellungen-Start-Vorschau")
            sleep(2)
            snap("32-Einstellungen-Start-Vorschau")
        } else {
            note("Start-Einstellungen", texts(in: app))
        }
        #if !os(tvOS)
        app.swipeUp()
        sleep(1)
        snap("33-Einstellungen-Symbole")
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

    private func openFilters(_ toggle: XCUIElement, in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !toggle.hasFocus {
            remote.press(.up)
            sleep(1)
        }
        remote.press(.select)
    }

    /// Geht nach unten bis in die Zeile mit diesen Tasten und dann seitwärts genau bis zur gesuchten.
    private func choose(_ label: String, among row: [String], in app: XCUIApplication) -> Bool {
        let remote = XCUIRemote.shared
        for _ in 0..<8 where !row.contains(focusedLabel(in: app)) {
            remote.press(.down)
            sleep(1)
        }
        guard let target = row.firstIndex(of: label) else { return false }
        for _ in 0..<row.count {
            guard let current = row.firstIndex(of: focusedLabel(in: app)) else { return false }
            if current == target {
                remote.press(.select)
                return true
            }
            remote.press(current < target ? .right : .left)
            sleep(1)
        }
        return false
    }

    private func openRow(_ row: XCUIElement, in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        for _ in 0..<12 where !focusedLabel(in: app).hasPrefix("Webtor.io") {
            remote.press(.down)
            sleep(1)
        }
        print("FRAMES-UI Fokus vor dem Start: \(focusedLabel(in: app))")
        remote.press(.select)
    }

    private func select(_ element: XCUIElement, in app: XCUIApplication) {
        XCUIRemote.shared.press(.select)
    }

    private func browse(in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        for button in [XCUIRemote.Button.right, .right, .right, .down, .right, .right, .up, .left, .left, .left, .left, .left] {
            remote.press(button)
            sleep(1)
        }
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

    private func openFilters(_ toggle: XCUIElement, in app: XCUIApplication) {
        toggle.tap()
    }

    private func choose(_ label: String, among row: [String], in app: XCUIApplication) -> Bool {
        let chip = app.buttons[label].firstMatch
        guard chip.waitForExistence(timeout: 5) else { return false }
        if !chip.isHittable { app.swipeUp() }
        guard chip.isHittable else { return false }
        chip.tap()
        return true
    }

    private func openRow(_ row: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
    }

    private func select(_ element: XCUIElement, in app: XCUIApplication) {
        element.tap()
    }

    private func browse(in app: XCUIApplication) {
        app.swipeUp()
        sleep(2)
        app.swipeDown()
        sleep(2)
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
        let path: [String]
        switch name {
        case "Filme": path = ["Home", "FILME"]
        case "Serien": path = ["Home", "SERIEN"]
        case "Addons": path = ["Mehr", "ADDONS"]
        case "Einstellungen": path = ["Mehr", "EINSTELLUNGEN"]
        default: path = [name]
        }
        for step in path {
            let button = app.buttons[step].firstMatch
            guard button.waitForExistence(timeout: 5), button.isHittable else { return false }
            button.tap()
            sleep(1)
        }
        return true
    }
    #endif
}
