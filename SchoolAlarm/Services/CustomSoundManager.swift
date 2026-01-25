import Foundation
import AVFoundation

/// Manages custom alarm sound file import, storage, and retrieval
class CustomSoundManager {
    static let shared = CustomSoundManager()

    private let maxFileSize = 10 * 1024 * 1024  // 10MB

    private init() {
        createSoundsDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    private var soundsDirectory: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return library.appendingPathComponent("Sounds")
    }

    private func createSoundsDirectoryIfNeeded() {
        guard let soundsDirectory else { return }
        try? FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    /// Returns URL of current custom sound, nil if none imported
    func customSoundURL() -> URL? {
        guard let soundsDirectory,
              let filename = customSoundFilename() else { return nil }
        let url = soundsDirectory.appendingPathComponent(filename)
        // Verify file actually exists before returning
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Returns filename of current custom sound, nil if none imported
    func customSoundFilename() -> String? {
        guard let soundsDirectory else { return nil }
        let contents = try? FileManager.default.contentsOfDirectory(at: soundsDirectory, includingPropertiesForKeys: nil)
        return contents?.first?.lastPathComponent
    }

    /// Import sound from document picker URL
    /// - Returns: filename on success
    /// - Throws: CustomSoundError on failure
    func importSound(from sourceURL: URL) async throws -> String {
        guard let soundsDirectory else {
            throw CustomSoundError.copyFailed
        }

        // Start accessing security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw CustomSoundError.accessDenied
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize <= maxFileSize else {
            throw CustomSoundError.fileTooLarge
        }

        // Validate playability
        do {
            let player = try AVAudioPlayer(contentsOf: sourceURL)
            // Just creating player validates the file
            _ = player.duration
        } catch {
            throw CustomSoundError.notPlayable
        }

        // Delete existing custom sound
        deleteCustomSound()

        // Copy to app storage
        let filename = sourceURL.lastPathComponent
        let destinationURL = soundsDirectory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw CustomSoundError.copyFailed
        }

        return filename
    }

    /// Delete current custom sound
    func deleteCustomSound() {
        guard let url = customSoundURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum CustomSoundError: LocalizedError {
    case accessDenied
    case fileTooLarge
    case notPlayable
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the selected file"
        case .fileTooLarge:
            return "File is too large (max 10MB)"
        case .notPlayable:
            return "Cannot play this audio file"
        case .copyFailed:
            return "Failed to save the sound"
        }
    }
}
