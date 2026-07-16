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

    // MARK: - Rename / move (§2)

    @Test func renameMovesSidecarAlongWithBytesUnchanged() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("old.md")
            try Data("# body\n".utf8).write(to: src)
            try SidecarStore.setTags(["a"], forMarkdownAt: src)
            let sidecarBytes = try Data(contentsOf: SidecarStore.sidecarURL(forMarkdownAt: src))

            let dst = dir.appendingPathComponent("sub").appendingPathComponent("new.md")
            try FileManager.default.createDirectory(
                at: dst.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try NoteFileOperations.renameNote(from: src, to: dst)

            #expect(!exists(src))
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: src)))
            #expect(try String(contentsOf: dst, encoding: .utf8) == "# body\n")
            // Sidecar followed byte-for-byte: a move must never rewrite it.
            #expect(try Data(contentsOf: SidecarStore.sidecarURL(forMarkdownAt: dst)) == sidecarBytes)
        }
    }

    @Test func renameWithoutSidecarMovesOnlyMarkdown() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("old.md")
            try Data("x".utf8).write(to: src)
            let dst = dir.appendingPathComponent("new.md")
            try NoteFileOperations.renameNote(from: src, to: dst)
            #expect(exists(dst))
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: dst)))
        }
    }

    @Test func renameRefusedWhenDestinationMarkdownExists() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("old.md")
            try Data("src".utf8).write(to: src)
            try SidecarStore.setTags(["a"], forMarkdownAt: src)
            let dst = dir.appendingPathComponent("new.md")
            try Data("dst".utf8).write(to: dst)

            #expect(throws: NoteFileOperations.OperationError.destinationExists) {
                try NoteFileOperations.renameNote(from: src, to: dst)
            }
            // Nothing moved.
            #expect(exists(src))
            #expect(exists(SidecarStore.sidecarURL(forMarkdownAt: src)))
            #expect(try Data(contentsOf: dst) == Data("dst".utf8))
        }
    }

    @Test func renameDisplacesStaleOrphanSidecarAtDestination() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("old.md")
            try Data("src".utf8).write(to: src)
            try SidecarStore.setTags(["ours"], forMarkdownAt: src)
            let ourSidecarBytes = try Data(contentsOf: SidecarStore.sidecarURL(forMarkdownAt: src))

            // Orphan sidecar at the destination name, no matching .md.
            let dst = dir.appendingPathComponent("new.md")
            let orphan = SidecarStore.sidecarURL(forMarkdownAt: dst)
            try Data(#"{"schemaVersion": 1, "ai": {"stale": true}}"#.utf8).write(to: orphan)

            try NoteFileOperations.renameNote(from: src, to: dst)

            // Our sidecar owns the destination name; the orphan was
            // displaced (to the trash), not merged into.
            #expect(try Data(contentsOf: orphan) == ourSidecarBytes)
        }
    }

    // MARK: - Delete (§6)

    @Test func trashRemovesBothFilesFromDirectory() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try Data("x".utf8).write(to: md)
            try SidecarStore.setTags(["a"], forMarkdownAt: md)

            try NoteFileOperations.trashNote(at: md)

            #expect(!exists(md))
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: md)))
        }
    }

    @Test func trashWithoutSidecarRemovesMarkdownOnly() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try Data("x".utf8).write(to: md)
            try NoteFileOperations.trashNote(at: md)
            #expect(!exists(md))
        }
    }
}
