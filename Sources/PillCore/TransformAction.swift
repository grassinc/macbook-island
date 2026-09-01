import Foundation

/// An action offered when a file lands on the shelf.
///
/// Availability is decided by file type, and deliberately conservatively: an
/// action is only offered when it would genuinely do something. Offering
/// "Strip EXIF" on a PNG, which has no EXIF block, would be a lie the user only
/// discovers after tapping it.
public enum TransformAction: Equatable, Sendable, CaseIterable {
    case heicToJPEG
    case resize
    case stripEXIF
    case toPDF
    case zip

    public var title: String {
        switch self {
        case .heicToJPEG: "Convert to JPEG"
        case .resize:     "Resize"
        case .stripEXIF:  "Strip EXIF"
        case .toPDF:      "Convert to PDF"
        case .zip:        "Compress to ZIP"
        }
    }

    public var systemImage: String {
        switch self {
        case .heicToJPEG: "photo.on.rectangle.angled"
        case .resize:     "arrow.down.right.and.arrow.up.left"
        case .stripEXIF:  "location.slash"
        case .toPDF:      "doc.richtext"
        case .zip:        "archivebox"
        }
    }

    /// Raster formats we can decode and re-encode.
    private static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]

    /// Formats that actually carry an EXIF block.
    private static let exifExtensions: Set<String> =
        ["jpg", "jpeg", "heic", "heif", "tiff", "tif"]

    private static let heicExtensions: Set<String> = ["heic", "heif"]

    /// Ordered most-specific first, so the action a user most likely wants for
    /// this particular file leads the menu.
    public static func available(for item: ShelfItem) -> [TransformAction] {
        let ext = item.fileExtension
        var actions: [TransformAction] = []

        if heicExtensions.contains(ext) { actions.append(.heicToJPEG) }
        if imageExtensions.contains(ext) { actions.append(.resize) }
        if exifExtensions.contains(ext) { actions.append(.stripEXIF) }
        if imageExtensions.contains(ext) { actions.append(.toPDF) }
        actions.append(.zip)   // always possible

        return actions
    }
}
