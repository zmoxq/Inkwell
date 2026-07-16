// =============================================================================
// NoteFileOperations.swift
// =============================================================================
//
// Note-level filesystem operations that keep a note's .md and its sidecar
// (P.md.json) moving through the filesystem as a pair, per
// PHASE_4_SIDECAR_SCHEMA.md §2 (in-app rename/move) and §6 (save hook).
//
// Stateless and URL-based like SidecarStore; UI entry points wire in from
// AppState / views in later PRs.
// -----------------------------------------------------------------------------

import Foundation

enum NoteFileOperations {

    enum OperationError: Error, Equatable {
        /// Rename/move destination .md already exists; the operation is
        /// refused as a whole.
        case destinationExists
    }

    // MARK: - Save (§6 content-save hook)

    /// Writes note content to disk, then records the save in the sidecar
    /// (contentHash/modifiedAt). The sidecar step no-ops when no sidecar
    /// exists, and a sidecar failure is logged but never blocks the content
    /// save — the .md is the source of truth and its persistence has
    /// absolute priority.
    static func saveNote(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        do {
            // Hash over the exact UTF-8 bytes just written, matching the
            // contract's "hash of on-disk bytes" without a re-read.
            try SidecarStore.recordContentSave(markdownData: Data(content.utf8), forMarkdownAt: url)
        } catch {
            print("[Inkwell] Sidecar update failed for \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Rename / move (§2 in-app rename)

    /// Moves a note's .md and its sidecar together. Same-directory rename
    /// and cross-directory move are the same operation.
    ///
    /// Conflicts: an existing destination .md refuses the whole operation.
    /// An existing destination sidecar can only be a stale orphan (its .md
    /// is absent) — left in place it would mis-pair with the note moving
    /// in, and §2 rates mis-pairing worse than loss, so it is moved to the
    /// system trash (recoverable, never hard-deleted) before our pair
    /// takes the name.
    static func renameNote(from sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destinationURL.path) else {
            throw OperationError.destinationExists
        }
        let destinationSidecar = SidecarStore.sidecarURL(forMarkdownAt: destinationURL)
        if fm.fileExists(atPath: destinationSidecar.path) {
            try fm.trashItem(at: destinationSidecar, resultingItemURL: nil)
        }
        try fm.moveItem(at: sourceURL, to: destinationURL)
        let sourceSidecar = SidecarStore.sidecarURL(forMarkdownAt: sourceURL)
        if fm.fileExists(atPath: sourceSidecar.path) {
            try fm.moveItem(at: sourceSidecar, to: destinationSidecar)
        }
    }
}
