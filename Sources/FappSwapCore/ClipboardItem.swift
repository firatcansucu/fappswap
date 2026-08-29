import Foundation

/// One entry in the clipboard history. Text is stored inline; an image is a
/// reference to files the store owns, so `history.json` stays small.
public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public struct ImageRef: Codable, Equatable, Sendable {
        /// File names relative to the store's `images/` directory.
        public let fileName: String
        public let thumbnailFileName: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        /// Size of the full image file, kept here so the byte cap can be
        /// enforced without stat-ing files.
        public let byteCount: Int

        public init(fileName: String, thumbnailFileName: String,
                    pixelWidth: Int, pixelHeight: Int, byteCount: Int) {
            self.fileName = fileName
            self.thumbnailFileName = thumbnailFileName
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.byteCount = byteCount
        }
    }

    public enum Content: Codable, Equatable, Sendable {
        case text(String)
        case image(ImageRef)
    }

    public let id: UUID
    public let date: Date
    /// Bundle ID of the frontmost app when the item was captured; nil if unknown.
    public let sourceBundleID: String?
    public let content: Content

    public init(id: UUID = UUID(), date: Date, sourceBundleID: String?, content: Content) {
        self.id = id
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.content = content
    }

    public var text: String? {
        if case .text(let text) = content { return text }
        return nil
    }

    public var imageRef: ImageRef? {
        if case .image(let ref) = content { return ref }
        return nil
    }

    /// 0 for text items.
    public var imageByteCount: Int { imageRef?.byteCount ?? 0 }
}
