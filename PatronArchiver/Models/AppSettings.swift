import Foundation

@MainActor
@Observable
class AppSettings {
    var renderWidth: Int {
        didSet { UserDefaults.standard.set(renderWidth, forKey: "renderWidth") }
    }

    var scrollDelay: Double {
        didSet { UserDefaults.standard.set(scrollDelay, forKey: "scrollDelay") }
    }

    var savedDirectoryBookmark: Data? {
        didSet { UserDefaults.standard.set(savedDirectoryBookmark, forKey: "savedDirectoryBookmark") }
    }

    var includesWhereFroms: Bool {
        didSet { UserDefaults.standard.set(includesWhereFroms, forKey: "includesWhereFroms") }
    }

    var includesFinderTags: Bool {
        didSet { UserDefaults.standard.set(includesFinderTags, forKey: "includesFinderTags") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.renderWidth = defaults.object(forKey: "renderWidth") as? Int ?? 1920
        self.scrollDelay = defaults.object(forKey: "scrollDelay") as? Double ?? 150
        self.savedDirectoryBookmark = defaults.data(forKey: "savedDirectoryBookmark")
        self.includesWhereFroms = defaults.object(forKey: "includesWhereFroms") as? Bool ?? true
        self.includesFinderTags = defaults.object(forKey: "includesFinderTags") as? Bool ?? true
    }

    var defaultSaveDirectory: URL {
        #if os(macOS)
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appending(path: "PatronArchiver", directoryHint: .isDirectory)
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }
}
