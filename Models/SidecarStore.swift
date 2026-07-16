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
}
