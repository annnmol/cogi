import Foundation
import ImageIO

// Image bytes and thumbnail bytes remain in memory. This type intentionally has
// no Codable conformance and is never part of a persistence snapshot.
struct TemporaryClipboardImage: Sendable {
    static let maximumDataSize = 64 * 1024 * 1024
    static let maximumHistoryDataSize = 256 * 1024 * 1024

    let data: Data
    let pasteboardType: String
    let thumbnailData: Data
    let width: Int
    let height: Int

    static func make(data: Data, pasteboardType: String) -> TemporaryClipboardImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              width <= 64_000_000 / height else { return nil }

        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: 160,
            kCGImageSourceShouldCacheImmediately as String: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return TemporaryClipboardImage(data: data, pasteboardType: pasteboardType,
                                       thumbnailData: buffer as Data, width: width, height: height)
    }
}
