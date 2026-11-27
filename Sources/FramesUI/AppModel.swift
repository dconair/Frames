#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Zustand der ganzen App: Anmeldung, Addons, Bibliothek, Einstellungen.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable {
        case launching, loggedOut, ready
    }

    public private(set) var phase: Phase = .launching
    public private(set) var session: AuthSession?
    public private(set) var addons: [InstalledAddon] = []
    public private(set) var library: [LibraryItem] = []
    public private(set) var isBusy = false
    public private(set) var lastSync: Date?
    public var errorMessage: String?
    /// Solange der Player läuft, gehört ihm der ganze Bildschirm: Seitenleiste und untere Leiste weichen.
    public var isPlayerActive = false
    public var settings: PlaybackSettings

    public let content: ContentService
    private let api: StremioAPI
    private let store: SessionStore
    /// Nur in den automatischen Tests: ohne Konto, mit Stremios Grundausstattung an Addons.
    private var isGuest = false

    public init(
        api: StremioAPI = StremioAPI(),
        content: ContentService = ContentService(),
        store: SessionStore = SessionStore()
    ) {
        self.api = api
        self.content = content
        self.store = store
        self.settings = store.loadSettings()
    }

    /// Beim Start: gespeicherte Sitzung wieder aufnehmen und Addons laden.
    public func start() async {
        guard phase == .launching else { return }
        if TestHooks.isGuest {
            isGuest = true
            phase = .ready
            await refresh()
            return
        }
        if let login = TestHooks.login {
            phase = .loggedOut
            await self.login(email: login.email, password: login.password)
            return
        }
        guard let saved = store.loadSession() else {
            phase = .loggedOut
            return
        }
        session = saved
        phase = .ready
        await refresh()
    }

    public func login(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Bitte E-Mail und Passwort eingeben."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let newSession = try await api.login(email: email, password: password)
            store.saveSession(newSession)
            session = newSession
            phase = .ready
        } catch {
            errorMessage = Self.describe(error)
            return
        }
        await refresh()
    }

    public func logout() {
        let key = session?.authKey
        store.saveSession(nil)
        session = nil
        addons = []
        library = []
        lastSync = nil
        phase = .loggedOut
        if let key {
            let api = api
            Task.detached { _ = try? await api.logout(authKey: key) }
        }
    }

    /// Lädt Addons und Bibliothek neu aus dem Stremio-Konto.
    public func refresh() async {
        let key = session?.authKey
        guard key != nil || isGuest else { return }
        isBusy = true
        defer { isBusy = false }
        let api = api
        do {
            async let loadedAddons = api.addonCollection(authKey: key)
            async let loadedLibrary = Self.loadLibrary(api, authKey: key)
            addons = try await loadedAddons
            library = await loadedLibrary ?? library
            lastSync = Date()
            errorMessage = nil
        } catch FramesError.api(let code, let message) where code == 1 {
            // Die Sitzung gilt nicht mehr, etwa nach einer Passwortänderung.
            logout()
            errorMessage = message
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Position in Sekunden, an der dieses Video zuletzt verlassen wurde.
    public func resumePosition(metaId: String, videoId: String) -> Double? {
        library.resumePosition(metaId: metaId, videoId: videoId)
    }

    /// Meldet den Wiedergabestand ans Stremio-Konto, damit „Weiter ansehen“ auf allen Geräten stimmt.
    /// Schlägt das fehl, läuft die Wiedergabe ungestört weiter. Der nächste Versuch kommt von selbst.
    public func saveProgress(_ progress: WatchProgress) async {
        guard progress.isWorthSaving, let key = session?.authKey else { return }
        guard let saved = try? await api.saveProgress(progress, authKey: key) else { return }
        if let index = library.firstIndex(where: { $0.id == saved.id }) {
            library[index] = saved
        } else {
            library.append(saved)
        }
    }

    /// Installiert ein Addon über seine Adresse im Stremio-Konto. Gibt den Namen zurück, wenn es geklappt hat.
    /// Die Adresse selbst taucht in keiner Meldung auf: sie trägt oft einen persönlichen Schlüssel.
    public func installAddon(address: String) async -> Result<String, AddonInstallFailure> {
        guard let url = AddonAddress.normalize(address) else {
            return .failure(.init("Das ist keine Addon-Adresse. Sie beginnt mit https:// und endet auf /manifest.json."))
        }
        guard let key = session?.authKey else {
            return .failure(.init("Melde dich erst mit deinem Stremio-Konto an."))
        }
        isBusy = true
        let api = api
        let result: Result<String, AddonInstallFailure>
        do {
            let manifest = try await api.installAddon(at: url, authKey: key)
            result = .success(manifest.name)
        } catch FramesError.http(let status) where status == 401 || status == 403 || status == 404 {
            result = .failure(.init("Unter dieser Adresse antwortet kein Addon. Ist sie vollständig und noch gültig?"))
        } catch FramesError.decoding {
            result = .failure(.init("Unter dieser Adresse liegt kein Stremio-Addon."))
        } catch {
            result = .failure(.init(Self.describe(error)))
        }
        isBusy = false
        if case .success = result { await refresh() }
        return result
    }

    public func saveSettings() {
        // Der Test mit der Beispielliste soll keine Filter hinterlassen, die spätere Läufe einengen.
        guard TestHooks.sampleStreams == nil else { return }
        store.saveSettings(settings)
    }

    private nonisolated static func loadLibrary(_ api: StremioAPI, authKey: String?) async -> [LibraryItem]? {
        guard let authKey else { return nil }
        return try? await api.libraryItems(authKey: authKey)
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? FramesError, error.requiresPasswordReset {
            return "Stremio verlangt ein neues Passwort. Setze es auf stremio.com zurück und melde dich dann neu an."
        }
        if case FramesError.api(let code, _) = error, code == 2 || code == 3 {
            return "E-Mail oder Passwort stimmen nicht."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Das hat nicht geklappt."
    }
}

public struct AddonInstallFailure: Error, Equatable {
    public let message: String
    init(_ message: String) { self.message = message }
}
#endif
