// =============================================================================
// InkwellAttachmentStore.swift
// =============================================================================
//
// Shared per-note attachment WRITE logic.
//
// Convention (PHASE_3_ARCHITECTURE.md §11): a note `<basename>.md` stores its
// associated assets in a sibling `<basename>/` folder. Assets are referenced
// from the markdown by the relative path `<basename>/<file>`, which resolves
// against the note's directory (the WebView base URL + its read-access grant
// are both that directory) — the same directory the read side
// (InkwellFileReadResolver) enforces as its boundary.
//
// This is the single source of truth for that write path. Both
//   - MarkdownDocument.saveAttachment (the model-level API), and
//   - EditorCoordinator's image-copy path (carousel + single-image insert)
// call it, so no caller derives the folder or the collision-safe name itself.
//
// Foundation-only + no WKWebView dependency, so it can be unit-tested directly
// (mirrors InkwellFileReadResolver on the read side).
// -----------------------------------------------------------------------------

import Foundation
import CryptoKit

enum InkwellAttachmentStore {

    enum StoreError: Error {
        /// The note has no on-disk location yet (no basename to derive a folder).
        case noNoteOnDisk
        case writeFailed(Error)
    }

    /// The per-note attachment directory for `noteURL` (`<basename>/`).
    static func attachmentsDirectory(for noteURL: URL) -> URL {
        noteURL.deletingPathExtension()
    }

    /// Create `<basename>/` if it does not already exist. Idempotent.
    static func ensureDirectory(for noteURL: URL) throws {
        let dir = attachmentsDirectory(for: noteURL)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Save `data` (an asset whose original filename is `originalName`) into the
    /// note's `<basename>/` folder under a collision-safe name
    /// `<cleaned>-<shorthash>.<ext>`. Returns the markdown-relative path
    /// `<basename>/<finalName>`.
    ///
    /// Content-addressed: the short hash is over the bytes, so two *different*
    /// files that share a name land as two files (different hash), while the
    /// *same* bytes inserted twice dedup to one file (identical name → the
    /// existing file is reused, both references point at it).
    @discardableResult
    static func save(data: Data, originalName: String, for noteURL: URL) throws -> String {
        try ensureDirectory(for: noteURL)
        let dir = attachmentsDirectory(for: noteURL)
        let finalName = fileName(for: data, originalName: originalName)
        let target = dir.appendingPathComponent(finalName)
        if !FileManager.default.fileExists(atPath: target.path) {
            do { try data.write(to: target) }
            catch { throw StoreError.writeFailed(error) }
        }
        let folder = noteURL.deletingPathExtension().lastPathComponent
        return "\(folder)/\(finalName)"
    }

    // MARK: - Name construction

    /// `<cleaned>-<shorthash>.<ext>` (or `<cleaned>-<shorthash>` when the source
    /// has no extension). Falls back to `image` when cleaning empties the base.
    static func fileName(for data: Data, originalName: String) -> String {
        let ns = originalName as NSString
        let ext = sanitizedExtension(ns.pathExtension)
        let base = cleanedBase(ns.deletingPathExtension)
        let stem = base.isEmpty ? "image" : base
        let hash = shortHash(data)
        return ext.isEmpty ? "\(stem)-\(hash)" : "\(stem)-\(hash).\(ext)"
    }

    /// Filename-base cleaning rules:
    ///  - keep Unicode letters/digits (Chinese, accented names survive) plus
    ///    `-` and `_`;
    ///  - every other scalar (spaces, path separators `/ \`, and filesystem /
    ///    URL-hostile chars `: ? * " < > | #` …) becomes `-`;
    ///  - runs of `-` collapse to one; leading/trailing `-`/`_` are trimmed;
    ///  - truncate to 40 characters.
    static func cleanedBase(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let mapped = String(String.UnicodeScalarView(
            raw.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }))
        let collapsed = mapped.replacingOccurrences(
            of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return String(trimmed.prefix(40))
    }

    /// Lowercased, alphanumerics only, capped at 10 chars.
    static func sanitizedExtension(_ ext: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let filtered = String(ext.lowercased().unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(10))
    }

    /// First 4 bytes of SHA-256 as 8 lowercase hex chars.
    static func shortHash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
