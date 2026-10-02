import Foundation

// The version-1 JSON representation remains text-only and compatible with
// existing saved histories. Image items cannot be encoded by this DTO.
struct PersistedClipboardItem: Codable, Sendable {
    let id: UUID
    let text: String
    let detectedAt: Date
    let lastCopiedAt: Date
    let foregroundApplicationName: String?
    let characterCount: Int
    let copyCount: Int
    let isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case id, text, detectedAt, lastCopiedAt, foregroundApplicationName, characterCount, copyCount, isPinned
    }

    private enum ImageKeys: String, CodingKey {
        case image, imageData, thumbnailData, pasteboardType, type
    }

    init?(_ item: DetectedClipboardItem) {
        guard item.image == nil, !item.text.isEmpty else { return nil }
        id = item.id
        text = item.text
        detectedAt = item.detectedAt
        lastCopiedAt = item.lastCopiedAt
        foregroundApplicationName = item.foregroundApplicationName
        characterCount = item.characterCount
        copyCount = item.copyCount
        isPinned = item.isPinned
    }

    init(from decoder: Decoder) throws {
        let imageKeys = try decoder.container(keyedBy: ImageKeys.self)
        let type = try imageKeys.decodeIfPresent(String.self, forKey: .type)
        guard !imageKeys.contains(.image), !imageKeys.contains(.imageData),
              !imageKeys.contains(.thumbnailData), !imageKeys.contains(.pasteboardType),
              type == nil || type == "text" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Only text history may be restored."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        detectedAt = try values.decode(Date.self, forKey: .detectedAt)
        lastCopiedAt = try values.decode(Date.self, forKey: .lastCopiedAt)
        foregroundApplicationName = try values.decodeIfPresent(String.self, forKey: .foregroundApplicationName)
        characterCount = try values.decode(Int.self, forKey: .characterCount)
        copyCount = try values.decode(Int.self, forKey: .copyCount)
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
    }
}

// Like Maccy's Storage, history stays in the app's local Application Support
// directory. Codable snapshots keep Cogi's existing bounded text model intact.
// https://github.com/p0deje/Maccy (see Resources/Maccy-LICENSE.txt).
final class ClipboardHistoryStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        let version: Int
        let items: [PersistedClipboardItem]
    }

    private enum ReadError: Error {
        case unsupportedVersion(Int)
    }

    private let queue = DispatchQueue(label: "com.anmoltanwar.cogi.clipboard-history", qos: .utility)
    // All mutable store state is confined to the serial queue.
    private var canSave = false
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cogi", isDirectory: true)
        fileURL = directory.appendingPathComponent("clipboard-history.json")
    }

    func load(completion: @escaping @Sendable ([PersistedClipboardItem]) -> Void) {
        queue.async { [self] in
            do {
                let data = try Data(contentsOf: fileURL)
                do {
                    let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                    guard snapshot.version == 1 else {
                        throw ReadError.unsupportedVersion(snapshot.version)
                    }
                    canSave = true
                    completion(snapshot.items)
                } catch {
                    // Preserve unreadable data before allowing a fresh history.
                    let backup = fileURL.deletingLastPathComponent()
                        .appendingPathComponent("clipboard-history-unreadable-\(UUID().uuidString).json")
                    do {
                        try FileManager.default.moveItem(at: fileURL, to: backup)
                        canSave = true
                        NSLog("[Cogi] Unreadable clipboard history preserved at %@: %@", backup.path, error.localizedDescription)
                    } catch {
                        canSave = false
                        NSLog("[Cogi] Could not preserve unreadable clipboard history; saving is disabled: %@", error.localizedDescription)
                    }
                    completion([])
                }
            } catch {
                let failure = error as NSError
                canSave = failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError
                if !canSave {
                    NSLog("[Cogi] Could not read clipboard history; saving is disabled: %@", failure.localizedDescription)
                }
                completion([])
            }
        }
    }

    func save(_ items: [DetectedClipboardItem]) {
        let textItems = items.compactMap(PersistedClipboardItem.init)
        queue.async { [self] in
            guard canSave else { return }
            do {
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                let data = try JSONEncoder().encode(Snapshot(version: 1, items: textItems))
                try data.write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            } catch {
                NSLog("[Cogi] Could not save clipboard history: %@", error.localizedDescription)
            }
        }
    }

    func flush() {
        // Called only during termination, after clipboard monitoring stops.
        // Ordinary reads, serialization and writes stay off the UI thread.
        queue.sync {}
    }
}
