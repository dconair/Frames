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
    public var settings: PlaybackSettings

    public let content: ContentService
    private let api: StremioAPI
    private let store: SessionStore

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
        guard let key = session?.authKey else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            async let loadedAddons = api.addonCollection(authKey: key)
            async let loadedLibrary = api.libraryItems(authKey: key)
            addons = try await loadedAddons
            library = (try? await loadedLibrary) ?? library
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

    public func saveSettings() {
        store.saveSettings(settings)
    }

    private static func describe(_ error: Error) -> String {
        if case FramesError.api(let code, _) = error, code == 2 || code == 3 {
            return "E-Mail oder Passwort stimmen nicht."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Das hat nicht geklappt."
    }
}
#endif
