// =============================================================================
// InteractiveEditTests.swift
// =============================================================================
//
// Round-trip net for the INTERACTIVE editing path (EditMode enter/leave,
// key dispatch), where the worst corruption — a heading absorbing an
// adjacent block's content — lives and which the pure parse->serialize net
// cannot reach. See tests/roundtrip/INTERACTIVE_PLAN.md.
//
// Approach A: drive the real editor in an offscreen WKWebView via EditMode
// intents and dispatched keydown events. Deletion guards are verified by
// asserting the keydown's default was prevented — the same keydown path a
// real key press takes, and a prevented default is what stops WebKit's
// native block merge. (execCommand-based deletion is deliberately NOT used
// to assert guards: execCommand fires neither keydown nor beforeinput, so
// it bypasses every guard and cannot represent the guarded real-key path.)
// -----------------------------------------------------------------------------

import XCTest
import WebKit
@testable import Inkwell

@MainActor
final class InteractiveEditTests: XCTestCase {

    private static var sharedHarness: RoundTripHarness?

    private func harness() async throws -> RoundTripHarness {
        if let h = Self.sharedHarness { return h }
        let h = RoundTripHarness()
        try await h.boot()
        Self.sharedHarness = h
        return h
    }

    private func canonicalized(_ s: String) -> String {
        var t = Substring(s)
        while t.hasSuffix("\n") { t = t.dropLast() }
        return String(t)
    }

    // MARK: - Edit-cycle round-trip (green baseline)

    func testEditCycleMath() async throws {
        let md = "$$\nE = mc^2\n$$\n"
        let out = try await harness().roundTripThroughEdit(md, blockSelector: ".inkwell-block-renderer")
        XCTAssertEqual(canonicalized(out), canonicalized(md))
        let violations = try await harness().invariantViolations()
        XCTAssertEqual(violations, [], "DOM integrity after math edit cycle")
    }

    func testEditCycleMermaid() async throws {
        let md = "```mermaid\ngraph TD\n  A --> B\n```\n"
        let out = try await harness().roundTripThroughEdit(md, blockSelector: ".inkwell-block-renderer")
        XCTAssertEqual(canonicalized(out), canonicalized(md))
        let violations = try await harness().invariantViolations()
        XCTAssertEqual(violations, [], "DOM integrity after mermaid edit cycle")
    }

    // MARK: - Existing deletion guard (green regression)

    func testBackspaceAtCodeStartIsGuarded() async throws {
        // A real Backspace at the very start of a code block is already
        // guarded (prevents merging the block into the previous element).
        let prevented = try await harness().keydownPreventedAtCodeStart(
            "## Heading\n\n```js\nconst x = 1;\n```\n", key: "Backspace"
        )
        XCTAssertTrue(prevented, "Backspace at code start must be prevented")
    }
}
