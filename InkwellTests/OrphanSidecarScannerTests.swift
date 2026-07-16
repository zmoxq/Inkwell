// =============================================================================
// OrphanSidecarScannerTests.swift
// =============================================================================
//
// Tests for orphan-sidecar recovery (PHASE_4_SIDECAR_SCHEMA.md §2): unique
// hash match rebinds byte-for-byte, everything else is left in place, and a
// clean library computes zero hashes.
// -----------------------------------------------------------------------------

import Foundation
import Testing
@testable import Inkwell

struct OrphanSidecarScannerTests {

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrphanScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Writes an orphan sidecar (no matching .md) whose contentHash matches
    /// `content`, with unknown fields to prove byte preservation.
    @discardableResult
    private func makeOrphan(
        in dir: URL, named name: String, matching content: String, schemaVersion: Int = 1
    ) throws -> (url: URL, bytes: Data) {
        let json = """
        {"schemaVersion": \(schemaVersion), \
        "system": {"contentHash": "\(SidecarStore.contentHash(of: Data(content.utf8)))", \
        "createdAt": "2026-07-01T00:00:00Z", "modifiedAt": "2026-07-01T00:00:00Z"}, \
        "user": {"tags": ["t"]}, "ai": {"summary": "keep"}, "future": true}
        """
        let url = dir.appendingPathComponent(name)
        let bytes = Data(json.utf8)
        try bytes.write(to: url)
        return (url, bytes)
    }

    // MARK: - Unique match

    @Test func uniqueMatchRebindsByteForByte() throws {
        try withTempDir { dir in
            // Candidate note lives in a subdirectory: matching is library-wide.
            let sub = dir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let md = sub.appendingPathComponent("renamed.md")
            try Data("# body\n".utf8).write(to: md)
            let (orphanURL, orphanBytes) = try makeOrphan(
                in: dir, named: "old-name.md.json", matching: "# body\n"
            )

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            #expect(result.rebound.count == 1)
            #expect(result.ambiguous.isEmpty && result.unmatched.isEmpty)
            #expect(!exists(orphanURL))
            let destination = SidecarStore.sidecarURL(forMarkdownAt: md)
            #expect(try Data(contentsOf: destination) == orphanBytes)
        }
    }

