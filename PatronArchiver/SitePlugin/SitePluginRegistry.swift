import Foundation

struct SitePluginRegistry: Sendable {
    struct Entry: Sendable {
        let regex: Regex<AnyRegexOutput>
        let pluginType: any SitePlugin.Type

        func makePlugin() -> any SitePlugin {
            pluginType.init()
        }
    }

    private let entries: [Entry]

    static let shared = SitePluginRegistry()

    private init() {
        let pluginTypes: [any SitePlugin.Type] = [
            PatreonPlugin.self,
            FanboxPlugin.self,
            FantiaPlugin.self,
            ItchPlugin.self,
            SubscribeStarPlugin.self,
        ]

        self.entries = pluginTypes.flatMap { pluginType in
            pluginType.matchPatterns.compactMap { pattern in
                guard let regex = Self.globToRegex(pattern) else { return nil }
                return Entry(regex: regex, pluginType: pluginType)
            }
        }
    }

    func plugin(for url: URL) -> (any SitePlugin)? {
        let urlString = url.absoluteString
        for entry in entries {
            if urlString.wholeMatch(of: entry.regex) != nil {
                return entry.makePlugin()
            }
        }
        // Fallback: match against host + path
        guard let host = url.host() else { return nil }
        let hostPath = host + url.path()
        for entry in entries {
            if hostPath.wholeMatch(of: entry.regex) != nil {
                return entry.makePlugin()
            }
        }
        return nil
    }

    var allPluginTypes: [any SitePlugin.Type] {
        let seen = NSMutableSet()
        return entries.compactMap { entry in
            let typeName = String(describing: entry.pluginType)
            if seen.contains(typeName) { return nil }
            seen.add(typeName)
            return entry.pluginType
        }
    }

    private static func globToRegex(_ glob: String) -> Regex<AnyRegexOutput>? {
        var regexPattern = ""
        var i = glob.startIndex

        while i < glob.endIndex {
            let ch = glob[i]
            switch ch {
            case "*":
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    regexPattern += ".*"
                    i = glob.index(after: next)
                    continue
                } else {
                    regexPattern += "[^/]*"
                }
            case "?":
                regexPattern += "[^/]"
            case ".":
                regexPattern += "\\."
            case "/":
                regexPattern += "/"
            default:
                if "\\^$|+[]{}()".contains(ch) {
                    regexPattern += "\\\(ch)"
                } else {
                    regexPattern += String(ch)
                }
            }
            i = glob.index(after: i)
        }

        return try? Regex(regexPattern)
    }
}
