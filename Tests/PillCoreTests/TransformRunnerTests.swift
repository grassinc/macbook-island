import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import PillCore

// These tests touch the real filesystem and run the real encoders. Transform
// code that "compiles" but writes a corrupt file is the failure mode worth
// catching, and only real bytes catch it.

private func makeImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func write(_ image: CGImage, to url: URL, type: UTType, properties: CFDictionary? = nil) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, properties)
    return CGImageDestinationFinalize(destination)
}

private func firstBytes(_ url: URL, _ count: Int) -> [UInt8] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return Array(data.prefix(count))
}

private func properties(of url: URL) -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return [:] }
    return props
}

private func pixelSize(of url: URL) -> (Int, Int) {
    let props = properties(of: url)
    return (props[kCGImagePropertyPixelWidth] as? Int ?? -1,
            props[kCGImagePropertyPixelHeight] as? Int ?? -1)
}

func runTransformRunnerTests(_ r: TestRunner) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pill-transform-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date()

    // A 2400px source so the 1600px resize has something to actually do.
    let png = root.appendingPathComponent("wide.png")
    guard write(makeImage(width: 2400, height: 1200), to: png, type: .png) else {
        r.expect(false, "could not create the PNG fixture"); return
    }

    r.test("resize writes a new file bounded by the max dimension") { r in
        guard let output = try? TransformRunner.run(.resize, on: ShelfItem(url: png, addedAt: now)) else {
            r.expect(false, "resize threw"); return
        }
        r.expect(FileManager.default.fileExists(atPath: output.path), "output exists")
        let (w, h) = pixelSize(of: output)
        r.expectEqual(w, 1600, "longest edge resized to 1600")
        r.expectEqual(h, 800, "aspect ratio preserved")
    }

    r.test("the original is never modified by a transform") { r in
        let (w, h) = pixelSize(of: png)
        r.expectEqual(w, 2400, "source width untouched")
        r.expectEqual(h, 1200, "source height untouched")
    }

    r.test("PDF conversion writes a real PDF") { r in
        guard let output = try? TransformRunner.run(.toPDF, on: ShelfItem(url: png, addedAt: now)) else {
            r.expect(false, "toPDF threw"); return
        }
        r.expectEqual(output.pathExtension, "pdf", "pdf extension")
        // %PDF
        r.expectEqual(firstBytes(output, 4), [0x25, 0x50, 0x44, 0x46], "file really starts with %PDF")
    }

    r.test("zip writes a real archive") { r in
        guard let output = try? TransformRunner.run(.zip, on: ShelfItem(url: png, addedAt: now)) else {
            r.expect(false, "zip threw"); return
        }
        // PK\003\004
        r.expectEqual(firstBytes(output, 2), [0x50, 0x4B], "file really starts with PK")
    }

    // The point of the feature: GPS and EXIF must actually be gone afterwards.
    r.test("stripping EXIF removes the GPS and EXIF blocks") { r in
        let jpeg = root.appendingPathComponent("tagged.jpg")
        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "camera secret"] as CFDictionary,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5,
                                            kCGImagePropertyGPSLongitude: 0.12] as CFDictionary,
        ]
        guard write(makeImage(width: 64, height: 64), to: jpeg, type: .jpeg,
                    properties: metadata as CFDictionary) else {
            r.expect(false, "could not create the tagged JPEG"); return
        }
        // Confirm the fixture really carries the metadata, or the test proves nothing.
        r.expect(properties(of: jpeg)[kCGImagePropertyGPSDictionary] != nil, "fixture has GPS to begin with")

        guard let output = try? TransformRunner.run(.stripEXIF, on: ShelfItem(url: jpeg, addedAt: now)) else {
            r.expect(false, "stripEXIF threw"); return
        }
        let cleaned = properties(of: output)
        r.expect(cleaned[kCGImagePropertyGPSDictionary] == nil, "GPS block is gone")

        // ImageIO REGENERATES structural EXIF on every encode (ColorSpace and
        // the pixel dimensions), so an empty EXIF dictionary is not achievable
        // and not the goal. What must be gone is anything identifying.
        let exif = (cleaned[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        r.expect(exif[kCGImagePropertyExifUserComment] == nil, "user comment is gone")
        let structural: Set<String> = ["ColorSpace", "PixelXDimension", "PixelYDimension"]
        let leftover = Set(exif.keys.map { $0 as String }).subtracting(structural)
        r.expect(leftover.isEmpty, "only structural EXIF survives, found extra: \(leftover.sorted())")

        r.expect(properties(of: jpeg)[kCGImagePropertyGPSDictionary] != nil, "the original keeps its GPS")
    }

    r.test("running the same transform twice does not overwrite the first result") { r in
        let item = ShelfItem(url: png, addedAt: now)
        guard let first = try? TransformRunner.run(.toPDF, on: item),
              let second = try? TransformRunner.run(.toPDF, on: item) else {
            r.expect(false, "repeat transform threw"); return
        }
        r.expect(first.path != second.path, "second run picks a fresh name")
        r.expect(FileManager.default.fileExists(atPath: first.path), "first result still there")
    }

    r.test("an unreadable file reports an error instead of crashing") { r in
        let bogus = root.appendingPathComponent("not-an-image.png")
        try? Data("definitely not a png".utf8).write(to: bogus)
        var threw = false
        do { _ = try TransformRunner.run(.resize, on: ShelfItem(url: bogus, addedAt: now)) }
        catch { threw = true }
        r.expect(threw, "garbage input throws rather than producing a broken file")
    }
}
