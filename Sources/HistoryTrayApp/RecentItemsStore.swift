import AppKit
import Foundation

@MainActor
final class RecentItemsStore: ObservableObject {
    @Published private(set) var items: [RecentItem] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var openAppChoicesByPath: [String: OpenAppChoice]

    private let maxFolderItems = 30
    private let maxSystemItems = 300
    private static let openAppChoicesKey = "openAppChoicesByPath"
    private var systemItems: [RecentItem] = []
    private var finderItems: [RecentItem] = []
    private var finderTrackingTimer: Timer?

    init() {
        openAppChoicesByPath = Self.loadOpenAppChoices()
        mergeItems()
        startFinderTracking()
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [maxSystemItems] in
            do {
                let items = try Self.loadSystemRecentItems(limit: maxSystemItems)
                await MainActor.run {
                    self.systemItems = items
                    self.mergeItems()
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "系统最近记录读取失败：\(error.localizedDescription)"
                    self.systemItems = []
                    self.mergeItems()
                    self.isRefreshing = false
                }
            }
        }
    }

    func refreshFinderFolders(showErrors: Bool = true) {
        Task.detached(priority: .utility) {
            do {
                let items = try Self.loadFinderFolders()
                await MainActor.run {
                    self.upsertFinderItems(items)
                }
            } catch {
                await MainActor.run {
                    if showErrors {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func filteredItems(matching query: String) -> [RecentItem] {
        items.filter { $0.matches(query) }
    }

    func open(_ item: RecentItem) {
        open(item, with: openAppChoice(for: item))
    }

    func open(_ item: RecentItem, with appChoice: OpenAppChoice) {
        switch appChoice {
        case .systemDefault:
            NSWorkspace.shared.open(item.url)
        case .terminal:
            openTerminal(at: item.url)
        case .application(let appURL):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [item.url],
                withApplicationAt: appURL,
                configuration: configuration
            )
        }
    }

    func openAppChoice(for item: RecentItem) -> OpenAppChoice {
        openAppChoicesByPath[item.path] ?? .systemDefault
    }

    func openAndRemember(_ item: RecentItem, with appChoice: OpenAppChoice) {
        setOpenApp(appChoice, for: item)
        open(item, with: appChoice)
    }

    func chooseOpenApp(for item: RecentItem) {
        let panel = NSOpenPanel()
        panel.title = "选择打开应用"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let appURL = panel.url else {
            return
        }

        openAndRemember(item, with: .application(appURL))
    }

    func setOpenApp(_ appChoice: OpenAppChoice, for item: RecentItem) {
        switch appChoice {
        case .systemDefault:
            openAppChoicesByPath.removeValue(forKey: item.path)
        case .terminal:
            openAppChoicesByPath[item.path] = appChoice
        case .application(let appURL):
            openAppChoicesByPath[item.path] = FileManager.default.fileExists(atPath: appURL.path) ? appChoice : nil
        }

        persistOpenAppChoices()
    }

    func openTerminal(_ item: RecentItem) {
        openAndRemember(item, with: .terminal)
    }

    func copyPath(_ item: RecentItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.path, forType: .string)
    }

    private func startFinderTracking() {
        guard finderTrackingTimer == nil else {
            return
        }

        refreshFinderFolders()
        finderTrackingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFinderFolders(showErrors: false)
            }
        }
    }

    private func upsertFinderItems(_ items: [RecentItem]) {
        for item in items {
            finderItems.removeAll { $0.path == item.path }
            finderItems.insert(item, at: 0)
        }

        finderItems = Array(finderItems.prefix(maxFolderItems))
        mergeItems()
    }

    private func mergeItems() {
        var mergedByPath: [String: RecentItem] = [:]

        for item in systemItems + finderItems {
            if let existing = mergedByPath[item.path] {
                mergedByPath[item.path] = existing.lastUsedAt >= item.lastUsedAt ? existing : item
            } else {
                mergedByPath[item.path] = item
            }
        }

        let existingItems = mergedByPath.values
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }

        let folders = existingItems
            .filter { $0.type == .folder }
            .prefix(maxFolderItems)

        items = Array(folders)
    }

    private func openTerminal(at url: URL) {
        if let terminalURL = Self.terminalApplicationURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: terminalURL,
                configuration: configuration
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func persistOpenAppChoices() {
        let storedChoices = openAppChoicesByPath.mapValues(\.storageValue)
        UserDefaults.standard.set(storedChoices, forKey: Self.openAppChoicesKey)
    }

    private static func loadOpenAppChoices() -> [String: OpenAppChoice] {
        guard let storedChoices = UserDefaults.standard.dictionary(forKey: openAppChoicesKey) as? [String: String] else {
            return [:]
        }

        return storedChoices.compactMapValues { storedValue in
            if storedValue == OpenAppChoice.terminalStorageValue {
                return .terminal
            }

            let appURL = URL(fileURLWithPath: storedValue)
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                return nil
            }

            return .application(appURL)
        }
    }

    private static var terminalApplicationURL: URL? {
        let terminalPaths = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]

        return terminalPaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated private static func loadSystemRecentItems(limit: Int) throws -> [RecentItem] {
        try loadSystemItems(
            query: "kMDItemLastUsedDate == * && kMDItemContentTypeTree == 'public.folder'",
            expectedType: .folder,
            limit: limit
        )
    }

    nonisolated private static func loadSystemItems(
        query: String,
        expectedType: RecentItem.ItemType,
        limit: Int
    ) throws -> [RecentItem] {
        try runMDFindLastUsedDate(query: query)
            .compactMap { result -> RecentItem? in
                guard
                    let item = makeRecentItem(
                        from: URL(fileURLWithPath: result.path),
                        source: .system,
                        lastUsedAt: result.lastUsedAt
                    ),
                    item.type == expectedType
                else {
                    return nil
                }

                return item
            }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(limit)
            .map { $0 }
    }

    nonisolated private static func loadFinderFolders() throws -> [RecentItem] {
        let windowFolders = try loadFinderWindowFolders()
        let recentFolders = loadFinderRecentFolders()
        var mergedByPath: [String: RecentItem] = [:]

        for item in recentFolders + windowFolders {
            if let existing = mergedByPath[item.path] {
                mergedByPath[item.path] = existing.lastUsedAt >= item.lastUsedAt ? existing : item
            } else {
                mergedByPath[item.path] = item
            }
        }

        return mergedByPath.values.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    nonisolated private static func loadFinderWindowFolders() throws -> [RecentItem] {
        let script = """
        tell application "Finder"
            set folderPaths to {}
            repeat with finderWindow in windows
                try
                    set end of folderPaths to POSIX path of (target of finderWindow as alias)
                end try
            end repeat
            set AppleScript's text item delimiters to linefeed
            return folderPaths as text
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw FinderAccessError.scriptCreationFailed
        }

        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            throw FinderAccessError.appleEventFailed(message: message, number: number)
        }

        let paths = result.stringValue?
            .split(separator: "\n")
            .map { String($0) } ?? []

        return paths.compactMap { path in
            makeRecentItem(from: URL(fileURLWithPath: path), source: .finder, lastUsedAt: Date())
        }
    }

    nonisolated private static func loadFinderRecentFolders() -> [RecentItem] {
        guard
            let finderDefaults = UserDefaults(suiteName: "com.apple.finder"),
            let recentFolders = finderDefaults.array(forKey: "FXRecentFolders") as? [[String: Any]]
        else {
            return []
        }

        let now = Date()

        return recentFolders.enumerated().compactMap { index, entry in
            guard let bookmarkData = entry["file-bookmark"] as? Data else {
                return nil
            }

            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }

            return makeRecentItem(
                from: url,
                source: .finder,
                lastUsedAt: now.addingTimeInterval(TimeInterval(-index))
            )
        }
    }

    nonisolated private static func runMDFind(query: String) throws -> [String] {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        process.standardOutput = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let rawOutput = String(decoding: data, as: UTF8.self)

        return rawOutput
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func runMDFindLastUsedDate(query: String) throws -> [SpotlightResult] {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-attr", "kMDItemLastUsedDate", query]
        process.standardOutput = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let rawOutput = String(decoding: data, as: UTF8.self)

        return rawOutput
            .split(separator: "\n")
            .compactMap { parseMDFindLastUsedDateLine(String($0)) }
    }

    nonisolated private static func parseMDFindLastUsedDateLine(_ line: String) -> SpotlightResult? {
        let marker = "   kMDItemLastUsedDate = "
        guard let markerRange = line.range(of: marker, options: .backwards) else {
            return nil
        }

        let path = String(line[..<markerRange.lowerBound])
        let rawDate = String(line[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let lastUsedAt = spotlightDateFormatter.date(from: rawDate) else {
            return nil
        }

        return SpotlightResult(path: path, lastUsedAt: lastUsedAt)
    }

    nonisolated private static func makeRecentItem(
        from url: URL,
        source: RecentItem.Source,
        lastUsedAt overrideLastUsedAt: Date? = nil
    ) -> RecentItem? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .creationDateKey,
            .localizedNameKey
        ]

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }

        guard values.isDirectory == true else {
            return nil
        }

        let lastUsedAt = overrideLastUsedAt
            ?? spotlightLastUsedDate(for: url)
            ?? values.contentAccessDate
            ?? values.contentModificationDate
            ?? values.creationDate
            ?? Date.distantPast

        return RecentItem(
            path: url.path,
            name: values.localizedName ?? url.lastPathComponent,
            type: .folder,
            lastUsedAt: lastUsedAt,
            source: source
        )
    }

    nonisolated private static func spotlightLastUsedDate(for url: URL) -> Date? {
        guard let rawDate = try? runMDLS(attribute: "kMDItemLastUsedDate", path: url.path) else {
            return nil
        }

        let trimmedDate = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDate.isEmpty, trimmedDate != "(null)" else {
            return nil
        }

        return spotlightDateFormatter.date(from: trimmedDate)
    }

    nonisolated private static func runMDLS(attribute: String, path: String) throws -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-raw", "-name", attribute, path]
        process.standardOutput = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static let spotlightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}

private enum FinderAccessError: LocalizedError {
    case scriptCreationFailed
    case appleEventFailed(message: String?, number: Int?)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "无法创建 Finder 读取脚本。"
        case .appleEventFailed(let message, let number):
            if number == -1743 {
                return "需要授权访问 Finder：系统设置 > 隐私与安全性 > 自动化 > History > Finder。"
            }

            return "Finder 文件夹读取失败：\(message ?? "未知错误")"
        }
    }
}

private struct SpotlightResult {
    let path: String
    let lastUsedAt: Date
}

enum OpenAppChoice: Equatable {
    case systemDefault
    case terminal
    case application(URL)

    static let terminalStorageValue = "__terminal__"

    var displayName: String {
        switch self {
        case .systemDefault:
            return "Finder"
        case .terminal:
            return "终端"
        case .application(let appURL):
            return appURL.deletingPathExtension().lastPathComponent
        }
    }

    var storageValue: String {
        switch self {
        case .systemDefault:
            return ""
        case .terminal:
            return Self.terminalStorageValue
        case .application(let appURL):
            return appURL.path
        }
    }
}
