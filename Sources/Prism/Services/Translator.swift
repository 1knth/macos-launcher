import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// On-device translation of the selected text into the user's primary language (macOS 15+).
final class Translator: ObservableObject {
    enum Status: Equatable { case idle, working, done(String), failed }

    @Published private(set) var status: Status = .idle
    /// A `TranslationSession.Configuration`, boxed so this class builds on macOS 14.
    @Published private(set) var configuration: Any?
    private(set) var text = ""
    private(set) var targetName = ""
    var onFinish: (() -> Void)?

    /// Whether the text is in another language than the user's own, and so worth translating.
    static func needsTranslation(_ text: String) -> Bool { sourceAndTarget(text) != nil }

    private static func sourceAndTarget(_ text: String) -> (Locale.Language, Locale.Language)? {
        guard #available(macOS 15, *), text.count >= 2 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(500)))
        guard let detected = recognizer.dominantLanguage else { return nil }
        let source = Locale.Language(identifier: detected.rawValue)
        let target = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
        guard source.languageCode != target.languageCode else { return nil }
        return (source, target)
    }

    func translate(_ text: String) {
        guard text != self.text || status == .failed else { return }
        self.text = text
        guard let (source, target) = Self.sourceAndTarget(text) else {
            status = .idle
            configuration = nil
            return
        }
        targetName = Locale.current.localizedString(forLanguageCode: target.languageCode?.identifier ?? "") ?? "Your Language"
        status = .working
        #if canImport(Translation)
        if #available(macOS 15, *) {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
        #endif
    }

    func finish(_ result: String?) {
        status = result.map { .done($0) } ?? .failed
        onFinish?()
    }
}

#if canImport(Translation)
/// Invisible view that owns the translation session; SwiftUI is the only way to get one.
@available(macOS 15, *)
struct TranslationHost: View {
    @ObservedObject var translator: Translator

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(translator.configuration as? TranslationSession.Configuration) { session in
                let text = translator.text
                let result = try? await session.translate(text).targetText
                await MainActor.run { if translator.text == text { translator.finish(result) } }
            }
    }
}
#endif
