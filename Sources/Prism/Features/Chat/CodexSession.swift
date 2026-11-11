import Foundation

/// Chat runs through the Codex CLI so it uses the user's ChatGPT subscription sign-in, not an API key.
enum CodexCLI {
    static let model = "gpt-6-luna"
    static let instructions = "You are a helpful assistant in the Prism launcher. Give clear, concise answers. Use web search for current events, recent facts, or anything time-sensitive, and cite sources as links. You can see images attached to the conversation. You have no other access to the user's files, apps, or clipboard."

    static var path: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum CodexEvent {
    case text(String)
    case searching
}

struct CodexError: Error {
    let message: String
    /// The app server itself is unusable (missing, crashed, unsupported protocol), as opposed to a failed turn.
    var transport = false

    static func turn(_ error: Any?) -> CodexError {
        let message = (error as? [String: Any])?["message"] as? String ?? "Codex couldn’t answer. Please try again."
        return CodexError(message: message.localizedCaseInsensitiveContains("usage limit") ? "Codex usage limit reached. Check Usage Limits for reset times." : message)
    }
}

/// One long-lived `codex app-server` process speaking JSON-RPC over stdio.
/// Started on first use, keeps one thread per conversation, and exits after a few idle minutes.
actor CodexSession {
    static let shared = CodexSession()
    private static let idleTimeout: Duration = .seconds(300)

    private var process: Process?
    private var stdin: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var threadID: String?
    private var turn: (id: String?, stream: AsyncThrowingStream<CodexEvent, Error>.Continuation)?
    private var interruptRequested = false
    private var activity = 0

    /// Streams the reply's text deltas. Finishes when the turn completes; throws if it fails.
    /// `transcript` is the conversation so far, used only if a new thread has to pick it up (first use, restart, after a fallback).
    func ask(_ text: String, transcript: String, images: [String] = [], historyImages: [String] = []) async throws -> AsyncThrowingStream<CodexEvent, Error> {
        guard turn == nil else { throw CodexError(message: "A reply is already in progress.") }
        activity += 1
        try await launchIfNeeded()
        let imagePaths = threadID == nil ? historyImages : images
        var input = text
        if threadID == nil {
            if !transcript.isEmpty { input = "Conversation so far:\n\(transcript)\n\nUser: \(text)" }
            let result = try await request("thread/start", ["model": CodexCLI.model, "cwd": NSTemporaryDirectory(), "sandbox": "read-only",
                                                            "approvalPolicy": "never", "ephemeral": true, "config": ["web_search": "live"], "baseInstructions": CodexCLI.instructions])
            guard let id = (result["thread"] as? [String: Any])?["id"] as? String else { throw CodexError(message: "Codex returned an unexpected response.", transport: true) }
            threadID = id
        }
        let (stream, continuation) = AsyncThrowingStream<CodexEvent, Error>.makeStream()
        turn = (nil, continuation)
        interruptRequested = false
        do {
            var inputs: [[String: Any]] = [["type": "text", "text": input, "text_elements": []]]
            inputs += imagePaths.map { ["type": "localImage", "path": $0] }
            let result = try await request("turn/start", ["threadId": threadID!, "input": inputs])
            guard turn != nil else { return stream }
            turn?.id = (result["turn"] as? [String: Any])?["id"] as? String
            if interruptRequested { await interrupt() }
        } catch {
            turn = nil
            throw error
        }
        return stream
    }

    func interrupt() async {
        guard let current = turn else { return }
        guard let turnID = current.id, let threadID else { interruptRequested = true; return }
        _ = try? await request("turn/interrupt", ["threadId": threadID, "turnId": turnID])
    }

    /// Next question starts a fresh Codex thread.
    func reset() async {
        await interrupt()
        threadID = nil
    }

    func shutdown() {
        process?.terminate()
    }

    // MARK: Transport

    private func launchIfNeeded() async throws {
        if process?.isRunning == true { return }
        guard let path = CodexCLI.path else { throw CodexError(message: "Install Codex and sign in with ChatGPT to start chatting.", transport: true) }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A single ordered stream keeps responses and notifications in the order Codex wrote them.
        let (chunks, sink) = AsyncStream<Data>.makeStream()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; sink.finish() } else { sink.yield(data) }
        }
        do { try process.run() } catch { throw CodexError(message: "Couldn’t start Codex.", transport: true) }
        self.process = process
        stdin = input.fileHandleForWriting
        Task { await self.read(chunks, from: process) }
        do {
            _ = try await request("initialize", ["clientInfo": ["name": "prism", "title": "Prism", "version": "1"], "capabilities": NSNull()])
            write(["method": "initialized"])
        } catch {
            process.terminate()
            throw CodexError(message: "This Codex version isn’t supported.", transport: true)
        }
    }

    private func read(_ chunks: AsyncStream<Data>, from source: Process) async {
        var buffer = Data()
        for await chunk in chunks {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(message) }
            }
        }
        exited(source)
    }

    private func handle(_ message: [String: Any]) {
        let method = message["method"] as? String
        if let id = message["id"] as? Int {
            if let method {
                // Approvals can't happen with a read-only, never-approve thread; decline anything else Codex asks.
                write(["id": id, "error": ["code": -32601, "message": "Prism doesn’t handle \(method)"]])
            } else if let continuation = pending.removeValue(forKey: id) {
                if let error = message["error"] { continuation.resume(throwing: CodexError.turn(error)) }
                else { continuation.resume(returning: message["result"] as? [String: Any] ?? [:]) }
            }
            return
        }
        let params = message["params"] as? [String: Any] ?? [:]
        guard params["threadId"] as? String == threadID, let current = turn else { return }
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { current.stream.yield(.text(delta)) }
        case "item/started" where (params["item"] as? [String: Any])?["type"] as? String == "webSearch":
            current.stream.yield(.searching)
        case "error" where params["willRetry"] as? Bool != true:
            finishTurn(throwing: CodexError.turn(params["error"]))
        case "turn/completed":
            let turn = params["turn"] as? [String: Any]
            if turn?["status"] as? String == "failed" { finishTurn(throwing: CodexError.turn(turn?["error"])) }
            else { finishTurn() }
        default: break
        }
    }

    private func finishTurn(throwing error: Error? = nil) {
        turn?.stream.finish(throwing: error)
        turn = nil
        scheduleIdleShutdown()
    }

    private func exited(_ source: Process) {
        guard source === process else { return }
        process = nil
        stdin = nil
        threadID = nil
        let error = CodexError(message: "Codex stopped unexpectedly. Please try again.", transport: true)
        pending.values.forEach { $0.resume(throwing: error) }
        pending = [:]
        turn?.stream.finish(throwing: error)
        turn = nil
    }

    private func scheduleIdleShutdown() {
        let mark = activity
        Task {
            try? await Task.sleep(for: Self.idleTimeout)
            if activity == mark, turn == nil { shutdown() }
        }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            write(["id": id, "method": method, "params": params])
        }
    }

    private func write(_ message: [String: Any]) {
        guard let stdin, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(UInt8(ascii: "\n"))
        try? stdin.write(contentsOf: data)
    }
}

