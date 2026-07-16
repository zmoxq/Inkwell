// =============================================================================
// AppStateFileManagementTests.swift
// =============================================================================
//
// End-to-end tests for AppState.renameNote / deleteNote wiring: open-tab URL
// sync, save-to-new-path after rename, and tab closing on delete.
// -----------------------------------------------------------------------------

import Foundation
import Testing
@testable import Inkwell

struct AppStateFileManagementTests {

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateFileManagementTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    private func makeNote(_ dir: URL, _ name: String, _ content: String = "# Hi\n") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    // MARK: - Rename

    /// Core acceptance: rename an open note, keep editing, save — the save
    /// must land at the new path and the old path must not come back.
    @Test func renameOpenNoteThenSaveWritesToNewPathOnly() throws {
        try withTempDir { dir in
            let old = try makeNote(dir, "old.md", "v1")
            let state = AppState()
            state.openFile(old)

            // Unsaved edit at rename time: saved to the old path first,
            // then the pair moves.
            state.currentDocument?.content = "v2"
            state.currentDocument?.isDirty = true
            let new = try state.renameNote(at: old, to: "renamed")

            #expect(new.lastPathComponent == "renamed.md")
            #expect(!exists(old))
            #expect(try String(contentsOf: new, encoding: .utf8) == "v2")
            #expect(state.currentDocument?.url == new)

            // Keep editing and save: new path gets the content, old path
            // must not be resurrected.
            state.currentDocument?.content = "v3"
            state.currentDocument?.isDirty = true
            state.saveCurrentDocument()
            #expect(try String(contentsOf: new, encoding: .utf8) == "v3")
            #expect(!exists(old))
        }
    }

    @Test func renameMovesSidecarThroughAppState() throws {
        try withTempDir { dir in
            let old = try makeNote(dir, "old.md")
            try SidecarStore.setTags(["a"], forMarkdownAt: old)
            let state = AppState()
            let new = try state.renameNote(at: old, to: "renamed.md")

            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: old)))
            guard case .writable(let doc) = try SidecarStore.read(forMarkdownAt: new) else {
                Issue.record("expected sidecar at new path")
                return
            }
            #expect(doc.tags == ["a"])
        }
    }

    @Test func renameToExistingNameThrowsAndChangesNothing() throws {
        try withTempDir { dir in
            let old = try makeNote(dir, "old.md", "src")
            try makeNote(dir, "taken.md", "dst")
            let state = AppState()
            state.openFile(old)

            #expect(throws: NoteFileOperations.OperationError.destinationExists) {
                try state.renameNote(at: old, to: "taken")
            }
            #expect(exists(old))
            #expect(state.currentDocument?.url == old)
        }
    }

    @Test func renameAppendsMDExtensionAndIgnoresNoOps() throws {
        try withTempDir { dir in
            let old = try makeNote(dir, "note.md")
            let state = AppState()
            // Empty and unchanged names are no-ops.
            #expect(try state.renameNote(at: old, to: "  ") == old)
            #expect(try state.renameNote(at: old, to: "note.md") == old)
            let new = try state.renameNote(at: old, to: "plain")
            #expect(new.lastPathComponent == "plain.md")
        }
    }

    // MARK: - Delete

    @Test func deleteActiveNoteClosesTabAndActivatesNeighbor() throws {
        try withTempDir { dir in
            let a = try makeNote(dir, "a.md")
            let b = try makeNote(dir, "b.md")
            let state = AppState()
            state.openFile(a)
            state.openFile(b) // active

            // Dirty edit must be discarded, not saved back to the trashed path.
            state.currentDocument?.content = "unsaved"
            state.currentDocument?.isDirty = true
            try state.deleteNote(at: b)

            #expect(!exists(b))
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: b)))
            #expect(state.openTabs.count == 1)
            #expect(state.currentDocument?.url == a)
        }
    }

    @Test func deleteInactiveNoteKeepsActiveTab() throws {
        try withTempDir { dir in
            let a = try makeNote(dir, "a.md")
            let b = try makeNote(dir, "b.md")
            let state = AppState()
            state.openFile(a)
            state.openFile(b) // active
            try state.deleteNote(at: a)

            #expect(state.openTabs.count == 1)
            #expect(state.currentDocument?.url == b)
        }
    }

    @Test func deleteRemovesSidecarToo() throws {
        try withTempDir { dir in
            let a = try makeNote(dir, "a.md")
            try SidecarStore.setTags(["x"], forMarkdownAt: a)
            let state = AppState()
            try state.deleteNote(at: a)
            #expect(!exists(a))
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: a)))
        }
    }
}
