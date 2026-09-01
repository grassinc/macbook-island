import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ o: TimeInterval) -> Date { t0.addingTimeInterval(o) }

private func item(_ path: String, _ when: Date, source: ShelfItemSource = .dropped) -> ShelfItem {
    ShelfItem(url: URL(fileURLWithPath: path), addedAt: when, source: source)
}

func runShelfTests(_ r: TestRunner) {

    r.test("an added file is held in the shelf") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/report.pdf", t0))
        r.expectEqual(shelf.items.count, 1, "one item held")
        r.expectEqual(shelf.items.first?.name, "report.pdf", "name comes from the last path component")
    }

    r.test("the newest item is first") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/old.txt", t0))
        shelf.add(item("/tmp/new.txt", at(5)))
        r.expectEqual(shelf.items.first?.name, "new.txt", "newest leads")
    }

    // Dropping the same file twice is a normal accident; it must not produce
    // two identical tiles.
    r.test("re-adding the same file moves it to the front rather than duplicating") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/a.txt", t0))
        shelf.add(item("/tmp/b.txt", at(1)))
        shelf.add(item("/tmp/a.txt", at(2)))
        r.expectEqual(shelf.items.count, 2, "no duplicate tile")
        r.expectEqual(shelf.items.first?.name, "a.txt", "re-added file returns to the front")
    }

    r.test("the oldest item is dropped when capacity is exceeded") { r in
        let shelf = ShelfStore(capacity: 2)
        shelf.add(item("/tmp/1.txt", t0))
        shelf.add(item("/tmp/2.txt", at(1)))
        shelf.add(item("/tmp/3.txt", at(2)))
        r.expectEqual(shelf.items.count, 2, "capacity respected")
        r.expect(shelf.items.contains { $0.name == "1.txt" } == false, "oldest evicted")
        r.expectEqual(shelf.items.first?.name, "3.txt", "newest still leads")
    }

    r.test("an item can be removed by id") { r in
        let shelf = ShelfStore(capacity: 10)
        let one = item("/tmp/a.txt", t0)
        shelf.add(one)
        shelf.add(item("/tmp/b.txt", at(1)))
        shelf.remove(id: one.id)
        r.expectEqual(shelf.items.count, 1, "one removed")
        r.expectEqual(shelf.items.first?.name, "b.txt", "the right one survived")
    }

    r.test("clearing empties the shelf") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/a.txt", t0))
        shelf.clear()
        r.expect(shelf.items.isEmpty, "shelf emptied")
    }

    // Identity is the file path, so the same file added from two sources is one
    // item -- a screenshot dragged back in should not become a second tile.
    r.test("identity is the file path, independent of source") { r in
        let dropped = item("/tmp/shot.png", t0, source: .dropped)
        let captured = item("/tmp/shot.png", at(1), source: .screenshot)
        r.expectEqual(dropped.id, captured.id, "same path means same item")
    }

    r.test("the shelf reports whether it has anything to show") { r in
        let shelf = ShelfStore(capacity: 5)
        r.expect(shelf.isEmpty, "starts empty")
        shelf.add(item("/tmp/a.txt", t0))
        r.expect(shelf.isEmpty == false, "not empty after an add")
    }

    r.test("a change handler fires when the shelf mutates") { r in
        let shelf = ShelfStore(capacity: 5)
        var changes = 0
        shelf.onChange = { changes += 1 }
        shelf.add(item("/tmp/a.txt", t0))
        shelf.remove(id: item("/tmp/a.txt", t0).id)
        r.expectEqual(changes, 2, "add and remove each notify")
    }

    // A parked file can be moved, renamed, or deleted behind our back. A tile
    // pointing at nothing would fail silently when dragged into another app,
    // which is the worst way to find out.
    r.test("items whose files have vanished are pruned") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/present.txt", t0))
        shelf.add(item("/tmp/gone.txt", at(1)))

        shelf.pruneMissing { url in url.path == "/tmp/present.txt" }

        r.expectEqual(shelf.items.count, 1, "the vanished file is dropped")
        r.expectEqual(shelf.items.first?.name, "present.txt", "the surviving file is kept")
    }

    r.test("pruning notifies only when something actually went") { r in
        let shelf = ShelfStore(capacity: 10)
        shelf.add(item("/tmp/present.txt", t0))
        var changes = 0
        shelf.onChange = { changes += 1 }

        shelf.pruneMissing { _ in true }
        r.expectEqual(changes, 0, "nothing missing means no notification")

        shelf.pruneMissing { _ in false }
        r.expectEqual(changes, 1, "a removal notifies once")
    }

    // Parked files must survive quitting Pill and rebooting the Mac. Without
    // this the shelf is a scratchpad that silently empties overnight.
    r.test("shelf items survive an encode/decode round trip") { r in
        let original = [item("/tmp/a.pdf", t0), item("/tmp/shot.png", at(3), source: .screenshot)]
        guard let data = try? JSONEncoder().encode(original),
              let restored = try? JSONDecoder().decode([ShelfItem].self, from: data) else {
            r.expect(false, "round trip threw"); return
        }
        r.expectEqual(restored.count, 2, "both items came back")
        r.expectEqual(restored.first?.name, "a.pdf", "url survived")
        r.expect(restored.last?.source == .screenshot, "source survived")
        r.expectEqual(restored.first?.id, original.first?.id, "identity is stable across a restart")
    }

    r.test("a restored shelf keeps newest-first order and honours capacity") { r in
        let shelf = ShelfStore(capacity: 2)
        shelf.restore([item("/tmp/1.txt", t0), item("/tmp/2.txt", at(1)), item("/tmp/3.txt", at(2))])
        r.expectEqual(shelf.items.count, 2, "capacity applied on restore, not just on add")
        r.expectEqual(shelf.items.first?.name, "1.txt", "restore preserves the given order")
    }

    r.test("restoring does not fire onChange") { r in
        // Restore happens at launch; treating it as a mutation would write the
        // file straight back out for no reason.
        let shelf = ShelfStore(capacity: 5)
        var changes = 0
        shelf.onChange = { changes += 1 }
        shelf.restore([item("/tmp/a.txt", t0)])
        r.expectEqual(changes, 0, "restore is not a user-visible change")
    }
}
