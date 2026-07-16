// =============================================================================
// SidecarStoreTests.swift
// =============================================================================
//
// Disk-level tests for SidecarStore against real files in a per-test
// temporary directory: naming rule, read-state classification, version
// gating, and content hashing (PHASE_4_SIDECAR_SCHEMA.md §2–§4).
// -----------------------------------------------------------------------------

import Foundation
import Testing
@testable import Inkwell

struct SidecarStoreTests {

    /// Creates an isolated temp directory and hands its note URL to `body`.
    private func withTempNote(
        markdown: String? = "# Hello\n",
        sidecarJSON: String? = nil,
        _ body: (URL) throws -> Void
    ) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mdURL = dir.appendingPathComponent("note.md")
        if let markdown {
            try Data(markdown.utf8).write(to: mdURL)
        }
        if let sidecarJSON {
            try Data(sidecarJSON.utf8).write(to: SidecarStore.sidecarURL(forMarkdownAt: mdURL))
        }
        try body(mdURL)
    }

    // MARK: - Naming (§2)

    @Test func sidecarURLAppendsJSONToFullFilename() {
        let md = URL(fileURLWithPath: "/notes/投资笔记.md")
        #expect(SidecarStore.sidecarURL(forMarkdownAt: md).lastPathComponent == "投资笔记.md.json")
    }

    // MARK: - Read states

    @Test func readReturnsAbsentWhenNoFile() throws {
        try withTempNote { mdURL in
            guard case .absent = try SidecarStore.read(forMarkdownAt: mdURL) else {
                Issue.record("expected .absent")
                return
            }
        }
    }

    @Test func readReturnsWritableForSupportedVersion() throws {
        let json = #"{"schemaVersion": 1, "system": {}, "user": {"tags": ["a"]}, "ai": {}}"#
        try withTempNote(sidecarJSON: json) { mdURL in
            guard case .writable(let doc) = try SidecarStore.read(forMarkdownAt: mdURL) else {
                Issue.record("expected .writable")
                return
            }
            #expect(doc.tags == ["a"])
        }
    }

    @Test func readReturnsReadOnlyForNewerVersion() throws {
        let json = #"{"schemaVersion": 2, "system": {}, "user": {}, "ai": {}}"#
        try withTempNote(sidecarJSON: json) { mdURL in
            guard case .readOnly(_, let version) = try SidecarStore.read(forMarkdownAt: mdURL) else {
                Issue.record("expected .readOnly")
                return
            }
            #expect(version == 2)
        }
    }

    @Test func readThrowsMalformedForInvalidContent() throws {
        // Invalid JSON, non-object top level, and missing schemaVersion are
        // all refused rather than risk clobbering another writer's data.
        for bad in ["not json", "[1,2]", #"{"system": {}}"#] {
            try withTempNote(sidecarJSON: bad) { mdURL in
                #expect(throws: SidecarError.malformed) {
                    try SidecarStore.read(forMarkdownAt: mdURL)
                }
            }
        }
    }

    // MARK: - Content hash (§3)

    @Test func contentHashMatchesKnownVector() {
        // SHA-256 of ASCII "abc", a standard test vector.
        #expect(
            SidecarStore.contentHash(of: Data("abc".utf8))
            == "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
