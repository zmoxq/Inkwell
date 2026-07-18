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

    // MARK: - Forward-delete heading absorption (the worst corruption)

    func testDeleteAtHeadingEndBeforeCodeIsGuarded() async throws {
        // Delete at the end of a heading whose next block is a rendered code
        // block used to merge the code (with hljs colors leaking as inline
        // <span style>) into the heading — the disk corruption
        // '## Heading<span style="color:...">const...'. A real Delete key
        // must be prevented so the native merge never happens.
        let prevented = try await harness().keydownPreventedAtEndOf(
            "## Heading\n\n```js\nconst x = 1;\n```\n", selector: "h2", key: "Delete"
        )
        XCTAssertTrue(prevented, "Delete at heading end before a code block must be prevented")
    }

    func testDeleteAtParagraphEndBeforeCodeIsGuarded() async throws {
        let prevented = try await harness().keydownPreventedAtEndOf(
            "Paragraph text\n\n```js\nconst x = 1;\n```\n", selector: "p", key: "Delete"
        )
        XCTAssertTrue(prevented, "Delete at paragraph end before a code block must be prevented")
    }

    // MARK: - Cross-block selection delete (Approach A: conservative guard)

    func testCrossBlockDeletePartialCutIsGuarded() async throws {
        // A selection from a heading's end into the MIDDLE of a code block
        // would leave the code's tail behind, textified into the heading
        // (hljs colors leaking as inline HTML). Such a partial cut must be
        // prevented.
        let prevented = try await harness().keydownPreventedForCrossBlock(
            "## Heading\n\n```js\nconst x = 1;\n```\n", fromSelector: "h2", codeFraction: 0.4, key: "Delete"
        )
        XCTAssertTrue(prevented, "Partial cross-block cut into a code block must be prevented")
    }

    func testCrossBlockDeleteFullBlockIsAllowed() async throws {
        // Selecting through the code block's END fully removes it — no
        // remnant, no corruption — and must NOT be prevented.
        let prevented = try await harness().keydownPreventedForCrossBlock(
            "## Heading\n\n```js\nconst x = 1;\n```\n", fromSelector: "h2", codeFraction: 1.0, key: "Delete"
        )
        XCTAssertFalse(prevented, "Deleting a fully-selected code block must be allowed")
    }

    // MARK: - Shift+Enter hard break (#7)

    func testShiftEnterInsertsHardBreak() async throws {
        // Shift+Enter inside a paragraph inserts a deterministic <br> and
        // serializes it as a trailing backslash hard break, round-tripping
        // byte-exact.
        let (prevented, brCount) = try await harness().shiftEnter(
            "hello world", selector: "p", offset: 5
        )
        XCTAssertTrue(prevented, "Shift+Enter must be handled")
        XCTAssertEqual(brCount, 1, "Shift+Enter inserts exactly one <br>")
        let out = try await harness().serialize()
        XCTAssertTrue(out.contains("\\\n"), "hard break serializes to a trailing backslash; got \(out)")
    }

    func testShiftEnterGuardedDuringComposition() async throws {
        // During IME composition, Shift+Enter must NOT be intercepted (the
        // composed segment must never be split).
        let (prevented, brCount) = try await harness().shiftEnter(
            "abc", selector: "p", offset: 3, composing: true
        )
        XCTAssertFalse(prevented, "Shift+Enter must not be intercepted mid-composition")
        XCTAssertEqual(brCount, 0, "no <br> inserted during composition")
    }

    // MARK: - beforeinput backstop (menu / dictation / system replace)
    //
    // These deletion paths fire beforeinput without a keydown, bypassing the
    // keydown guards. The beforeinput backstop must catch the same
    // corrupting cases.

    func testBeforeInputForwardDeleteAtBoundaryGuarded() async throws {
        let prevented = try await harness().beforeinputPreventedAtEndOf(
            "## Heading\n\n```js\nconst x = 1;\n```\n", selector: "h2", inputType: "deleteContentForward"
        )
        XCTAssertTrue(prevented, "beforeinput forward-delete at a heading/code boundary must be prevented")
    }

    func testBeforeInputBackwardDeleteAtCodeStartGuarded() async throws {
        let prevented = try await harness().beforeinputPreventedAtCodeStart(
            "## Heading\n\n```js\nconst x = 1;\n```\n", inputType: "deleteContentBackward"
        )
        XCTAssertTrue(prevented, "beforeinput backward-delete at a code block start must be prevented")
    }

    func testBeforeInputCrossBlockPartialCutGuarded() async throws {
        let prevented = try await harness().beforeinputPreventedForCrossBlock(
            "## Heading\n\n```js\nconst x = 1;\n```\n", fromSelector: "h2", codeFraction: 0.4,
            inputType: "deleteContentBackward"
        )
        XCTAssertTrue(prevented, "beforeinput partial cross-block cut must be prevented")
    }

    func testBeforeInputMidContentAllowed() async throws {
        // A delete not at a protected boundary must pass through the backstop
        // untouched (no over-prevention of normal editing).
        let prevented = try await harness().beforeinputPreventedAtEndOf(
            "para one\n\npara two", selector: "p", inputType: "deleteContentForward"
        )
        XCTAssertFalse(prevented, "beforeinput delete away from a protected boundary must be allowed")
    }
}
