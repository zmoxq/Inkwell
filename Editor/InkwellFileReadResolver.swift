// =============================================================================
// InkwellFileReadResolver.swift
// =============================================================================
//
// Pure helper for resolving file paths from the readLocalFile JS bridge.
//
// This is intentionally separated from MarkdownEditorView so it can be unit-
// tested without WKWebView setup. The resolver enforces D.15 contract:
//
//   - file: field must start with "<docname>/" where docname = doc filename
//     minus .md extension
//   - After path standardization, resolved URL must remain inside that
//     per-note attachment directory
//   - Absolute paths are rejected outright
//
// Cross-document references (e.g. "other-note/foo.csv") and parent-directory
// escapes ("../../etc/passwd") are both caught by the boundary check.
// -----------------------------------------------------------------------------

import Foundation

struct InkwellFileReadResolver {

    /// Result of resolving a relative path against a document context.
    enum Result {
        case ok(URL)
        case error(InkwellFileReadError)
    }

    /// Resolve `relativePath` against `documentURL`'s attachment directory.
    /// Does NOT touch the filesystem — only computes and validates the URL.
    /// Caller is responsible for the actual file read.
    static func resolve(relativePath: String, documentURL: URL) -> Result {
        // 1. Reject absolute paths outright.
        if relativePath.hasPrefix("/") {
            return .error(.invalidFilePrefix)
        }

        // 2. Compute the attachment dir: <doc-dir>/<docname>/
        //    where docname = doc filename without .md extension
        let docDir = documentURL.deletingLastPathComponent()
        let docName = documentURL.deletingPathExtension().lastPathComponent

        // Empty docname can happen if the document is named ".md" — defensive.
        guard !docName.isEmpty else {
            return .error(.noDocument)
        }

        let attachmentDir = docDir.appendingPathComponent(docName, isDirectory: true)

        // 3. Required prefix: "<docname>/"
        let expectedPrefix = docName + "/"
        guard relativePath.hasPrefix(expectedPrefix) else {
            return .error(.invalidFilePrefix)
        }

        // 4. Resolve against doc-dir + standardize (normalize ../, ./, etc.)
        let resolved = docDir
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        // 5. Boundary check: resolved must still be inside attachmentDir.
        //    Compare standardized paths with trailing slash to avoid prefix
        //    confusion (e.g. /a/b vs /a/bc).
        let attachmentBase = attachmentDir.standardizedFileURL.path
        let attachmentPrefix = attachmentBase.hasSuffix("/")
            ? attachmentBase
            : attachmentBase + "/"

        guard resolved.path.hasPrefix(attachmentPrefix) else {
            return .error(.outsideAttachmentDir)
        }

        return .ok(resolved)
    }
}
