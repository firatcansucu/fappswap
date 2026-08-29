import Foundation
import Testing
@testable import FappSwapCore

@Test func clipboardTextItemRoundTripsThroughJSON() throws {
    let item = ClipboardItem(
        date: Date(timeIntervalSince1970: 1_000), sourceBundleID: "com.apple.Safari",
        content: .text("hello"))
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
    #expect(decoded == item)
    #expect(decoded.text == "hello")
    #expect(decoded.imageByteCount == 0)
}

@Test func clipboardImageItemRoundTripsThroughJSON() throws {
    let ref = ClipboardItem.ImageRef(
        fileName: "a.png", thumbnailFileName: "a.thumb.png",
        pixelWidth: 1280, pixelHeight: 800, byteCount: 4_096)
    let item = ClipboardItem(date: Date(timeIntervalSince1970: 5), sourceBundleID: nil, content: .image(ref))
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
    #expect(decoded == item)
    #expect(decoded.text == nil)
    #expect(decoded.imageByteCount == 4_096)
}

@Test func clipboardItemsGetDistinctIDsByDefault() {
    let a = ClipboardItem(date: Date(), sourceBundleID: nil, content: .text("a"))
    let b = ClipboardItem(date: Date(), sourceBundleID: nil, content: .text("a"))
    #expect(a.id != b.id)
}