/// Fallback for when the app server is unavailable: one `codex exec` run per message, with the transcript inlined.
enum CodexExec {
    static func ask(_ prompt: String, images: [String] = []) async throws -> String {
        guard let path = CodexCLI.path else { throw CodexError(message: "Install Codex and sign in with ChatGPT to start chatting.") }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["exec", "-m", CodexCLI.model, "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "-s", "read-only", "-c", "web_search=\"live\"", "--json", "-"]
        for image in images { process.arguments?.insert(contentsOf: ["--image", image], at: 1) }
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try await Task.detached {
                do { try process.run() } catch { throw CodexError(message: "Couldn’t start Codex.") }
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                try Task.checkCancellation()
                var reply: String?, failure: Any?
                for line in data.split(separator: UInt8(ascii: "\n")) {
                    guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                    if event["type"] as? String == "item.completed", let item = event["item"] as? [String: Any],
                       item["type"] as? String == "agent_message", let text = item["text"] as? String { reply = text }
                    if event["type"] as? String == "turn.failed" { failure = event["error"] }
                }
                if let reply, !reply.isEmpty { return reply }
                if failure != nil { throw CodexError.turn(failure) }
                throw CodexError(message: process.terminationStatus == 0 ? "No answer was returned. Please try again." : "Codex failed. Run `codex login` and try again.")
            }.value
        } onCancel: { process.terminate() }
    }
}
