import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ChatModel: ObservableObject {
    struct Message: Identifiable, Codable {
        var id = UUID()
        let role: String
        var text: String
        var images: [Data]? = nil
    }
    struct Conversation: Identifiable, Codable {
        var id = UUID()
        var title: String
        var updated: Date
        var messages: [Message]
    }
    struct Failure {
        let conversation: UUID
        let message: String
    }
    /// Saved chats, most recently updated first.
    @Published private(set) var conversations: [Conversation] = []
    /// The chat on screen; nil while a new, not-yet-sent chat is open.
    @Published private(set) var currentID: UUID?
    /// The chat Luna is answering. Replies belong to their chat, so switching chats never cancels one.
    @Published private(set) var answeringID: UUID?
    @Published private(set) var searching = false
    @Published private(set) var failure: Failure?
    @Published var attachments: [Data] = []
    @Published var attachmentError: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    /// The chat whose context the Codex thread holds; a different chat starts a fresh thread.
    private var sessionChat: UUID?
    private var lastActivity = Date()
    private static let stallTimeout: TimeInterval = 120
    private let file: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Prism", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("chats.json")
    }()

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved.sorted { $0.updated > $1.updated }
        }
    }

    var messages: [Message] { conversations.first { $0.id == currentID }?.messages ?? [] }
    /// The open chat is being answered.
    var busy: Bool { answeringID != nil && answeringID == currentID }
    /// Luna is answering some other chat, so the open one has to wait.
    var busyElsewhere: Bool { answeringID != nil && answeringID != currentID }
    var error: String? {
        if let failure, failure.conversation == currentID { return failure.message }
        return messages.last?.role == "user" && !busy ? "No reply was received." : nil
    }
    /// The question to resend after a failure or an interrupted reply.
    var retryPrompt: String? { !busy && messages.last?.role == "user" ? messages.last?.text : nil }

    func newChat() { currentID = nil; attachments = []; attachmentError = nil }

    func select(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        currentID = id
        attachments = []; attachmentError = nil
    }

    func delete(_ id: UUID) {
        if id == answeringID { cancel() }
        if id == currentID { currentID = nil }
        if failure?.conversation == id { failure = nil }
        conversations.removeAll { $0.id == id }
        save()
    }

    func deleteCurrent() {
        if let currentID { delete(currentID) }
    }

    func stop() {
        guard let id = answeringID else { return }
        cancel()
        update(id) { if $0.last?.role == "assistant", $0.last?.text.isEmpty == true { $0.removeLast() } }
        failure = Failure(conversation: id, message: "Request stopped.")
        save()
    }

    func retry() {
        guard answeringID == nil, let prompt = retryPrompt, let id = currentID else { return }
        let images = messages.last?.images ?? []
        update(id) { $0.removeLast() }
        _ = send(prompt, images: images)
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        answeringID = nil
        searching = false
        Task { await CodexSession.shared.interrupt() }
    }

    private func update(_ id: UUID, _ change: (inout [Message]) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[index].messages)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }

    func attach(_ image: NSImage) {
        guard attachments.count < 4 else { attachmentError = "Attach up to 4 screenshots per message."; return }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]), data.count <= 10_000_000 else {
            attachmentError = "Choose an image smaller than 10 MB."; return
        }
        attachments.append(data)
        attachmentError = nil
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let image = NSImage(contentsOf: url) { attach(image) }
            else { attachmentError = "Couldn’t read \(url.lastPathComponent). Choose another image." }
        }
    }

    func send(_ text: String, images suppliedImages: [Data]? = nil) -> Bool {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = suppliedImages ?? attachments
        guard !text.isEmpty || !images.isEmpty, answeringID == nil else { return false }
        guard text.count <= 16000 else { attachmentError = "Keep your message under 16,000 characters."; return false }
        text = text.isEmpty ? "Help me understand this screenshot." : text
        var conversation = conversations.first { $0.id == currentID } ?? Conversation(title: "", updated: Date(), messages: [])
        let transcript = conversation.messages.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n\n")
        if conversation.messages.isEmpty { conversation.title = String(text.split(whereSeparator: \.isNewline).first ?? "").prefix(80).description }
        conversation.messages.append(Message(role: "user", text: text, images: images.isEmpty ? nil : images))
        conversation.updated = Date()
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        attachments = []; attachmentError = nil
        save()
        let id = conversation.id, current = generation
        let switching = sessionChat != id
        sessionChat = id
        currentID = id
        answeringID = id
        failure = nil
        searching = false
        lastActivity = Date()
        watchForStall(current)
        let contextImages = conversation.messages.flatMap { $0.images ?? [] }
        task = Task { @MainActor [weak self] in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let allPaths = try contextImages.enumerated().map { index, data in
                    let url = folder.appendingPathComponent("screenshot-\(index).png")
                    try data.write(to: url)
                    return url.path
                }
                let currentPaths = Array(allPaths.suffix(images.count))
                do {
                    if switching { await CodexSession.shared.reset() }
                    let stream = try await CodexSession.shared.ask(text, transcript: transcript, images: currentPaths, historyImages: allPaths)
                    for try await event in stream {
                        guard let self, self.generation == current else { return }
                        self.lastActivity = Date()
                        guard case .text(let delta) = event else { self.searching = true; continue }
                        self.searching = false
                        self.update(id) {
                            if $0.last?.role != "assistant" { $0.append(Message(role: "assistant", text: "")) }
                            $0[$0.count - 1].text += delta
                        }
                    }
                } catch let failure as CodexError where failure.transport {
                    // App server unusable: answer this message with a one-shot run instead.
                    let prompt = "\(CodexCLI.instructions)\n\n\(transcript.isEmpty ? "" : "Conversation so far:\n\(transcript)\n\n")User: \(text)"
                    let reply = try await CodexExec.ask(prompt, images: allPaths)
                    guard let self, self.generation == current else { return }
                    self.update(id) { $0.append(Message(role: "assistant", text: reply)) }
                }
                guard let self, self.generation == current else { return }
                if self.conversations.first(where: { $0.id == id })?.messages.last?.role != "assistant" {
                    throw CodexError(message: "No answer was returned. Please try again.")
                }
                self.finish(id)
            } catch {
                guard let self, self.generation == current else { return }
                self.update(id) { if $0.last?.role == "assistant" { $0.removeLast() } }
                self.finish(id, failure: (error as? CodexError)?.message ?? "Couldn’t complete the request. Please try again.")
            }
        }
        return true
    }

    private func finish(_ id: UUID, failure message: String? = nil) {
        task = nil
        answeringID = nil
        searching = false
        failure = message.map { Failure(conversation: id, message: $0) }
        if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].updated = Date() }
        save()
    }

    /// A reply that goes quiet is failed rather than left spinning forever.
    private func watchForStall(_ current: UUID) {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.generation == current, let id = self.answeringID else { return }
                if Date().timeIntervalSince(self.lastActivity) > Self.stallTimeout {
                    self.cancel()
                    self.update(id) { if $0.last?.role == "assistant" { $0.removeLast() } }
                    self.finish(id, failure: "Luna stopped responding. Try again.")
                    return
                }
            }
        }
    }
}
