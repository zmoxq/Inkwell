// =============================================================================
// SidecarDocumentTests.swift
// =============================================================================
//
// In-memory tests for the dictionary-backed sidecar model. The core
// acceptance criterion is unknown-field preservation: any field the model
// does not know about — top-level, inside each layer, and the entire `ai`
// layer — must survive a parse → mutate → serialize → parse cycle
// semantically intact (PHASE_4_SIDECAR_SCHEMA.md §1 rule 3).
// -----------------------------------------------------------------------------

import Foundation
import Testing
@testable import Inkwell

struct SidecarDocumentTests {

    /// Fixture with unknown fields at every level the contract protects:
    /// top-level, inside system/user, and a fully populated ai layer.
    private static let fixtureJSON = """
    {
      "schemaVersion": 1,
      "system": {
        "contentHash": "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        "createdAt": "2026-07-14T08:30:00Z",
        "modifiedAt": "2026-07-14T09:12:45Z",
        "futureSystemField": {"nested": [1, 2, 3]}
      },
      "user": {
        "tags": ["投资", "读书笔记"],
        "futureUserField": "keep me"
      },
      "ai": {
        "summary": "Some AI-written summary",
        "embeddings": [0.25, -0.5],
        "meta": {"model": "some-model", "run": 42}
      },
      "futureTopLevelField": true
    }
    """

    private func parseFixture() throws -> SidecarDocument {
        let doc = SidecarDocument(jsonData: Data(Self.fixtureJSON.utf8))
        return try #require(doc)
    }

    /// Semantic JSON equality via NSDictionary (order-insensitive).
    private func assertSemanticallyEqual(_ a: Data, _ b: Data) throws {
        let objA = try #require(try JSONSerialization.jsonObject(with: a) as? [String: Any])
        let objB = try #require(try JSONSerialization.jsonObject(with: b) as? [String: Any])
        #expect(NSDictionary(dictionary: objA) == NSDictionary(dictionary: objB))
    }

    // MARK: - Parsing

    @Test func parsesTypedFields() throws {
        let doc = try parseFixture()
        #expect(doc.schemaVersion == 1)
        #expect(doc.contentHash == "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
        #expect(doc.createdAt == "2026-07-14T08:30:00Z")
        #expect(doc.modifiedAt == "2026-07-14T09:12:45Z")
        #expect(doc.tags == ["投资", "读书笔记"])
    }

    @Test func rejectsNonObjectTopLevel() {
        #expect(SidecarDocument(jsonData: Data("[1, 2, 3]".utf8)) == nil)
        #expect(SidecarDocument(jsonData: Data("not json".utf8)) == nil)
    }

    @Test func missingLayersReadAsDefaults() {
        let doc = SidecarDocument(root: ["schemaVersion": 1])
        #expect(doc.contentHash == nil)
        #expect(doc.tags == [])
    }

    // MARK: - Unknown-field preservation

    @Test func pureRoundTripIsSemanticallyEqual() throws {
        let doc = try parseFixture()
        try assertSemanticallyEqual(Data(Self.fixtureJSON.utf8), doc.jsonData())
    }

    @Test func mutationPreservesAllUnknownFields() throws {
        var doc = try parseFixture()
        doc.setTags(["新标签"])
        doc.updateSystem(contentHash: "sha256:abcd", modifiedAt: "2026-07-16T00:00:00Z")

        let reparsed = try #require(SidecarDocument(jsonData: doc.jsonData()))

        // Mutated fields took effect.
        #expect(reparsed.tags == ["新标签"])
        #expect(reparsed.contentHash == "sha256:abcd")
        #expect(reparsed.modifiedAt == "2026-07-16T00:00:00Z")

        // Untouched sibling fields in mutated layers survive.
        #expect(reparsed.createdAt == "2026-07-14T08:30:00Z")
        let system = try #require(reparsed.root["system"] as? [String: Any])
        let futureSystem = try #require(system["futureSystemField"] as? [String: Any])
        #expect(futureSystem["nested"] as? [Int] == [1, 2, 3])
        let user = try #require(reparsed.root["user"] as? [String: Any])
        #expect(user["futureUserField"] as? String == "keep me")

        // Top-level unknown field survives.
        #expect(reparsed.root["futureTopLevelField"] as? Bool == true)

        // The entire ai layer survives untouched.
        let originalRoot = try #require(
            try JSONSerialization.jsonObject(with: Data(Self.fixtureJSON.utf8)) as? [String: Any]
        )
        let originalAI = try #require(originalRoot["ai"] as? [String: Any])
        let reparsedAI = try #require(reparsed.root["ai"] as? [String: Any])
        #expect(NSDictionary(dictionary: reparsedAI) == NSDictionary(dictionary: originalAI))
    }

    @Test func mutatorsCreateMissingLayers() throws {
        var doc = SidecarDocument(root: ["schemaVersion": 1])
        doc.setTags(["a"])
        doc.updateSystem(contentHash: "sha256:00", modifiedAt: "2026-07-16T00:00:00Z")
        let reparsed = try #require(SidecarDocument(jsonData: doc.jsonData()))
        #expect(reparsed.tags == ["a"])
        #expect(reparsed.contentHash == "sha256:00")
    }

    // MARK: - Creation

    @Test func makeNewProducesCompleteSystemLayer() throws {
        let doc = SidecarDocument.makeNew(
            contentHash: "sha256:ff",
            createdAt: "2026-07-16T01:00:00Z",
            modifiedAt: "2026-07-16T01:00:00Z"
        )
        #expect(doc.schemaVersion == 1)
        #expect(doc.contentHash == "sha256:ff")
        #expect(doc.createdAt == "2026-07-16T01:00:00Z")
        #expect(doc.modifiedAt == "2026-07-16T01:00:00Z")
        // Empty user/ai envelopes exist from birth.
        #expect(doc.root["user"] as? [String: Any] != nil)
        #expect(doc.root["ai"] as? [String: Any] != nil)
        // Serializes without throwing.
        _ = try doc.jsonData()
    }
}
