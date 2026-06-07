import Foundation

/// UserDefaults-backed persistence for app settings. Value-type wrapper; each
/// property reads/writes through the injected defaults so it is testable with a
/// throwaway suite.
public struct SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let selected = "selectedPlayerIDs"
        static let volume = "lastVolume"
        static let phrases = "quickPhrases"
        static let prefixEnabled = "prefixEnabled"
        static let lastMessage = "lastMessage"
    }

    public static let defaultPhrases = [
        "Time to get ready for school!",
        "Dinner time!",
        "Come downstairs!",
        "Have a shower!",
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedPlayerIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.selected) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: Key.selected) }
    }

    public var lastVolume: Int {
        get { defaults.object(forKey: Key.volume) == nil ? 50 : defaults.integer(forKey: Key.volume) }
        nonmutating set { defaults.set(newValue, forKey: Key.volume) }
    }

    public var quickPhrases: [String] {
        get { defaults.stringArray(forKey: Key.phrases) ?? Self.defaultPhrases }
        nonmutating set { defaults.set(newValue, forKey: Key.phrases) }
    }

    public var prefixEnabled: Bool {
        get { defaults.object(forKey: Key.prefixEnabled) == nil ? true : defaults.bool(forKey: Key.prefixEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.prefixEnabled) }
    }

    public var lastMessage: String {
        get { defaults.string(forKey: Key.lastMessage) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.lastMessage) }
    }
}
