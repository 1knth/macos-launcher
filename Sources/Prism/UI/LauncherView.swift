import AppKit
import ImageIO
import SwiftUI

/// Hairline separator that reads like the system's in both appearances.
struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

struct LauncherView: View {
    @ObservedObject var state: LauncherState

    static let size = CGSize(width: 750, height: 474)

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Hairline()
            footer
        }
        .overlay(alignment: .topTrailing) {
            if !state.route.hasDetail, !state.showActions, let item = state.hoveredItem, let source = HoverPreview.source(for: item) {
                HoverPreview(source: source)
                    .padding(.top, 66)
                    .padding(.trailing, 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if state.showActions, let item = state.actionItem {
                ActionPanel(item: item, selection: state.actionSelection) { action in state.perform(action, on: item) }
                    .padding(.trailing, 10)
                    .padding(.bottom, 44)
            }
        }
        .background {
            #if canImport(Translation)
            if #available(macOS 15, *) { TranslationHost(translator: state.selected.translator) }
            #endif
        }
        .animation(.easeOut(duration: 0.1), value: state.hoverID)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if state.route != .root {
                Button { state.pop() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Back (Esc)")
            }
            if state.route.hasSearchField {
                SearchField(text: $state.query, placeholder: state.route.placeholder, focusToken: state.focusToken)
                    .frame(height: 26)
            } else {
                Text(state.route.title).font(.system(size: 16, weight: .medium))
                Spacer()
            }
            if state.route == .files {
                Button { state.files.toggleContentMode() } label: {
                    Text(state.files.contentMode ? "Names & Contents" : "Names")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Toggle content search (⌘T)")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherPanel.dragRegionHeight)
    }

    @ViewBuilder private var content: some View {
        if state.route == .chat {
            ChatView(chat: state.chat, draft: $state.query)
        } else if state.route == .usage {
            UsageView()
        } else if state.route == .colorWheel {
            ColorWheelView(wheel: state.colorWheel)
        } else if state.items.isEmpty {
            EmptyState(route: state.route, query: state.query)
        } else if state.route.hasDetail {
            HStack(spacing: 0) {
                ResultList(state: state).frame(width: 320)
                Hairline(vertical: true)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ResultList(state: state)
        }
    }

    @ViewBuilder private var detail: some View {
        switch state.selectedItem?.preview {
        case .file(let url): FileDetail(url: url).id(url)
        case .clip(let clip): ClipDetail(clip: clip).id(clip.id)
        default: Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let flash = state.flashMessage {
                Image(systemName: flash.symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.green)
                Text(flash.text).font(.system(size: 12, weight: .medium)).lineLimit(1)
            } else if state.route != .root {
                if state.route != .usage { IconView(icon: state.route.icon, size: 15) }
                Text(state.route.title).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { SettingsController.shared.show() } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Open Settings")
            Hairline(vertical: true).frame(height: 14).padding(.horizontal, 2)
            if let item = state.actionItem, let primary = item.actions.first {
                Button { state.perform(primary, on: item) } label: {
                    HStack(spacing: 6) {
                        Text(primary.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                        KeyCap(text: "↩")
                    }
                }
                .buttonStyle(.plain)
                Hairline(vertical: true).frame(height: 14).padding(.horizontal, 2)
                Button { if state.showActions { state.showActions = false } else { state.openActions() } } label: {
                    HStack(spacing: 6) {
                        Text("Actions").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        KeyCap(text: "⌘")
                        KeyCap(text: "K")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: LauncherPanel.footerHeight)
        .background(Color.primary.opacity(0.02))
    }
}

struct ResultList: View {
    @ObservedObject var state: LauncherState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || state.items[index - 1].section != item.section, !item.section.isEmpty {
                            SectionHeader(title: item.section)
                        }
                        ResultRow(item: item, selected: index == state.selection)
                            .id(item.id)
                            .onHover { inside in state.hover(item.id, inside: inside) }
                            .onTapGesture { state.selection = index }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if let primary = item.actions.first { state.perform(primary, on: item) }
                            })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: state.selection) { _, _ in
                guard let item = state.selectedItem else { return }
                proxy.scrollTo(item.id)
            }
            .onChange(of: state.route) { _, _ in
                if let first = state.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }
}

/// Floating thumbnail shown while hovering an image in the root search.
struct HoverPreview: View {
    enum Source: Equatable {
        case file(URL)
        case clip(ClipItem)
    }

    let source: Source
    @State private var image: NSImage?

    static func source(for item: ResultItem) -> Source? {
        switch item.preview {
        case .file(let url) where FileKind.isImage(url): return .file(url)
        case .clip(let clip) where clip.kind == .image: return .clip(clip)
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ProgressView().controlSize(.small).frame(width: 60, height: 60)
            }
        }
        .frame(maxWidth: 240, maxHeight: 240)
        .padding(6)
        .background(VisualEffect(material: .popover, blending: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .task(id: source) {
            image = nil
            let source = source
            image = await Task.detached(priority: .userInitiated) { HoverPreview.load(source) }.value
        }
    }

    nonisolated static func load(_ source: Source) -> NSImage? {
        switch source {
        case .clip(let clip): return AppServices.shared.clipboard.image(for: clip)
        case .file(let url):
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 520,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary).map { NSImage(cgImage: $0, size: .zero) }
        }
    }
}

struct ActionPanel: View {
    let item: ResultItem
    let selection: Int
    let perform: (ItemAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 5)
            ForEach(Array(item.actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: 9) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 12))
                        .frame(width: 18)
                        .foregroundStyle(action.destructive ? Color.red : .secondary)
                    Text(action.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(action.destructive ? Color.red : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if let shortcut = action.shortcut { ShortcutCaps(combo: shortcut) }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(index == selection ? Color.primary.opacity(0.09) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { perform(action) }
                .padding(.horizontal, 5)
            }
        }
        .padding(.bottom, 5)
        .frame(width: 310)
        .background(VisualEffect(material: .popover, blending: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

struct EmptyState: View {
    let route: Route
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            IconView(icon: route.icon, size: 34).opacity(0.8)
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.top, 4)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch route {
        case .google: return "Search Google"
        case .clipboard: return query.isEmpty ? "Nothing copied yet" : "No matches"
        case .files: return query.isEmpty ? "No recent files" : "No matching files"
        case .colors: return "No saved colors"
        case .windows: return "No open windows"
        case .menuItems: return Accessibility.trusted ? "No menu items" : "Accessibility access needed"
        case .transform: return NSPasteboard.general.string(forType: .string) != nil ? "No matching transforms" : "Clipboard has no text"
        default: return "No results"
        }
    }

    private var message: String {
        switch route {
        case .google: return "Type a search and press Return to open it in your default browser."
        case .clipboard: return "Text, links, images and files you copy will appear here. Password managers’ concealed copies are skipped."
        case .menuItems where !Accessibility.trusted: return "Grant Accessibility access in Settings to search the frontmost app’s menus."
        case .files: return "Try kind:image, kind:pdf, ext:swift, or toggle content search with ⌘T."
        default: return "Try a different search."
        }
    }
}
