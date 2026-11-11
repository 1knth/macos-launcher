import AppKit
import PrismCore
import UniformTypeIdentifiers

/// Spotlight-backed file search with filter tokens:
///   kind:image|pdf|text|code|folder|video|audio|app|doc   ext:swift   in:contents
final class FileSearcher: NSObject {
    private(set) var results: [URL] = []
    private(set) var searching = false
    private var query: NSMetadataQuery?
    private var pending: DispatchWorkItem?
    private var term = ""
    private var limit = 60
    var onUpdate: (() -> Void)?

    private static let kinds: [String: String] = [
        "image": "public.image", "img": "public.image", "photo": "public.image",
        "pdf": "com.adobe.pdf", "text": "public.text", "code": "public.source-code",
        "folder": "public.folder", "dir": "public.folder", "video": "public.movie", "movie": "public.movie",
        "audio": "public.audio", "music": "public.audio", "app": "com.apple.application-bundle",
        "doc": "public.composite-content", "archive": "public.archive", "zip": "public.archive",
    ]

    func search(_ text: String, contents: Bool = false, limit: Int = 60, recentWhenEmpty: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let key = "\(trimmed)|\(contents)|\(limit)"
        guard key != term else { return }
        term = key
        self.limit = limit
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start(trimmed, contents: contents, recentWhenEmpty: recentWhenEmpty) }
        pending = work
        // Debounce keystrokes so Spotlight is not restarted for every character.
        DispatchQueue.main.asyncAfter(deadline: .now() + (trimmed.isEmpty ? 0 : 0.12), execute: work)
    }

    func stop() {
        pending?.cancel()
        query?.stop()
        query = nil
        term = ""
    }

    private func start(_ text: String, contents: Bool, recentWhenEmpty: Bool) {
        query?.stop()
        NotificationCenter.default.removeObserver(self)
        guard let predicate = Self.predicate(text, contents: contents, recentWhenEmpty: recentWhenEmpty) else {
            results = []
            searching = false
            onUpdate?()
            return
        }
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey as String, ascending: false)]
        query.notificationBatchingInterval = 0.15
        NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryGatheringProgress, object: query)
        self.query = query
        searching = true
        query.start()
    }

    @objc private func gathered(_ notification: Notification) {
        guard let query, notification.object as? NSMetadataQuery === query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        if notification.name == .NSMetadataQueryDidFinishGathering { searching = false }
        let name = Self.nameTerms(term.components(separatedBy: "|").first ?? "").joined(separator: " ")
        var scored: [(URL, Double)] = []
        let count = min(query.resultCount, 400)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey as String) as? String,
                  !Self.isNoise(path) else { continue }
            let url = URL(fileURLWithPath: path)
            let used = item.value(forAttribute: NSMetadataItemLastUsedDateKey as String) as? Date
            var score = name.isEmpty ? 0.5 : Fuzzy.score(name, url.lastPathComponent) ?? 0.3
            if let used { score += max(0, 0.2 - (-used.timeIntervalSinceNow / 86400 / 150)) }
            // Shallower paths are usually what people mean.
            score -= Double(path.split(separator: "/").count) * 0.004
            scored.append((url, score))
        }
        results = scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        onUpdate?()
    }

    static func isNoise(_ path: String) -> Bool {
        path.contains("/Library/") || path.contains("/.") || path.contains("/node_modules/")
            || path.contains("/DerivedData/") || path.contains(".build/") || path.hasSuffix(".DS_Store")
    }

    static func nameTerms(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init).filter { !$0.contains(":") }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "*", with: "\\*")
    }

    static func predicate(_ text: String, contents: Bool, recentWhenEmpty: Bool) -> NSPredicate? {
        var clauses: [String] = []
        var wantsContents = contents
        for token in text.split(separator: " ").map(String.init) {
            let lowered = token.lowercased()
            if lowered.hasPrefix("kind:"), let type = kinds[String(lowered.dropFirst(5))] {
                clauses.append("kMDItemContentTypeTree == \"\(type)\"")
            } else if lowered.hasPrefix("ext:") || lowered.hasPrefix("."), lowered.count > 1, !lowered.dropFirst().contains(".") {
                let ext = lowered.hasPrefix(".") ? String(lowered.dropFirst()) : String(lowered.dropFirst(4))
                clauses.append("kMDItemFSName == \"*.\(escape(ext))\"c")
            } else if lowered == "in:contents" || lowered == "in:content" {
                wantsContents = true
            }
        }
        let words = nameTerms(text).filter { !$0.hasPrefix(".") }
        for word in words {
            let value = escape(word)
            clauses.append(wantsContents
                ? "(kMDItemFSName == \"*\(value)*\"cd || kMDItemTextContent == \"\(value)*\"cdw)"
                : "kMDItemFSName == \"*\(value)*\"cd")
        }
        if words.isEmpty, clauses.isEmpty {
            // No query: recently used files, newest first.
            guard recentWhenEmpty else { return nil }
            clauses = ["kMDItemLastUsedDate >= $time.today(-7)", "kMDItemContentTypeTree != \"public.folder\""]
        } else if words.isEmpty {
            // Only filters ("kind:pdf"): limit to the last year so Spotlight returns quickly.
            clauses.append("kMDItemLastUsedDate >= $time.today(-365)")
        }
        return NSPredicate(fromMetadataQueryString: clauses.joined(separator: " && "))
    }
}

enum FileKind {
    static func type(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

    static func isImage(_ url: URL) -> Bool { type(of: url)?.conforms(to: .image) == true }

    static func isText(_ url: URL) -> Bool {
        guard let type = type(of: url) else { return false }
        if type.conforms(to: .rtf) { return false }
        if [.text, .sourceCode, .json, .xml, .propertyList].contains(where: { type.conforms(to: $0) }) { return true }
        return ["md", "txt", "log", "yml", "yaml", "toml", "ini", "cfg", "conf", "env", "csv", "tsv", "gitignore", "sh", "zsh"].contains(url.pathExtension.lowercased())
    }

    static func kindName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "File"
    }
}
