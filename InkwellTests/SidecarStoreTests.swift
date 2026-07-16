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

    // MARK: - Lazy creation (§2)

    @Test func lazyCreationWritesCompleteSystemLayer() throws {
        try withTempNote(markdown: "# Hello\n") { mdURL in
            let now = Date(timeIntervalSince1970: 0)
            try SidecarStore.setTags(["投资"], forMarkdownAt: mdURL, now: now)

            guard case .writable(let doc) = try SidecarStore.read(forMarkdownAt: mdURL) else {
                Issue.record("expected .writable after lazy creation")
                return
            }
            #expect(doc.schemaVersion == 1)
            #expect(doc.tags == ["投资"])
            // System layer is complete from birth: hash over the note's
            // current disk bytes, plus both timestamps.
            #expect(doc.contentHash == SidecarStore.contentHash(of: Data("# Hello\n".utf8)))
            #expect(doc.createdAt != nil)
            #expect(doc.modifiedAt == "1970-01-01T00:00:00Z")
            // Empty ai envelope exists.
            #expect(doc.root["ai"] as? [String: Any] != nil)
        }
    }

    @Test func contentSaveDoesNotLazilyCreate() throws {
        try withTempNote { mdURL in
            try SidecarStore.recordContentSave(markdownData: Data("x".utf8), forMarkdownAt: mdURL)
            let sidecarPath = SidecarStore.sidecarURL(forMarkdownAt: mdURL).path
            #expect(!FileManager.default.fileExists(atPath: sidecarPath))
        }
    }

    // MARK: - Unknown-field round-trip through the store (§1 rule 3)

    @Test func writePreservesUnknownFieldsOnDisk() throws {
        let original = """
        {
          "schemaVersion": 1,
          "system": {
            "contentHash": "sha256:00",
            "createdAt": "2026-07-14T08:30:00Z",
            "modifiedAt": "2026-07-14T09:12:45Z",
            "futureSystemField": {"nested": [1, 2, 3]}
          },
          "user": {"tags": ["old"], "futureUserField": "keep me"},
          "ai": {"summary": "AI text", "meta": {"run": 42}},
          "futureTopLevelField": true
        }
        """
        try withTempNote(sidecarJSON: original) { mdURL in
            let now = Date(timeIntervalSince1970: 86_400)
            try SidecarStore.setTags(["new"], forMarkdownAt: mdURL, now: now)
            try SidecarStore.recordContentSave(
                markdownData: Data("abc".utf8), forMarkdownAt: mdURL, now: now
            )

            // Expected = original with exactly the owned fields changed.
            var expected = try #require(
                try JSONSerialization.jsonObject(with: Data(original.utf8)) as? [String: Any]
            )
            var user = expected["user"] as! [String: Any]
            user["tags"] = ["new"]
            expected["user"] = user
            var system = expected["system"] as! [String: Any]
            system["contentHash"] = SidecarStore.contentHash(of: Data("abc".utf8))
            system["modifiedAt"] = "1970-01-02T00:00:00Z"
            expected["system"] = system

            let onDisk = try Data(contentsOf: SidecarStore.sidecarURL(forMarkdownAt: mdURL))
            let actual = try #require(try JSONSerialization.jsonObject(with: onDisk) as? [String: Any])
            #expect(NSDictionary(dictionary: actual) == NSDictionary(dictionary: expected))
        }
    }

    // MARK: - Version gating on write (§3)

    @Test func writesRejectedForNewerVersion() throws {
        let json = #"{"schemaVersion": 2, "system": {}, "user": {}, "ai": {"x": 1}}"#
        try withTempNote(sidecarJSON: json) { mdURL in
            let sidecarURL = SidecarStore.sidecarURL(forMarkdownAt: mdURL)
            let before = try Data(contentsOf: sidecarURL)

            #expect(throws: SidecarError.unsupportedSchemaVersion(2)) {
                try SidecarStore.setTags(["a"], forMarkdownAt: mdURL)
            }
            #expect(throws: SidecarError.unsupportedSchemaVersion(2)) {
                try SidecarStore.recordContentSave(markdownData: Data(), forMarkdownAt: mdURL)
            }
            // File is byte-for-byte untouched.
            #expect(try Data(contentsOf: sidecarURL) == before)
        }
    }

    // MARK: - Atomic write (§4 step 4)

    @Test func interruptedWriteLeavesDestinationIntact() throws {
        let json = #"{"schemaVersion": 1, "system": {}, "user": {}, "ai": {}}"#
        try withTempNote(sidecarJSON: json) { mdURL in
            let sidecarURL = SidecarStore.sidecarURL(forMarkdownAt: mdURL)
            let before = try Data(contentsOf: sidecarURL)

            // Simulate an interruption between stage and commit: only the
            // stage step runs.
            let staged = try SidecarStore.stageWrite(Data("{}".utf8), to: sidecarURL)

            // Payload landed in a temp file in the same directory; the
            // destination is byte-for-byte untouched.
            #expect(FileManager.default.fileExists(atPath: staged.path))
            #expect(staged.deletingLastPathComponent() == sidecarURL.deletingLastPathComponent())
            #expect(try Data(contentsOf: sidecarURL) == before)

            // Completing the commit atomically replaces the destination.
            try SidecarStore.commitStagedWrite(from: staged, to: sidecarURL)
            #expect(try Data(contentsOf: sidecarURL) == Data("{}".utf8))
            #expect(!FileManager.default.fileExists(atPath: staged.path))
        }
    }

    @Test func successfulWriteLeavesNoTempFiles() throws {
        try withTempNote { mdURL in
            try SidecarStore.setTags(["a"], forMarkdownAt: mdURL)
            let contents = try FileManager.default.contentsOfDirectory(
                at: mdURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
            )
            #expect(!contents.contains { $0.lastPathComponent.contains(".tmp-") })
        }
    }
}
