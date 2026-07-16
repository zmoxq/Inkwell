// =============================================================================
// InkwellFileReadResolver.swift
// =============================================================================
//
// Pure helper for resolving file paths from the readLocalFile JS bridge.
//
// This is intentionally separated from MarkdownEditorView so it can be unit-
// tested without WKWebView setup. The resolver enforces the D.15 contract,
// revised 2026-07-16 (PHASE_3_ARCHITECTURE.md §11): paths resolve against
// the note's DIRECTORY, not a folder derived from the note's filename.
//
//   - Absolute paths are rejected outright
//   - After standardization, the resolved URL must remain strictly inside
//     the note's directory — parent-directory escapes ("../../etc/passwd")
//     are caught by the containment check
//
// The directory basis matches the image channel (WebView base URL and its
// read-access grant are both the note's directory), and survives note
// renames: a same-directory rename never changes the directory. Error-code
// rawValues are unchanged — they are part of the Swift<->JS contract.
// -----------------------------------------------------------------------------

import Foundation

struct InkwellFileReadResolver {

    /// Result of resolving a relative path against a document context.
    enum Result {
        case ok(URL)
        case error(InkwellFileReadError)
    }

    /// Resolve `relativePath` against `documentURL`'s directory.
    /// Does NOT touch the filesystem — only computes and validates the URL.
    /// Caller is responsible for the actual file read.
    static func resolve(relativePath: String, documentURL: URL) -> Result {
        // 1. Reject absolute paths outright.
        if relativePath.hasPrefix("/") {
            return .error(.invalidFilePrefix)
        }

        // 2. Base: the note's directory.
        let docDir = documentURL.deletingLastPathComponent().standardizedFileURL

        // 3. Resolve + standardize (normalizes ../, ./, etc.).
        let resolved = docDir
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        // 4. Containment: resolved must be strictly inside the note's
        //    directory. Trailing-slash comparison avoids prefix confusion
        //    (/a/b vs /a/bc) and rejects the directory itself (empty path,
        //    "." and full ../ round-trips all land on docDir).
        let base = docDir.path.hasSuffix("/") ? docDir.path : docDir.path + "/"
        guard resolved.path.hasPrefix(base) else {
            return .error(.outsideAttachmentDir)
        }

        return .ok(resolved)
    }
}
