// =============================================================================
// OrphanSidecarScanner.swift
// =============================================================================
//
// Orphan-sidecar recovery per PHASE_4_SIDECAR_SCHEMA.md §2: when a note is
// renamed outside the app, its sidecar (P.md.json) loses its .md. On library
// open we scan for such orphans and re-pair each one against the sidecar-less
// .md files by exact contentHash match — unique hit rebinds, anything else is
// left alone (mis-pairing is worse than loss; no fuzzy matching).
//
// Rebinding is a pure filesystem rename: sidecar bytes are never touched, so
// it is exempt from the schemaVersion read-only rule, which restricts writes
// to content only.
// -----------------------------------------------------------------------------

import Foundation

enum OrphanSidecarScanner {

    struct ScanResult {
        /// Orphans re-paired by unique hash match: (old location, new location).
        var rebound: [(orphan: URL, destination: URL)] = []
        /// Orphans matching multiple candidate notes (identical content) —
        /// left in place.
        var ambiguous: [URL] = []
        /// Orphans with no match, an unreadable contentHash, or a rebind
        /// destination that turned out to be taken — left in place.
        var unmatched: [URL] = []
    }

    /// Scans the library once. Hashing of candidate notes only happens when
    /// at least one orphan exists — a clean library pays enumeration cost
    /// only. `contentHash` is injectable so tests can count invocations.
    static func scan(
        libraryRoot: URL,
        contentHash: (Data) -> String = { SidecarStore.contentHash(of: $0) }
    ) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()

        // Single enumeration pass: collect sidecars and notes.
        // §2 rule: a .json file is a sidecar iff dropping the .json suffix
        // yields a path ending in .md. Stray temp files (*.md.json.tmp-…)
        // fail that rule by construction.
        var sidecarURLs: [URL] = []
        var markdownURLs: [URL] = []
        guard let enumerator = fm.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return result }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".md.json") {
                sidecarURLs.append(url)
            } else if name.hasSuffix(".md") {
                markdownURLs.append(url)
            }
        }

        // Orphan: sidecar whose .md (path minus the .json suffix) is gone.
        let orphans = sidecarURLs.filter {
            !fm.fileExists(atPath: $0.deletingPathExtension().path)
        }
        guard !orphans.isEmpty else { return result }

        // Candidates: notes without a sidecar. Each hashed exactly once,
        // shared across all orphans.
        var candidatesByHash: [String: [URL]] = [:]
        for md in markdownURLs {
            guard !fm.fileExists(atPath: SidecarStore.sidecarURL(forMarkdownAt: md).path),
                  let data = try? Data(contentsOf: md) else { continue }
            candidatesByHash[contentHash(data), default: []].append(md)
        }

        for orphan in orphans {
            guard let data = try? Data(contentsOf: orphan),
                  let document = SidecarDocument(jsonData: data),
                  let hash = document.contentHash else {
                print("[Inkwell] Orphan sidecar has no readable contentHash, leaving in place: \(orphan.path)")
                result.unmatched.append(orphan)
                continue
            }
            let candidates = candidatesByHash[hash] ?? []
            switch candidates.count {
            case 1:
                let destination = SidecarStore.sidecarURL(forMarkdownAt: candidates[0])
                // Candidates are sidecar-less by definition, so the name is
                // free — but guard anyway (e.g. an identical-hash orphan
                // rebound earlier in this pass).
                if !fm.fileExists(atPath: destination.path),
                   (try? fm.moveItem(at: orphan, to: destination)) != nil {
                    result.rebound.append((orphan: orphan, destination: destination))
                    candidatesByHash[hash] = []
                } else {
                    print("[Inkwell] Orphan sidecar rebind destination unavailable, leaving in place: \(orphan.path)")
                    result.unmatched.append(orphan)
                }
            case 0:
                print("[Inkwell] Orphan sidecar has no content match, leaving in place: \(orphan.path)")
                result.unmatched.append(orphan)
            default:
                print("[Inkwell] Orphan sidecar matches \(candidates.count) identical notes, leaving in place: \(orphan.path)")
                result.ambiguous.append(orphan)
            }
        }
        return result
    }
}
