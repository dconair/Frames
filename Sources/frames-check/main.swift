import Foundation
import FramesCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Prüft die Stremio-Anbindung gegen die echten Server, ohne die App zu starten.
//
//   swift run frames-check
//       ohne Konto: Grundausstattung an Addons, Kataloge, Details, Streams
//
//   FRAMES_EMAIL=… FRAMES_PASSWORD=… swift run frames-check [tt-id]
//       mit deinem Konto: deine Addons, deine Bibliothek, Streams über dein Debrid-Addon
//       und ein Abruf des besten Links, wie ihn der Player macht
//
// Adressen von Addons und Streams werden nie ausgegeben, weil sie persönliche Schlüssel enthalten können.
// Mit Konto bleiben auch die Namen deiner Addons und Titel aus der Ausgabe, damit das Protokoll
// eines Laufs auf GitHub nichts über dich verrät. FRAMES_VERBOSE=1 zeigt sie, etwa am eigenen Rechner.

var failures = 0

func step(_ title: String) { print("\n== \(title)") }
func ok(_ text: String) { print("  ok    \(text)") }
func note(_ text: String) { print("        \(text)") }
func fail(_ text: String) {
    failures += 1
    print("  FEHLER \(text)")
}

let environment = ProcessInfo.processInfo.environment
let hasAccount = !(environment["FRAMES_EMAIL"] ?? "").isEmpty && !(environment["FRAMES_PASSWORD"] ?? "").isEmpty
/// Namen von Addons und Titeln nur zeigen, wenn sie nichts über ein Konto verraten oder ausdrücklich gewünscht sind.
let showNames = !hasAccount || environment["FRAMES_VERBOSE"] == "1"
var addonAliases: [String: String] = [:]
func alias(_ name: String) -> String {
    if showNames { return name }
    if let known = addonAliases[name] { return known }
    let made = "Addon \(addonAliases.count + 1)"
    addonAliases[name] = made
    return made
}
let http = URLSessionTransport()
let api = StremioAPI(http: http)
let content = ContentService(client: AddonClient(http: http))
let arguments = Array(CommandLine.arguments.dropFirst())

// MARK: Konto

var authKey: String?
step("Konto")
if hasAccount, let email = environment["FRAMES_EMAIL"], let password = environment["FRAMES_PASSWORD"] {
    do {
        let session = try await api.login(email: email, password: password)
        authKey = session.authKey
        ok("Anmeldung angenommen, Sitzungsschlüssel erhalten")
    } catch {
        fail("Anmeldung: \(error.localizedDescription)")
    }
} else {
    note("Kein Konto angegeben (FRAMES_EMAIL, FRAMES_PASSWORD). Geprüft wird die Grundausstattung.")
    do {
        _ = try await api.login(email: "niemand@frames-check.invalid", password: "falsch")
        fail("Eine falsche Anmeldung wurde angenommen")
    } catch FramesError.api(_, let message) {
        ok("Falsche Anmeldung wird sauber abgelehnt (\(message))")
    } catch {
        fail("Falsche Anmeldung: unerwartete Antwort \(error)")
    }
}

// MARK: Addons

step("Addons")
var addons: [InstalledAddon] = []
do {
    addons = try await api.addonCollection(authKey: authKey)
    ok("\(addons.count) Addons geladen, \(addons.reachable.count) davon ansprechbar")
    for addon in addons {
        let reach = addon.isReachable ? "" : "  (nicht ansprechbar)"
        note("\(alias(addon.manifest.name)): \(addon.capabilities.joined(separator: ", "))\(reach)")
    }
} catch {
    fail("Addons laden: \(error.localizedDescription)")
}

// MARK: Bibliothek

if let authKey {
    step("Bibliothek")
    do {
        let items = try await api.libraryItems(authKey: authKey)
        ok("\(items.library.count) Titel in der Bibliothek, \(items.continueWatching.count) unter „Weiter ansehen“")
        if showNames {
            for item in items.continueWatching.prefix(3) {
                note("\(item.name): \(Int((item.progress ?? 0) * 100)) %")
            }
        }
    } catch {
        fail("Bibliothek laden: \(error.localizedDescription)")
    }
}

// MARK: Kataloge

step("Kataloge")
let catalogs = addons.homeCatalogs()
if catalogs.isEmpty { fail("Kein Addon liefert einen Katalog für den Home-Screen") }
var sample: Meta?
var loaded = 0
for ref in catalogs.prefix(6) {
    do {
        let page = try await content.catalog(ref)
        loaded += 1
        ok("\(alias(ref.addon.manifest.name)) / \(showNames ? ref.title : "Katalog \(loaded)") (\(ref.type)): \(page.metas.count) Titel")
        // Ohne Konto am liebsten ein Titel aus einem Addon, das selbst Streams liefert,
        // damit auch der Weg bis zum Abruf des Links geprüft wird.
        let candidate = page.metas.first { $0.type == "movie" && $0.id.hasPrefix("tt") }
        if let candidate, sample == nil || (authKey == nil && ref.addon.capabilities.contains("stream")) {
            sample = candidate
        }
    } catch {
        fail("\(alias(ref.addon.manifest.name)) / \(showNames ? ref.title : "ein Katalog"): \(error.localizedDescription)")
    }
}
if catalogs.count > 6 { note("\(catalogs.count - 6) weitere Kataloge nicht einzeln geprüft") }

