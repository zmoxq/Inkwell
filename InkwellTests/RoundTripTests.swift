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

    /// Asserts a fixture round-trips to its golden `<name>.expected.md`
    /// (used for documented, semantics-preserving normalizations — see
    /// NORMALIZATION.md). Byte-exact modulo the EOF rule.
    private func assertRoundTrip(
        _ name: String, produces expectedName: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let input = try fixture(name)
        let output = try await harness().roundTrip(input)
        let expected = canonicalized(try fixture(expectedName))
        let actual = canonicalized(output)
        if expected != actual {
            XCTFail("Normalization mismatch \(name):\n\(firstDivergence(expected, actual))", file: file, line: line)
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
        // Golden: multi-line blockquotes fold to one line (soft-wrap
        // normalization, #7) — the only change from the source.
        try await assertRoundTrip("smoke-mermaid.md", produces: "smoke-mermaid.expected.md")
    }

    func testTable() async throws {
        // Guards that the thematic-break fix (header must contain a pipe)
        // did not break real GFM tables.
        try await assertRoundTripClean("table.md")
    }

    func testTableAlignment() async throws {
        // Default/center/right alignment markers must each round-trip
        // unchanged (serializeTable used to collapse everything to center).
        try await assertRoundTripClean("table-alignment.md")
    }

    func testNestedList() async throws {
        // Nested unordered list (2-space indent = parent '- ' marker width).
        try await assertRoundTripClean("nested-list.md")
    }

    func testNestedListOrdered() async throws {
        // Bullets nested under an ordered item (3-space indent = '3. '
        // marker width) — the smoke-katex sub-list shape.
        try await assertRoundTripClean("nested-list-ordered.md")
    }

    func testListSiblings() async throws {
        // An ordered list followed by an unordered list must stay two lists
        // (the bullet list must not be absorbed as ordered items).
        try await assertRoundTripClean("list-siblings.md")
    }

    // MARK: - Documented normalizations (assert against a golden)

    func testEmphasisMarkerNormalization() async throws {
        // Real _underscore_ / __double__ emphasis normalizes to * / ** —
        // a semantics-preserving marker normalization (NORMALIZATION.md).
        try await assertRoundTrip("emphasis-marker.md", produces: "emphasis-marker.expected.md")
    }

    func testSoftWrapFold() async throws {
        // Soft-wrapped lines fold into one reflowed paragraph line (#7,
        // CommonMark). Folding loses the wrap positions — a documented
        // normalization asserted against a golden.
        try await assertRoundTrip("soft-wrap.md", produces: "soft-wrap.expected.md")
    }

    func testHardBreak() async throws {
        // A hard line break (trailing '\') is preserved as a <br> and
        // serialized back to '\' — byte-exact, not a normalization.
        try await assertRoundTripClean("hard-break.md")
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
        // Golden: with #6/#7 landed, the only changes from the source are
        // documented normalizations (blockquote soft-wrap fold, block
        // adjacency). Formerly XCTExpectFailure; now green against a golden.
        try await assertRoundTrip("smoke-katex.md", produces: "smoke-katex.expected.md")
    }
}
