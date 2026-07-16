// =============================================================================
// SidecarDocument.swift
// =============================================================================
//
// Dictionary-backed model for a sidecar file (P.md.json), per the contract in
// PHASE_4_SIDECAR_SCHEMA.md.
//
// The single source of truth is `root`, the raw JSON object produced by
// JSONSerialization. Typed accessors are thin wrappers that read/patch named
// fields inside the `system` and `user` layers only. Serialization writes the
// whole tree back, so unknown fields — top-level, inside any layer, and the
// entire `ai` layer — survive a read/modify/write cycle untouched (§1 rule 3).
//
// Deliberately NOT Codable: Codable structs drop unknown keys on decode,
// which would violate the unknown-field preservation rule.
// -----------------------------------------------------------------------------

import Foundation

struct SidecarDocument {

    /// Raw JSON object. Mutations go through the accessors below, which only
    /// touch named fields in the layers Inkwell owns (`system`, `user`).
    private(set) var root: [String: Any]

    init(root: [String: Any]) {
        self.root = root
    }

    /// Parses sidecar bytes. Fails (returns nil) if the data is not valid
    /// JSON or the top level is not an object.
    init?(jsonData: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        self.root = dictionary
    }

    /// Serializes the entire tree. Sorted keys keep output stable across
    /// rewrites; pretty-printing keeps the file human-readable in Finder.
    func jsonData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - Typed accessors (read)

    var schemaVersion: Int? {
        root["schemaVersion"] as? Int
    }

    var contentHash: String? {
        layer("system")["contentHash"] as? String
    }

    var createdAt: String? {
        layer("system")["createdAt"] as? String
    }

    var modifiedAt: String? {
        layer("system")["modifiedAt"] as? String
    }

    var tags: [String] {
        layer("user")["tags"] as? [String] ?? []
    }

    // MARK: - Typed accessors (write; system/user layers only)

    /// Updates system fields after a content save. Other keys in the
    /// `system` layer are preserved.
    mutating func updateSystem(contentHash: String, modifiedAt: String) {
        patchLayer("system") { system in
            system["contentHash"] = contentHash
            system["modifiedAt"] = modifiedAt
        }
    }

    /// Replaces `user.tags`. Other keys in the `user` layer are preserved.
    mutating func setTags(_ tags: [String]) {
        patchLayer("user") { user in
            user["tags"] = tags
        }
    }

    // MARK: - Creation

    /// Builds a brand-new document for lazy sidecar creation: complete
    /// `system` layer, empty `user` and `ai` layers (§2 lazy creation).
    static func makeNew(contentHash: String, createdAt: String, modifiedAt: String) -> SidecarDocument {
        SidecarDocument(root: [
            "schemaVersion": 1,
            "system": [
                "contentHash": contentHash,
                "createdAt": createdAt,
                "modifiedAt": modifiedAt,
            ],
            "user": [:],
            "ai": [:],
        ])
    }

    // MARK: - Private

    private func layer(_ name: String) -> [String: Any] {
        root[name] as? [String: Any] ?? [:]
    }

    private mutating func patchLayer(_ name: String, _ mutate: (inout [String: Any]) -> Void) {
        var layer = root[name] as? [String: Any] ?? [:]
        mutate(&layer)
        root[name] = layer
    }
}
