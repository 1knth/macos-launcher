import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

struct MetadataRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.vertical, 3.5)
    }
}

struct MetadataList: View {
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information").font(.system(size: 12, weight: .semibold)).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().opacity(0.5) }
                MetadataRow(label: row.0, value: row.1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: Files

struct FileDetail: View {
    let url: URL
    @State private var loaded: Loaded?

    struct Loaded {
        var image: NSImage?
        var text: String?
        var listing: [String]?
        var rows: [(String, String)] = []
        var isThumbnail = false
    }

    var body: some View {
        VStack(spacing: 0) {
            preview.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
            Divider()
            MetadataList(rows: loaded?.rows ?? [("Name", url.lastPathComponent)])
        }
        .task(id: url) {
            loaded = nil
            let url = url
            let result = await Task.detached(priority: .userInitiated) { await FileDetail.load(url) }.value
            if !Task.isCancelled { loaded = result }
        }
    }

    @ViewBuilder private var preview: some View {
        if let text = loaded?.text {
            ScrollView {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
        } else if let listing = loaded?.listing {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(listing, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(nsImage: IconCache.icon(url.appendingPathComponent(name).path)).resizable().frame(width: 16, height: 16)
                            Text(name).font(.system(size: 12)).lineLimit(1)
                        }
                    }
                    if listing.isEmpty { Text("Empty folder").font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        } else if let image = loaded?.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: loaded?.isThumbnail == true ? 180 : .infinity, maxHeight: loaded?.isThumbnail == true ? 180 : .infinity)
                .shadow(color: .black.opacity(loaded?.isThumbnail == true ? 0 : 0.15), radius: 6, y: 2)
                .padding(16)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    static func load(_ url: URL) async -> Loaded {
        var result = Loaded()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        result.rows.append(("Name", url.lastPathComponent))
        result.rows.append(("Kind", values?.localizedTypeDescription ?? "File"))
        if values?.isDirectory != true, let size = values?.totalFileSize ?? values?.fileSize {
            result.rows.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let modified = values?.contentModificationDate { result.rows.append(("Modified", dateFormatter.string(from: modified))) }
        result.rows.append(("Where", (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))

        if values?.isDirectory == true, url.pathExtension != "app" {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            result.listing = names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(60).map { $0 }
            result.rows.insert(("Items", "\(names.filter { !$0.hasPrefix(".") }.count)"), at: 2)
            return result
        }
        if FileKind.isImage(url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                result.image = NSImage(cgImage: thumbnail, size: .zero)
            }
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
                result.rows.insert(("Dimensions", "\(width) × \(height)"), at: 2)
            }
            if result.image != nil { return result }
        }
        if FileKind.isText(url), let handle = try? FileHandle(forReadingFrom: url) {
            let data = (try? handle.read(upToCount: 48_000)) ?? Data()
            try? handle.close()
            // NUL bytes mean binary content (binary plists, etc.).
            if !data.contains(0) {
                let text = String(decoding: data, as: UTF8.self)
                result.text = text.isEmpty ? "Empty file" : text
                result.rows.insert(("Lines", "\(text.split(separator: "\n", omittingEmptySubsequences: false).count)\(data.count >= 48_000 ? "+" : "")"), at: 2)
                return result
            }
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 512, height: 512), scale: 2, representationTypes: .all)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            result.image = representation.nsImage
            result.isThumbnail = representation.type == .icon
        } else {
            result.image = NSWorkspace.shared.icon(forFile: url.path)
            result.isThumbnail = true
        }
        return result
    }
}

// MARK: Clipboard

struct ClipDetail: View {
    let clip: ClipItem

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            MetadataList(rows: rows)
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            if let image = AppServices.shared.clipboard.image(for: clip) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(16)
            } else {
                Text("Image unavailable").foregroundStyle(.secondary)
            }
        case .color:
            let color = NSColor(hex: clip.text ?? "") ?? .clear
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: color))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                    .frame(width: 140, height: 140)
                Text(clip.text ?? "").font(.system(size: 15, weight: .medium, design: .monospaced))
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(clip.filePaths ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.icon(path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent).font(.system(size: 12.5))
                                Text((path as NSString).abbreviatingWithTildeInPath).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        default:
            ScrollView {
                Text(String((clip.text ?? "").prefix(20_000)))
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if let app = clip.sourceApp { rows.append(("Application", app)) }
        rows.append(("Content type", clip.kind.rawValue.capitalized))
        if let text = clip.text, clip.kind != .image {
            rows.append(("Characters", "\(text.count)"))
            rows.append(("Words", "\(text.split { $0.isWhitespace || $0.isNewline }.count)"))
        }
        if let size = clip.imageSize { rows.append(("Dimensions", "\(Int(size.width)) × \(Int(size.height))")) }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        rows.append(("Copied", formatter.string(from: clip.date)))
        return rows
    }
}
