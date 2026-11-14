import Foundation

// Addons liefern Felder mal als Text, mal als Zahl, mal als Liste, mal gar nicht.
// Diese Helfer lesen tolerant, damit ein schiefes Feld nicht den ganzen Titel kostet.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Element einer Liste, das beim Lesen scheitern darf, ohne die Liste mitzureißen.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func string(_ key: String) -> String? {
        let key = AnyKey(key)
        if let value = try? decode(String.self, forKey: key) { return value.isEmpty ? nil : value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func int(_ key: String) -> Int? {
        let key = AnyKey(key)
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        let key = AnyKey(key)
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        try? decode(Bool.self, forKey: AnyKey(key))
    }

    /// Liest eine Liste von Texten, auch wenn nur ein einzelner Text geliefert wird.
    func strings(_ key: String) -> [String] {
        let key = AnyKey(key)
        if let list = try? decode([Lossy<String>].self, forKey: key) { return list.compactMap(\.value) }
        if let single = try? decode(String.self, forKey: key), !single.isEmpty { return [single] }
        return []
    }

    func list<T: Decodable>(_ key: String, of type: T.Type = T.self) -> [T] {
        guard let list = try? decode([Lossy<T>].self, forKey: AnyKey(key)) else { return [] }
        return list.compactMap(\.value)
    }

    func value<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        try? decode(T.self, forKey: AnyKey(key))
    }

    func date(_ key: String) -> Date? {
        guard let text = string(key) else { return nil }
        return StremioDate.parse(text)
    }
}

enum StremioDate {
    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
