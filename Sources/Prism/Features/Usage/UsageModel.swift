import AppKit
import SwiftUI
import Security
import PrismCore

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude, gpt
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "GPT / Codex" }
    var dashboard: URL { URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")! }
    var setup: String { self == .claude ? "Sign in to Claude Code, then refresh. Allow Prism access to Claude Code credentials if macOS asks." : "Sign in with ChatGPT in Codex, then refresh. API key accounts do not expose subscription limits." }
}

/// Only what a usage request needs, kept in memory so live updates don't reread the Keychain.
private struct UsageCredentials: Sendable {
    let token: String
    let account: String?
    let expires: Date?
    var fresh: Bool { expires.map { $0.timeIntervalSinceNow > 60 } ?? true }
}

struct UsageResult {
    var windows: [UsageWindow] = []
    var updated: Date?
    var error: String?
    var needsKeychainAccess = false
    var needsSignIn = false
}

@MainActor final class UsageModel: ObservableObject {
    static let shared = UsageModel()

    @Published var results: [UsageProvider: UsageResult] = [:]
    @Published var loading = false
    private var limitsFetched: Date?
    private var cachedCredentials: [UsageProvider: UsageCredentials] = [:]
    @Published var tokenDays: [TokenDay] = []
    @Published var loadingTokens = false
    private var tokenCache = TokenCache()
    private var tokensScanned: Date?

    /// Rescans local logs at most every few minutes unless forced; unchanged files come from the cache.
    func refreshTokens(force: Bool = false) {
        guard !loadingTokens else { return }
        if !force, let tokensScanned, -tokensScanned.timeIntervalSinceNow < 300 { return }
        loadingTokens = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let since = Calendar.current.tokenCalendarStart
        let cache = tokenCache
        Task {
            let (days, cache) = await Task.detached(priority: .background) {
                var cache = cache
                let days = TokenHistory.load(claudeDirectory: home.appendingPathComponent(".claude/projects"), codexDirectory: codex.appendingPathComponent("sessions"), piDirectory: home.appendingPathComponent(".pi/agent/sessions"), since: since, cache: &cache)
                return (days, cache)
            }.value
            tokenDays = days
            tokenCache = cache
            tokensScanned = Date()
            loadingTokens = false
        }
    }

    /// Limits update live while the view is visible, without polling the providers more than once a minute.
    func refreshIfStale() {
        if let limitsFetched, -limitsFetched.timeIntervalSinceNow < 60 { return }
        refresh()
    }

    func refresh(allowKeychainPrompt: Bool = false) {
        guard !loading else { return }
        loading = true
        // Only an explicit authorization action may display Keychain UI.
        let cached = cachedCredentials
        Task {
            await withTaskGroup(of: (UsageProvider, UsageResult, UsageCredentials?).self) { group in
                for provider in UsageProvider.allCases {
                    group.addTask {
                        let (result, credentials) = await Self.fetch(provider, cached: cached[provider], allowKeychainPrompt: allowKeychainPrompt)
                        return (provider, result, credentials)
                    }
                }
                for await (provider, result, credentials) in group {
                    cachedCredentials[provider] = credentials
                    // A failed update keeps the last known usage on screen, marked with its age.
                    var result = result
                    if result.error != nil, let previous = results[provider], !previous.windows.isEmpty {
                        result.windows = previous.windows
                        result.updated = previous.updated
                    }
                    results[provider] = result
                }
            }
            limitsFetched = Date()
            loading = false
        }
    }

    /// Uses cached credentials while they're fresh, and rereads them once if the provider rejects them.
    nonisolated private static func fetch(_ provider: UsageProvider, cached: UsageCredentials?, allowKeychainPrompt: Bool) async -> (UsageResult, UsageCredentials?) {
        do {
            let reused = cached?.fresh == true && !allowKeychainPrompt
            var credentials = try reused ? cached! : credentials(provider, allowKeychainPrompt: allowKeychainPrompt)
            if provider == .claude, let expires = credentials.expires, expires <= Date() {
                return (UsageResult(error: "Claude’s sign-in token has expired. Run claude auth login in Terminal, then refresh.", needsSignIn: true), nil)
            }
            var (data, status) = try await request(provider, credentials)
            if reused, [401, 403].contains(status) {
                credentials = try self.credentials(provider, allowKeychainPrompt: false)
                (data, status) = try await request(provider, credentials)
            }
            guard status == 200 else {
                let message = status == 401 ? "Sign in to \(provider == .claude ? "Claude Code with claude auth login in Terminal" : "Codex") again, then refresh." : status == 403 ? "Access to usage was denied. Check your subscription and permissions in the usage dashboard." : status == 429 ? "Too many requests. Try refreshing later." : "Usage service unavailable (HTTP \(status)). Try again later."
                return (UsageResult(error: message, needsSignIn: status == 401), [401, 403].contains(status) ? nil : credentials)
            }
            let windows = try UsageLimits.parse(data, claude: provider == .claude)
            return (windows.isEmpty ? UsageResult(error: "The provider returned no supported usage windows. Check the usage dashboard.") : UsageResult(windows: windows, updated: Date()), credentials)
        } catch CredentialError.authorizationRequired {
            return (UsageResult(error: "Allow Keychain access to read Claude usage, or open the usage dashboard.", needsKeychainAccess: true), nil)
        } catch {
            // Never expose credential contents or response bodies in errors.
            return (UsageResult(error: error is URLError ? "Couldn’t reach the usage service. Check your connection and refresh." : provider.setup), error is URLError ? cached : nil)
        }
    }

    nonisolated private static func request(_ provider: UsageProvider, _ credentials: UsageCredentials) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: provider == .claude ? "https://api.anthropic.com/api/oauth/usage" : "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .claude {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else {
            request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
            if let account = credentials.account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private enum CredentialError: Error { case authorizationRequired, missing }

    nonisolated private static func credentials(_ provider: UsageProvider, allowKeychainPrompt: Bool) throws -> UsageCredentials {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let data: Data
        if provider == .claude {
            if allowKeychainPrompt {
                var value: CFTypeRef?
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                            kSecAttrService as String: "Claude Code-credentials",
                                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
                let status = SecItemCopyMatching(query as CFDictionary, &value)
                guard status == errSecSuccess, let stored = value as? Data else { throw CredentialError.authorizationRequired }
                data = stored
            } else if let stored = try claudeKeychainItem() {
                data = stored
            } else {
                data = try Data(contentsOf: home.appendingPathComponent(".claude/.credentials.json"))
            }
        } else {
            let directory = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home.appendingPathComponent(".codex")
            data = try Data(contentsOf: directory.appendingPathComponent("auth.json"))
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let object = root?[provider == .claude ? "claudeAiOauth" : "tokens"] as? [String: Any] ?? [:]
        guard let token = object[provider == .claude ? "accessToken" : "access_token"] as? String, !token.isEmpty else { throw CredentialError.missing }
        let expires = (object["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return UsageCredentials(token: token, account: object["account_id"] as? String, expires: expires)
    }

    /// Claude Code writes its Keychain item with `/usr/bin/security`, which leaves that tool as the item's only trusted reader
    /// and resets the list each time Claude Code renews its sign-in. Reading through it avoids a password prompt every time.
    /// Returns nil when there is no item.
    nonisolated private static func claudeKeychainItem() throws -> Data? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: return data
        case 44: return nil  // errSecItemNotFound
        default: throw CredentialError.authorizationRequired
        }
    }
}
