import Foundation

@MainActor
@Observable
public final class AppSettings {
    public var renderWidth: Int {
        didSet { UserDefaults.standard.set(renderWidth, forKey: "renderWidth") }
    }

    public var scrollDelay: Double {
        didSet { UserDefaults.standard.set(scrollDelay, forKey: "scrollDelay") }
    }

    public var savedDirectoryBookmark: Data? {
        didSet { UserDefaults.standard.set(savedDirectoryBookmark, forKey: "savedDirectoryBookmark") }
    }

    public var includesWhereFroms: Bool {
        didSet { UserDefaults.standard.set(includesWhereFroms, forKey: "includesWhereFroms") }
    }

    public var includesFinderTags: Bool {
        didSet { UserDefaults.standard.set(includesFinderTags, forKey: "includesFinderTags") }
    }

    public var includesContentDates: Bool {
        didSet { UserDefaults.standard.set(includesContentDates, forKey: "includesContentDates") }
    }

    public init() {
        let defaults = UserDefaults.standard
        self.renderWidth = defaults.object(forKey: "renderWidth") as? Int ?? 1920
        self.scrollDelay = defaults.object(forKey: "scrollDelay") as? Double ?? 150
        self.savedDirectoryBookmark = defaults.data(forKey: "savedDirectoryBookmark")
        self.includesWhereFroms = defaults.object(forKey: "includesWhereFroms") as? Bool ?? true
        self.includesFinderTags = defaults.object(forKey: "includesFinderTags") as? Bool ?? true
        self.includesContentDates = defaults.object(forKey: "includesContentDates") as? Bool ?? true
    }

    /// Default archive location: the app's sandbox container `Documents` directory.
    ///
    /// Always writable without any file-access entitlement on both macOS and iOS.
    /// Users can override this by choosing their own folder (security-scoped bookmark).
    public var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