// MARK: Suche

step("Suche")
let hits = await content.search("matrix", addons: addons)
if hits.isEmpty {
    fail("Die Suche nach „matrix“ liefert nichts")
} else {
    ok("„matrix“: \(hits.map { "\($0.1.count) Treffer" }.joined(separator: ", ")) aus \(hits.count) Katalogen")
}

// MARK: Details

step("Details")
let wantedId = arguments.first
let type = wantedId?.contains(":") == true ? "series" : (sample?.type ?? "movie")
let metaId = wantedId.map { String($0.split(separator: ":").first ?? "") } ?? sample?.id ?? "tt0133093"
var streamId = wantedId ?? metaId
do {
    let meta = try await content.meta(type: type, id: metaId, addons: addons)
    ok("\(meta.name) (\(meta.releaseInfo ?? "ohne Jahr")), \(meta.videos.count) Folgen")
    if wantedId == nil { streamId = meta.streamId() }
} catch {
    fail("Details zu \(metaId): \(error.localizedDescription)")
}

do {
    let series = try await content.meta(type: "series", id: "tt0903747", addons: addons)
    if series.isSeries, let season = series.seasons.first, let episode = series.episodes(inSeason: season).first {
        ok("Serie \(series.name): \(series.seasons.count) Staffeln, erste Folge \(episode.code ?? "?") „\(episode.title)“")
    } else {
        fail("Serie \(series.name) kommt ohne Staffeln an")
    }
} catch {
    fail("Details zur Serie tt0903747: \(error.localizedDescription)")
}

// MARK: Streams

step("Streams für \(streamId)")
let providers = addons.providing("stream", type: type, id: streamId)
note("Gefragt werden: \(providers.map { alias($0.manifest.name) }.joined(separator: ", "))")
let streams = await content.streams(type: type, id: streamId, addons: addons)
let ranked = StreamRanker.ranked(streams)
var kinds: [String: Int] = [:]
for item in streams {
    let kind: String
    switch item.stream.kind {
    case .direct: kind = "direkter Link"
    case .torrent: kind = "Torrent"
    case .youtube: kind = "YouTube"
    case .external: kind = "externe Seite"
    case .unknown: kind = "unbekannt"
    }
    kinds[kind, default: 0] += 1
}
if streams.isEmpty {
    note("Keine Streams. Ohne Debrid-Addon ist das für die meisten Titel der Normalfall.")
} else {
    ok("\(streams.count) Streams: " + kinds.sorted { $0.key < $1.key }.map { "\($0.value) × \($0.key)" }.joined(separator: ", "))
}
for item in ranked.prefix(5) {
    let info = item.info
    let badges = [info.resolution?.label, info.dynamicRange?.label, info.audioLabel, info.sizeLabel, info.isCached == false ? "lädt erst" : nil]
        .compactMap { $0 }.joined(separator: " · ")
    note("\(alias(item.addonName)): \(badges.isEmpty ? "ohne Technik-Angaben" : badges)")
}

// MARK: Abruf wie im Player

if let best = ranked.first, let url = best.stream.playableURL {
    step("Abruf des besten Links")
    var request = URLRequest(url: url)
    request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
    for (name, value) in best.stream.requestHeaders { request.setValue(value, forHTTPHeaderField: name) }
    request.timeoutInterval = 30
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let reply = response as? HTTPURLResponse
        let status = reply?.statusCode ?? 0
        let kind = reply?.value(forHTTPHeaderField: "Content-Type") ?? "ohne Typ"
        if status == 206 {
            ok("Der Server liefert Teilstücke (206), \(data.count) Bytes, \(kind). Spulen funktioniert damit.")
        } else if status == 200 {
            ok("Der Server liefert die Datei (200), \(kind). Teilabrufe bestätigt er nicht, Spulen kann langsamer sein.")
        } else {
            fail("Der Link antwortet mit \(status)")
        }
        if data.count >= 4, data.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) {
            note("Die Datei ist Matroska (MKV).")
        }
        // Debrid-Addons liefern bei abgelaufener Anmeldung oder gesperrter Adresse statt des Films
        // ein kurzes Hinweisvideo. Das erkennt man nur an der Größe.
        let total = reply?.value(forHTTPHeaderField: "Content-Range")
            .flatMap { $0.split(separator: "/").last }
            .flatMap { Int64($0) }
        if let total, let expected = best.info.sizeBytes, expected > 200_000_000, total < expected / 20 {
            fail("Die Datei hat nur \(total / 1_048_576) MB statt der angekündigten \(best.info.sizeLabel ?? "?"). "
                + "Das ist ein Hinweisvideo des Addons, nicht der Film. Meist ist die Debrid-Anmeldung im Addon abgelaufen.")
        } else if let total {
            ok("Größe der Datei: \(total / 1_048_576) MB")
        }
    } catch {
        fail("Abruf: \(error.localizedDescription)")
    }
} else if authKey != nil {
    step("Abruf des besten Links")
    fail("Kein direkter Link für \(streamId). Liefert dein Debrid-Addon für diesen Titel Streams?")
}

print(failures == 0 ? "\nAlles in Ordnung." : "\n\(failures) Fehler.")
exit(failures == 0 ? 0 : 1)
