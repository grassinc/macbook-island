import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Executes the drop-to-transform actions.
///
/// Every transform writes a NEW file beside the original and never modifies the
/// input. Dropping a file on a utility should not be able to destroy it.
public enum TransformRunner {

    public enum TransformError: LocalizedError {
        case unreadable(URL)
        case encodingFailed
        case zipFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let url): "Could not read \(url.lastPathComponent)"
            case .encodingFailed:      "Could not write the converted file"
            case .zipFailed(let code): "Compression failed (exit \(code))"
            }
        }
    }

    /// Longest edge used by `.resize`. A sensible default beats a modal asking
    /// for pixels every single time.
    public static let resizeMaxDimension: CGFloat = 1600

    public static func run(_ action: TransformAction, on item: ShelfItem) throws -> URL {
        switch action {
        case .heicToJPEG: try convertImage(item.url, to: .jpeg, suffix: "jpeg")
        case .stripEXIF:  try stripMetadata(item.url)
        case .toPDF:      try convertToPDF(item.url)
        case .resize:     try resize(item.url)
        case .zip:        try compress(item.url)
        }
    }

    // MARK: - Output naming

    /// Never overwrites: appends a counter until the name is free.
    private static func outputURL(for source: URL, suffix: String, ext: String) -> URL {
        let directory = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    // MARK: - Image transforms

    private static func imageSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw TransformError.unreadable(url)
        }
        return source
    }

    private static func convertImage(_ url: URL, to type: UTType, suffix: String) throws -> URL {
        let source = try imageSource(url)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TransformError.unreadable(url)
        }
        let output = outputURL(for: url, suffix: suffix, ext: type.preferredFilenameExtension ?? "jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, type.identifier as CFString, 1, nil) else {
            throw TransformError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TransformError.encodingFailed }
        return output
    }

    /// Re-encodes without the metadata dictionaries, which is what actually
    /// removes GPS and camera data — rewriting pixels alone would keep them.
    ///
    /// Note that ImageIO regenerates structural EXIF on encode (ColorSpace,
    /// PixelXDimension, PixelYDimension), so the output still carries a small
    /// EXIF block. Those fields are derivable from the pixels and identify
    /// nobody; everything personal — GPS, UserComment, camera body and lens —
    /// is gone. Verified by TransformRunnerTests.
    private static func stripMetadata(_ url: URL) throws -> URL {
        let source = try imageSource(url)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let type = CGImageSourceGetType(source) else {
            throw TransformError.unreadable(url)
        }
        let output = outputURL(for: url, suffix: "clean", ext: url.pathExtension)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
            throw TransformError.encodingFailed
        }
        // Explicitly blank the metadata containers rather than copying them over.
        let scrubbed: [CFString: Any] = [
            kCGImagePropertyExifDictionary: kCFNull as Any,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any,
            kCGImagePropertyTIFFDictionary: kCFNull as Any,
        ]
        CGImageDestinationAddImage(destination, image, scrubbed as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TransformError.encodingFailed }
        return output
    }

    private static func resize(_ url: URL) throws -> URL {
        let source = try imageSource(url)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: resizeMaxDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let type = CGImageSourceGetType(source) else {
            throw TransformError.unreadable(url)
        }
        let output = outputURL(for: url, suffix: "\(Int(resizeMaxDimension))px", ext: url.pathExtension)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
            throw TransformError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TransformError.encodingFailed }
        return output
    }

    private static func convertToPDF(_ url: URL) throws -> URL {
        let source = try imageSource(url)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TransformError.unreadable(url)
        }
        let output = outputURL(for: url, suffix: "converted", ext: "pdf")

        // One page, sized to the image's own pixel dimensions.
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw TransformError.encodingFailed
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return output
    }

    // MARK: - Compression

    /// `ditto` is used rather than hand-rolling an archive: it is on every macOS
    /// install and produces archives Finder opens without complaint.
    private static func compress(_ url: URL) throws -> URL {
        let output = outputURL(for: url, suffix: "archive", ext: "zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TransformError.zipFailed(process.terminationStatus)
        }
        return output
    }
}
