import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func item(_ path: String) -> ShelfItem {
    ShelfItem(url: URL(fileURLWithPath: path), addedAt: t0)
}

func runTransformTests(_ r: TestRunner) {

    r.test("anything at all can be zipped") { r in
        r.expect(TransformAction.available(for: item("/tmp/notes.txt")).contains(.zip), "text zips")
        r.expect(TransformAction.available(for: item("/tmp/a.heic")).contains(.zip), "images zip")
        r.expect(TransformAction.available(for: item("/tmp/weird.xyz")).contains(.zip), "unknown types zip")
    }

    r.test("HEIC conversion is offered only for HEIC") { r in
        r.expect(TransformAction.available(for: item("/tmp/a.heic")).contains(.heicToJPEG), "heic converts")
        r.expect(TransformAction.available(for: item("/tmp/a.HEIC")).contains(.heicToJPEG), "case-insensitive")
        r.expect(TransformAction.available(for: item("/tmp/a.jpg")).contains(.heicToJPEG) == false,
                 "a JPEG is already a JPEG")
    }

    r.test("resize and PDF conversion are offered for images only") { r in
        let png = TransformAction.available(for: item("/tmp/a.png"))
        r.expect(png.contains(.resize), "png resizes")
        r.expect(png.contains(.toPDF), "png converts to pdf")

        let txt = TransformAction.available(for: item("/tmp/a.txt"))
        r.expect(txt.contains(.resize) == false, "text does not resize")
        r.expect(txt.contains(.toPDF) == false, "text is not offered image-to-pdf")
    }

    // Offering "strip EXIF" on a PNG would be a lie: PNG carries no EXIF block.
    r.test("EXIF stripping is offered only for formats that carry EXIF") { r in
        r.expect(TransformAction.available(for: item("/tmp/a.jpg")).contains(.stripEXIF), "jpeg carries EXIF")
        r.expect(TransformAction.available(for: item("/tmp/a.heic")).contains(.stripEXIF), "heic carries EXIF")
        r.expect(TransformAction.available(for: item("/tmp/a.png")).contains(.stripEXIF) == false,
                 "png has no EXIF block to strip")
    }

    r.test("a file with no extension still offers zip and nothing bogus") { r in
        let actions = TransformAction.available(for: item("/tmp/Makefile"))
        r.expectEqual(actions, [.zip], "only zip is honest here")
    }

    r.test("actions come back in a stable order") { r in
        let first = TransformAction.available(for: item("/tmp/a.heic"))
        let second = TransformAction.available(for: item("/tmp/a.heic"))
        r.expectEqual(first, second, "ordering is deterministic")
        r.expectEqual(first.first, .heicToJPEG, "the most specific action leads")
    }

    r.test("every action has a label for the menu") { r in
        for action in TransformAction.allCases {
            r.expect(action.title.isEmpty == false, "\(action) has a title")
        }
    }
}
