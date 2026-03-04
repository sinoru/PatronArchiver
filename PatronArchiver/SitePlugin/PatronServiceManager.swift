import Foundation

struct PatronServiceManager: Sendable {
    struct Entry: Sendable {
        let regex: Regex<AnyRegexOutput>
        let pluginType: any PatronServiceProvider.Type

        func makeProvider() -> any PatronServiceProvider {
            pluginType.init()
        }
    }

    private let entries: [Entry]

    static let shared = PatronServiceManager()

    private init() {
        let providerTypes: [any PatronServiceProvider.Type] = [
            PatreonProvider.self,
            FanboxProvider.self,
            FantiaProvider.self,
            ItchProvider.self,
            SubscribeStarProvider.self,
        ]

        self.entries = providerTypes.flatMap { providerType in
            providerType.matchPatterns.compactMap { pattern in
                guard let regex = Self.globToRegex(pattern) else { return nil }
                return Entry(regex: regex, pluginType: providerType)
            }
        }
    }

    func provider(for url: URL) -> (any PatronServiceProvider)? {
        let urlString = url.absoluteString
        for entry in entries {
            if urlString.wholeMatch(of: entry.regex) != nil {
                return entry.makeProvider()
            }
        }
        // Fallback: match against host + path
        guard let host = url.host() else { return nil }
        let hostPath = host + url.path()
        for entry in entries {
            if hostPath.wholeMatch(of: entry.regex) != nil {
                return entry.makeProvider()
            }
        }
        return nil
    }

    var allProviderTypes: [any PatronServiceProvider.Type] {
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
