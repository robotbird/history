import Foundation

struct RecentItem: Identifiable, Codable, Hashable {
    enum ItemType: String, Codable {
        case folder

        var displayName: String {
            switch self {
            case .folder:
                return "文件夹"
            }
        }
    }

    var id: String { path }

    let path: String
    let name: String
    let type: ItemType
    let lastUsedAt: Date
    let source: Source

    enum Source: String, Codable {
        case system
        case finder

        var displayName: String {
            switch self {
            case .system:
                return "系统"
            case .finder:
                return "Finder"
            }
        }
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return name.localizedCaseInsensitiveContains(normalizedQuery)
            || path.localizedCaseInsensitiveContains(normalizedQuery)
            || type.displayName.localizedCaseInsensitiveContains(normalizedQuery)
    }
}
