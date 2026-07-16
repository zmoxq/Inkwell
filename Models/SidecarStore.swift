// =============================================================================
// SidecarStore.swift
// =============================================================================
//
// Stateless read/write service for sidecar files (P.md.json), implementing
// the Inkwell side of the write protocol in PHASE_4_SIDECAR_SCHEMA.md §4:
// read whole file → patch only Inkwell-owned layers → atomic write-back.
// Every operation takes the markdown URL and hits disk; no in-memory cache.
//
// V1 scope (§4): protocol steps 1, 2, 4. Step 3 (mtime conflict retry) is a
// contract clause for future multi-writer scenarios, deliberately not
// implemented while Inkwell is the only writer.
// -----------------------------------------------------------------------------

import CryptoKit
import Foundation

/// Highest sidecar schema version this build can safely write.
private let supportedSchemaVersion = 1

enum SidecarError: Error, Equatable {
    /// File exists but is not a JSON object, or schemaVersion is missing /
    /// not an integer. Never overwritten: the file may hold data from other
    /// writers that we must not destroy.
    case malformed
    /// schemaVersion is newer than this build supports; sidecar is read-only.
    case unsupportedSchemaVersion(Int)
}

/// Result of reading a note's sidecar.
enum SidecarReadState {
    /// No sidecar file on disk (lazy creation hasn't happened yet).
    case absent
    /// Parsed and writable.
    case writable(SidecarDocument)
    /// schemaVersion is newer than this build supports: content is exposed
    /// for display, but every write is rejected (§3 top-level table).
    case readOnly(SidecarDocument, schemaVersion: Int)
}

enum SidecarStore {

    // MARK: - File binding (§2)

    /// Sidecar for `P.md` is `P.md.json` in the same directory.
    static func sidecarURL(forMarkdownAt markdownURL: URL) -> URL {
        markdownURL.appendingPathExtension("json")
    }

    // MARK: - Reading

    /// Reads and classifies the sidecar for the given note.
    /// Throws `SidecarError.malformed` for undecodable content; never
    /// throws for a missing file (that is the `.absent` state).
    static func read(forMarkdownAt markdownURL: URL) throws -> SidecarReadState {
        let url = sidecarURL(forMarkdownAt: markdownURL)
        guard let data = try? Data(contentsOf: url) else {
            return .absent
        }
        guard let document = SidecarDocument(jsonData: data),
              let version = document.schemaVersion else {
            throw SidecarError.malformed
        }
        if version > supportedSchemaVersion {
            return .readOnly(document, schemaVersion: version)
        }
        return .writable(document)
    }

    // MARK: - Content hash (§3 system layer)

    /// `"sha256:" + lowercase hex` over the note's on-disk bytes.
    static func contentHash(of markdownData: Data) -> String {
        let digest = SHA256.hash(data: markdownData)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Writing (§4 steps 1, 2, 4)

    /// Replaces `user.tags`. Lazily creates the sidecar on first metadata
    /// write (§2), with a complete `system` layer from birth.
    static func setTags(_ tags: [String], forMarkdownAt markdownURL: URL, now: Date = Date()) throws {
        var document: SidecarDocument
        switch try read(forMarkdownAt: markdownURL) {
        case .absent:
            document = try makeNewDocument(forMarkdownAt: markdownURL, now: now)
        case .writable(let existing):
            document = existing
        case .readOnly(_, let version):
            throw SidecarError.unsupportedSchemaVersion(version)
        }
        document.setTags(tags)
        try write(document, forMarkdownAt: markdownURL)
    }

    /// Updates `system.contentHash` / `system.modifiedAt` after a content
    /// save (§6). Deliberately does NOT lazily create: a content save alone
    /// is not a metadata write — creating here would produce a sidecar for
    /// every note ever saved, defeating lazy creation (§2).
    static func recordContentSave(markdownData: Data, forMarkdownAt markdownURL: URL, now: Date = Date()) throws {
        switch try read(forMarkdownAt: markdownURL) {
        case .absent:
            return
        case .writable(var document):
            document.updateSystem(contentHash: contentHash(of: markdownData), modifiedAt: isoTimestamp(now))
            try write(document, forMarkdownAt: markdownURL)
        case .readOnly(_, let version):
            throw SidecarError.unsupportedSchemaVersion(version)
        }
    }

    // MARK: - Atomic write (§4 step 4)

    /// Serializes and atomically replaces the sidecar file.
    /// Internal so tests can drive the stage/commit seam separately.
    static func write(_ document: SidecarDocument, forMarkdownAt markdownURL: URL) throws {
        let destination = sidecarURL(forMarkdownAt: markdownURL)
        let staged = try stageWrite(document.jsonData(), to: destination)
        try commitStagedWrite(from: staged, to: destination)
    }

    /// Stage: write the full payload to a temp file in the destination's
    /// directory (same volume, so the rename in commit stays atomic).
    /// An interruption after this step leaves the destination untouched.
    static func stageWrite(_ data: Data, to destination: URL) throws -> URL {
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".tmp-" + UUID().uuidString)
        try data.write(to: tempURL)
        return tempURL
    }

    /// Commit: atomic rename over the destination (POSIX rename(2) replaces
    /// an existing file and succeeds when none exists).
    static func commitStagedWrite(from tempURL: URL, to destination: URL) throws {
        guard rename(tempURL.path, destination.path) == 0 else {
            let underlying = errno
            try? FileManager.default.removeItem(at: tempURL)
            throw POSIXError(POSIXErrorCode(rawValue: underlying) ?? .EIO)
        }
    }

    // MARK: - Lazy creation helpers (§2)

    /// Complete initial document: contentHash over the note's current disk
    /// bytes, createdAt from filesystem metadata, modifiedAt = now.
    private static func makeNewDocument(forMarkdownAt markdownURL: URL, now: Date) throws -> SidecarDocument {
        let markdownData = try Data(contentsOf: markdownURL)
        let attributes = try? FileManager.default.attributesOfItem(atPath: markdownURL.path)
        let createdAt = attributes?[.creationDate] as? Date ?? now
        return SidecarDocument.makeNew(
            contentHash: contentHash(of: markdownData),
            createdAt: isoTimestamp(createdAt),
            modifiedAt: isoTimestamp(now)
        )
    }

    private static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
