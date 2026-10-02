import Foundation

// Like Maccy's Storage, history stays in the app's local Application Support
// directory. Codable snapshots keep Cogi's existing bounded text model intact.
// https://github.com/p0deje/Maccy (see Resources/Maccy-LICENSE.txt).
final class ClipboardHistoryStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        let version: Int
        let items: [DetectedClipboardItem]
    }

    private enum ReadError: Error {
        case unsupportedVersion(Int)
    }

    private let queue = DispatchQueue(label: "com.anmoltanwar.Cogi.clipboard-history", qos: .utility)
    // All mutable store state is confined to the serial queue.
    private var canSave = false
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cogi", isDirectory: true)
        fileURL = directory.appendingPathComponent("clipboard-history.json")
    }

    func load(completion: @escaping @Sendable ([DetectedClipboardItem]) -> Void) {
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
        queue.async { [self] in
            guard canSave else { return }
            do {
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                let data = try JSONEncoder().encode(Snapshot(version: 1, items: items))
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
