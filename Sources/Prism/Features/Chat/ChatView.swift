import AppKit
import SwiftUI

struct ChatView: View {
    @ObservedObject var chat: ChatModel
    @Binding var draft: String

    var body: some View {
        HStack(spacing: 0) {
            ChatSidebar(chat: chat, draft: $draft).frame(width: 210)
            Hairline(vertical: true)
            VStack(spacing: 0) {
                if chat.messages.isEmpty && !chat.busy {
                    ChatEmptyState(chat: chat, draft: $draft)
                } else {
                    transcript
                }
                Hairline()
                composer
                statusBar
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { ChatBubble(message: $0).id($0.id) }
                    if chat.busy && chat.messages.last?.role != "assistant" {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(chat.searching ? "Searching the web…" : "Thinking…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let error = chat.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(18)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.currentID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.busy) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chat.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(chat.attachments.enumerated()), id: \.offset) { index, data in
                            if let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 64, height: 48)
                                    .overlay(alignment: .topTrailing) {
                                        Button { chat.attachments.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black)
                                        }.buttonStyle(.plain).help("Remove screenshot")
                                    }
                            }
                        }
                    }
                }.frame(height: 50)
            }
            ChatEditor(text: $draft)
                .frame(height: 48)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Message Luna or paste a screenshot…").font(.system(size: 13))
                            .foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 7).allowsHitTesting(false)
                    }
                }
            HStack {
                Button { chat.chooseImages() } label: { Label("Attach", systemImage: "paperclip") }
                    .help("Attach screenshots or images (up to 4)")
                Text("⇧Return for a new line").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if chat.busy {
                    Button { chat.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { if chat.send(draft) { draft = "" } } label: { Label("Send", systemImage: "arrow.up") }
                        .buttonStyle(.borderedProminent)
                        .disabled(chat.busyElsewhere || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.attachments.isEmpty))
                }
            }.controlSize(.small)
            if let error = chat.attachmentError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
        .padding(12)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if chat.busy {
                Text(chat.searching ? "Searching the web…" : "Luna is replying…").font(.caption).foregroundStyle(.secondary)
            } else if chat.busyElsewhere {
                ProgressView().controlSize(.mini)
                Text("Luna is answering another chat…").font(.caption).foregroundStyle(.secondary)
            } else if chat.retryPrompt != nil {
                Button { chat.retry() } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    .disabled(chat.busyElsewhere)
            } else {
                KeyCap(text: "↩")
                Text("Send").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Luna · web search").font(.caption).foregroundStyle(.tertiary)
        }
        .controlSize(.small)
        .padding(.horizontal, 14).frame(height: 34)
    }
}

private struct ChatSidebar: View {
    @ObservedObject var chat: ChatModel
    @Binding var draft: String
    @State private var hovered: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Button { chat.newChat(); draft = "" } label: {
                HStack {
                    Label("New Chat", systemImage: "square.and.pencil")
                    Spacer()
                    ShortcutCaps(combo: .cmd("n"))
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chat.currentID == nil ? Color.primary.opacity(0.09) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if chat.conversations.isEmpty {
                        Text("Your chats will appear here.").font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                    ForEach(sections, id: \.title) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.items) { row($0) }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    private func row(_ conversation: ChatModel.Conversation) -> some View {
        let selected = conversation.id == chat.currentID
        return HStack(spacing: 4) {
            Text(conversation.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if conversation.id == chat.answeringID && hovered != conversation.id { ProgressView().controlSize(.mini) }
            if hovered == conversation.id {
                Button { chat.delete(conversation.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete chat")
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.accentColor.opacity(0.22) : hovered == conversation.id ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { chat.select(conversation.id); draft = "" }
        .onHover { hovered = $0 ? conversation.id : (hovered == conversation.id ? nil : hovered) }
        .contextMenu {
            Button("Copy Chat") { Paster.copy(conversation.messages.map { "\($0.role == "user" ? "You" : "Luna"): \($0.text)" }.joined(separator: "\n\n")) }
            Divider()
            Button("Delete Chat", role: .destructive) { chat.delete(conversation.id) }
        }
    }

    private var sections: [(title: String, items: [ChatModel.Conversation])] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let groups: [(String, (Date) -> Bool)] = [("Today", calendar.isDateInToday), ("Yesterday", calendar.isDateInYesterday),
                                                  ("Previous 7 Days", { $0 > weekAgo }), ("Older", { _ in true })]
        var remaining = chat.conversations
        return groups.compactMap { title, test in
            let items = remaining.filter { test($0.updated) }
            remaining.removeAll { test($0.updated) }
            return items.isEmpty ? nil : (title, items)
        }
    }
}

private struct ChatBubble: View {
    let message: ChatModel.Message
    @State private var hovering = false
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) } else {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Circle().fill(Color.indigo))
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if let images = message.images {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                    .textSelection(.enabled)
                    .padding(.horizontal, isUser ? 11 : 0).padding(.vertical, isUser ? 7 : 1)
                    .background(isUser ? RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.18)) : nil)
                Button { Paster.copy(message.text) } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).opacity(hovering ? 1 : 0)
            }
            if !isUser { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { hovering = $0 }
    }
}

private struct ChatEmptyState: View {
    @ObservedObject var chat: ChatModel
    @Binding var draft: String
    private let suggestions = ["Explain this screenshot", "Help me write"]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Ask Luna anything").font(.title3.weight(.semibold))
            Text("Ask a question, attach a screenshot, or search the web.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { draft = suggestion == "Explain this screenshot" ? "Explain this screenshot." : "Help me write " }
                        .buttonStyle(.plain).font(.callout).lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }.padding(.top, 4)
            if let error = chat.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
            Spacer()
        }.frame(maxWidth: .infinity).padding(18)
    }
}

/// Native multiline editing preserves normal selection, undo, and text paste.
private struct ChatEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Message Luna")
        scroll.documentView = editor
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatEditor
        init(_ parent: ChatEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}
