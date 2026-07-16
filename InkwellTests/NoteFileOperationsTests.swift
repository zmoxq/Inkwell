// =============================================================================
// NoteFileOperationsTests.swift
// =============================================================================
//
// Disk-level tests for paired .md + sidecar lifecycle operations
// (PHASE_4_SIDECAR_SCHEMA.md §2, §6).
// -----------------------------------------------------------------------------

import Foundation
import Testing
@testable import Inkwell

struct NoteFileOperationsTests {

    /// Creates an isolated temp directory and hands it to `body`.
    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteFileOperationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Save hook (§6)

    @Test func saveWithoutSidecarWritesContentAndCreatesNoSidecar() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try NoteFileOperations.saveNote(content: "# Hi\n", to: md)
            #expect(try String(contentsOf: md, encoding: .utf8) == "# Hi\n")
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: md)))
        }
    }

    @Test func saveWithSidecarUpdatesHashAndPreservesUserData() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try Data("old".utf8).write(to: md)
            try SidecarStore.setTags(["keep"], forMarkdownAt: md)

            try NoteFileOperations.saveNote(content: "new body\n", to: md)

            guard case .writable(let doc) = try SidecarStore.read(forMarkdownAt: md) else {
                Issue.record("expected .writable")
                return
            }
            #expect(doc.contentHash == SidecarStore.contentHash(of: Data("new body\n".utf8)))
            #expect(doc.modifiedAt != nil)
            #expect(doc.tags == ["keep"])
        }
    }
}
