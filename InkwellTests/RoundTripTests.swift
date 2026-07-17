// =============================================================================
// RoundTripTests.swift
// =============================================================================
//
// Round-trip integrity net. Each fixture in tests/roundtrip/fixtures goes
// through the real parse → decorate → serialize path (RoundTripHarness) and
// must come back byte-for-byte, modulo the single EOF-newline normalization
// documented in tests/roundtrip/NORMALIZATION.md.
//
// Fixtures that reproduce a still-open defect are wrapped in XCTExpectFailure
// with a reference, so the suite stays green-runnable while the corruption is
// on record; removing the wrapper is how a fix lands. Fixtures for the two
// defects under active repair in this project (intra-word underscore,
// thematic-break-to-table) are left as hard assertions — they are RED until
// the parser fixes land, GREEN after.
// -----------------------------------------------------------------------------

import XCTest
import WebKit
@testable import Inkwell

@MainActor
final class RoundTripTests: XCTestCase {

    // Shared across tests: boot the editor once (mermaid/katex/hljs load is
    // the slow part).
    private static var sharedHarness: RoundTripHarness?

    private func harness() async throws -> RoundTripHarness {
        if let h = Self.sharedHarness { return h }
        let h = RoundTripHarness()
        try await h.boot()
        Self.sharedHarness = h
        return h
    }

    // #filePath = <repo>/InkwellTests/RoundTripTests.swift
    private static let fixturesDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // InkwellTests/
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("tests/roundtrip/fixtures")

    /// The one whitelisted normalization: strip trailing newlines (EOF
    /// convention, not content — see NORMALIZATION.md).
    private func canonicalized(_ s: String) -> String {
        var t = Substring(s)
        while t.hasSuffix("\n") { t = t.dropLast() }
        return String(t)
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: Self.fixturesDir.appendingPathComponent(name), encoding: .utf8)
    }

    /// Asserts a fixture round-trips clean (modulo the EOF rule). On failure,
    /// reports the first diverging line with context.
    private func assertRoundTripClean(
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let input = try fixture(name)
        let output = try await harness().roundTrip(input)
        let expected = canonicalized(input)
        let actual = canonicalized(output)
        if expected != actual {
            XCTFail("Round-trip corrupted \(name):\n\(firstDivergence(expected, actual))", file: file, line: line)
        }
    }

    private func firstDivergence(_ expected: String, _ actual: String) -> String {
        let e = expected.components(separatedBy: "\n")
        let a = actual.components(separatedBy: "\n")
        for i in 0..<max(e.count, a.count) {
            let el = i < e.count ? e[i] : "<none>"
            let al = i < a.count ? a[i] : "<none>"
            if el != al {
                return "  first diff at line \(i + 1):\n    expected: \(el)\n    actual:   \(al)"
            }
        }
        return "  (line-equal but string-unequal; check trailing whitespace)"
    }

    // MARK: - Green guards (must always pass)

    func testFenceWithoutLanguage() async throws {
        // Regression guard for the hljs language-fabrication fix (b21cf9f).
        try await assertRoundTripClean("fence-no-language.md")
    }

    func testHeadingNumbered() async throws {
        // Documents that the pure round-trip path does NOT eat heading
        // numbers (the disk corruption came from another path — see §12).
        try await assertRoundTripClean("heading-numbered.md")
    }

    func testCodeThenHeading() async throws {
        // Documents that the pure round-trip path does NOT leak an hljs
        // <span style> into a following heading.
        try await assertRoundTripClean("code-then-heading.md")
    }

    func testSmokeMermaid() async throws {
        try await assertRoundTripClean("smoke-mermaid.md")
    }

    // MARK: - Defects under active repair (RED now, GREEN after step 2)

    func testEmphasisUnderscore() async throws {
        // Intra-word underscore parsed as emphasis, re-serialized as '*'.
        try await assertRoundTripClean("emphasis-underscore.md")
    }

    func testThematicBreak() async throws {
        // '---' between paragraphs serialized back as an empty table.
        try await assertRoundTripClean("thematic-break.md")
    }

    func testSmokeKatex() async throws {
        // Broad fixture carrying both defects above (1x underscore, 4x '---').
        try await assertRoundTripClean("smoke-katex.md")
    }

    // MARK: - Known-open defects (documented, not fixed in this project)

    func testNestedList() async throws {
        // Defect: a blank line is inserted between a list item and its
        // nested child (tight list becomes loose). Discovered by the net,
        // not in the original incident list. See PHASE_3_ARCHITECTURE.md §12.
        XCTExpectFailure("Known defect: nested list gains a blank line on round-trip")
        try await assertRoundTripClean("nested-list.md")
    }
}
