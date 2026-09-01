import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import PillCore

/// Bounded thumbnails via ImageIO, with the Finder icon as fallback.
///
/// Decoding a full 48-megapixel image to draw a 44pt tile would stall the panel,
/// so images go through a size-capped thumbnail request instead.
@MainActor
enum Thumbnail {
    private static var cache: [String: NSImage] = [:]

    static func image(for item: ShelfItem, side: CGFloat) -> NSImage {
        if let hit = cache[item.id] { return hit }
        let result = make(item, side: side)
        cache[item.id] = result
        return result
    }

    private static func make(_ item: ShelfItem, side: CGFloat) -> NSImage {
        let pixels = side * 2   // Retina
        if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: pixels,
           ] as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        }
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: side, height: side)
        return icon
    }
}

struct ShelfStrip: View {
    @ObservedObject var shelf: ShelfObservable
    let onTransform: (TransformAction, ShelfItem) -> Void
    let onRemove: (ShelfItem) -> Void
    let onClear: () -> Void
    let onDragStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Shelf")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if let error = shelf.lastError {
                Text(error)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            well {
                if shelf.items.isEmpty {
                    Text(shelf.isDropTargeted ? "Release to park" : "Drop files here")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(shelf.isDropTargeted ? 0.85 : 0.38))
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item,
                                          onTransform: { onTransform($0, item) },
                                          onRemove: { onRemove(item) },
                                          onDragStart: onDragStart)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                }
            }
        }
    }

    /// The bordered tray the sketch draws: one constant shape whether it holds
    /// files or an invitation, so nothing about the panel moves when a file
    /// lands on it.
    private func well<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(shelf.isDropTargeted ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(shelf.isDropTargeted ? 0.5 : 0.12),
                                  lineWidth: shelf.isDropTargeted ? 1 : 0.5)
            )
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let onTransform: (TransformAction) -> Void
    let onRemove: () -> Void
    let onDragStart: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: Thumbnail.image(for: item, side: 30))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(item.name)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 52)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hovering ? 0.12 : 0.05))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
            }
        }
        .onHover { hovering = $0 }
        // Drag straight back out to any app: Finder, Mail, WhatsApp, anything
        // that accepts a file. The provider hands over the file URL, which is
        // what those apps expect for an attachment.
        .onDrag {
            onDragStart()
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            ForEach(TransformAction.available(for: item), id: \.self) { action in
                Button {
                    onTransform(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Remove", role: .destructive, action: onRemove)
        }
        .help("\(item.name) — drag out, or right-click for actions")
    }
}
