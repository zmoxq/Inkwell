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
}