    @Test func newerSchemaVersionOrphanStillRebinds() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try Data("x".utf8).write(to: md)
            let (orphanURL, orphanBytes) = try makeOrphan(
                in: dir, named: "old.md.json", matching: "x", schemaVersion: 2
            )

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            // Rebind is a pure rename, exempt from the read-only rule.
            #expect(result.rebound.count == 1)
            #expect(!exists(orphanURL))
            #expect(try Data(contentsOf: SidecarStore.sidecarURL(forMarkdownAt: md)) == orphanBytes)
        }
    }

    // MARK: - Left alone

    @Test func multipleIdenticalNotesLeaveOrphanInPlace() throws {
        try withTempDir { dir in
            try Data("same".utf8).write(to: dir.appendingPathComponent("a.md"))
            try Data("same".utf8).write(to: dir.appendingPathComponent("b.md"))
            let (orphanURL, orphanBytes) = try makeOrphan(
                in: dir, named: "old.md.json", matching: "same"
            )

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            #expect(result.rebound.isEmpty)
            #expect(result.ambiguous == [orphanURL])
            #expect(try Data(contentsOf: orphanURL) == orphanBytes)
        }
    }

    @Test func zeroMatchLeavesOrphanInPlace() throws {
        try withTempDir { dir in
            try Data("different".utf8).write(to: dir.appendingPathComponent("a.md"))
            let (orphanURL, orphanBytes) = try makeOrphan(
                in: dir, named: "old.md.json", matching: "vanished content"
            )

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            #expect(result.rebound.isEmpty)
            #expect(result.unmatched == [orphanURL])
            #expect(try Data(contentsOf: orphanURL) == orphanBytes)
        }
    }

    @Test func pairedNotesAreNeverDisturbed() throws {
        try withTempDir { dir in
            // A properly paired note whose content equals the orphan's hash
            // target — paired notes are not candidates.
            let paired = dir.appendingPathComponent("paired.md")
            try Data("body".utf8).write(to: paired)
            try SidecarStore.setTags(["mine"], forMarkdownAt: paired)
            let pairedSidecar = SidecarStore.sidecarURL(forMarkdownAt: paired)
            let pairedBytes = try Data(contentsOf: pairedSidecar)

            let (orphanURL, _) = try makeOrphan(in: dir, named: "old.md.json", matching: "body")

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            // Orphan has no sidecar-less candidate: left alone; the paired
            // sidecar is untouched.
            #expect(result.rebound.isEmpty)
            #expect(result.unmatched == [orphanURL])
            #expect(try Data(contentsOf: pairedSidecar) == pairedBytes)
        }
    }

    // MARK: - Non-sidecars and cost control

    @Test func tmpLeftoversAreIgnored() throws {
        try withTempDir { dir in
            try Data("{}".utf8).write(to: dir.appendingPathComponent("note.md.json.tmp-abc123"))
            try Data("plain".utf8).write(to: dir.appendingPathComponent("data.json"))

            var hashCount = 0
            let result = OrphanSidecarScanner.scan(libraryRoot: dir) { data in
                hashCount += 1
                return SidecarStore.contentHash(of: data)
            }

            #expect(result.rebound.isEmpty && result.ambiguous.isEmpty && result.unmatched.isEmpty)
            #expect(hashCount == 0)
            #expect(exists(dir.appendingPathComponent("note.md.json.tmp-abc123")))
        }
    }

    @Test func libraryWithoutOrphansComputesZeroHashes() throws {
        try withTempDir { dir in
            // Notes with and without sidecars, but no orphans.
            let paired = dir.appendingPathComponent("paired.md")
            try Data("a".utf8).write(to: paired)
            try SidecarStore.setTags(["t"], forMarkdownAt: paired)
            try Data("b".utf8).write(to: dir.appendingPathComponent("bare.md"))

            var hashCount = 0
            let result = OrphanSidecarScanner.scan(libraryRoot: dir) { data in
                hashCount += 1
                return SidecarStore.contentHash(of: data)
            }

            #expect(result.rebound.isEmpty && result.ambiguous.isEmpty && result.unmatched.isEmpty)
            #expect(hashCount == 0)
        }
    }

    @Test func emptyLibraryScansCleanly() throws {
        try withTempDir { dir in
            var hashCount = 0
            let result = OrphanSidecarScanner.scan(libraryRoot: dir) { data in
                hashCount += 1
                return SidecarStore.contentHash(of: data)
            }
            #expect(result.rebound.isEmpty && result.ambiguous.isEmpty && result.unmatched.isEmpty)
            #expect(hashCount == 0)
        }
    }

    // MARK: - Bidirectional uniqueness

    @Test func candidateClaimedByMultipleOrphansLeavesAllInPlace() throws {
        try withTempDir { dir in
            let md = dir.appendingPathComponent("note.md")
            try Data("shared".utf8).write(to: md)
            let (oneURL, oneBytes) = try makeOrphan(in: dir, named: "one.md.json", matching: "shared")
            let (twoURL, twoBytes) = try makeOrphan(in: dir, named: "two.md.json", matching: "shared")

            let result = OrphanSidecarScanner.scan(libraryRoot: dir)

            // Same hash, but the user/ai layers may differ — first-come-
            // first-served would bind arbitrary metadata to the note.
            // Uniqueness must hold in both directions: nobody rebinds.
            #expect(result.rebound.isEmpty)
            #expect(Set(result.ambiguous) == [oneURL, twoURL])
            #expect(result.unmatched.isEmpty)
            #expect(!exists(SidecarStore.sidecarURL(forMarkdownAt: md)))
            #expect(try Data(contentsOf: oneURL) == oneBytes)
            #expect(try Data(contentsOf: twoURL) == twoBytes)
        }
    }
}
