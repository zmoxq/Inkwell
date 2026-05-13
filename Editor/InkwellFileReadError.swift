// =============================================================================
// InkwellFileReadError.swift
// =============================================================================
//
// Error codes returned by the readLocalFile JS bridge (Phase 3 PR 4' D3).
//
// These codes cross the Swift↔JS boundary as strings inside the error response
// payload. JS-side `onError` handlers in BlockRenderers use them to classify
// errors as "syntax" (user can fix by editing source) vs "runtime" (genuine
// system error).
//
// Adding a new code:
//   1. Add a case below.
//   2. Decide its classification (syntax vs runtime) and document it.
//   3. Update the JS-side classification table in editor.html's stock-chart
//      registerBlock onError (search for INVALID_FILE_PREFIX to find it).
//   4. Update PHASE_3_ARCHITECTURE.md appendix D.6 error code table.
// -----------------------------------------------------------------------------

import Foundation

enum InkwellFileReadError: String, Error {
    /// No document is currently open — nothing to resolve paths against.
    case noDocument = "NO_DOCUMENT"

    /// Path doesn't start with `<docname>/` (the per-note attachment dir prefix).
    /// User-fixable (syntax class).
    case invalidFilePrefix = "INVALID_FILE_PREFIX"

    /// Path standardized to a location outside the per-note attachment dir
    /// (e.g. via `../` traversal). User-fixable (syntax class).
    case outsideAttachmentDir = "OUTSIDE_ATTACHMENT_DIR"

    /// File doesn't exist at the resolved path. User-fixable (syntax class).
    case fileNotFound = "FILE_NOT_FOUND"

    /// Generic IO failure (permission denied, encoding error, etc.).
    /// Runtime class — user typically can't fix from markdown source.
    case ioError = "IO_ERROR"

    var message: String {
        switch self {
        case .noDocument:
            return "No document is currently open."
        case .invalidFilePrefix:
            return "File path must start with the document's attachment folder name."
        case .outsideAttachmentDir:
            return "File path resolved outside the document's attachment folder."
        case .fileNotFound:
            return "File not found."
        case .ioError:
            return "Failed to read file."
        }
    }
}
