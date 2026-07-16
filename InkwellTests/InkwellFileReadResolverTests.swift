// =============================================================================
// InkwellFileReadResolverTests.swift
// =============================================================================
//
// Unit tests for the path resolver. Critical because a containment check
// failure = arbitrary file read vulnerability.
//
// Contract under test: D.15 revised (PHASE_3_ARCHITECTURE.md §11) —
// directory basis. Paths resolve against the note's directory; absolute
// paths and anything escaping that directory are rejected. No fixtures
// required: resolve() never touches the filesystem.
// -----------------------------------------------------------------------------

import XCTest
@testable import Inkwell

final class InkwellFileReadResolverTests: XCTestCase {

    // Helper: synthetic document URL "my-note.md" inside a workspace.
    private let docURL = URL(fileURLWithPath: "/Users/test/workspace/my-note.md")

    private func assertOK(_ result: InkwellFileReadResolver.Result, _ expectedPath: String,
                          file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .ok(let url):
            XCTAssertEqual(url.path, expectedPath, file: file, line: line)
        case .error(let e):
            XCTFail("expected success, got error \(e.rawValue)", file: file, line: line)
        }
    }

    private func assertError(_ result: InkwellFileReadResolver.Result, _ expected: InkwellFileReadError,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .ok(let url):
            XCTFail("expected error \(expected.rawValue), got \(url.path)", file: file, line: line)
        case .error(let e):
            XCTAssertEqual(e, expected, file: file, line: line)
        }
    }

    // MARK: - Happy paths

    func testAcceptsFileInAttachmentDir() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/AAPL.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/my-note/AAPL.csv")
    }

    func testAcceptsNestedSubdirectory() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/data/AAPL_2024.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/my-note/data/AAPL_2024.csv")
    }

    func testAcceptsRootLevelFile() {
        // Directory basis: files directly beside the note are readable,
        // matching what the image channel could always load.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "AAPL.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/AAPL.csv")
    }

    func testAcceptsOtherNoteSubdir() {
        // Cross-note references are allowed under the revised contract —
        // the boundary is the directory, same as the image channel.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "other-note/AAPL.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/other-note/AAPL.csv")
    }

    func testRenameInvariance() {
        // The rename fix: the same reference resolves identically for any
        // note filename in the same directory.
        let renamed = URL(fileURLWithPath: "/Users/test/workspace/renamed-note.md")
        let before = InkwellFileReadResolver.resolve(relativePath: "my-note/AAPL.csv", documentURL: docURL)
        let after = InkwellFileReadResolver.resolve(relativePath: "my-note/AAPL.csv", documentURL: renamed)
        guard case .ok(let beforeURL) = before, case .ok(let afterURL) = after else {
            XCTFail("expected both to resolve")
            return
        }
        XCTAssertEqual(beforeURL, afterURL)
    }

    func testDocnameWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/test/My Notes/Stock Recap.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "Stock Recap/AAPL.csv",
            documentURL: url
        )
        assertOK(result, "/Users/test/My Notes/Stock Recap/AAPL.csv")
    }

    func testDocnameWithDots() {
        let url = URL(fileURLWithPath: "/Users/test/workspace/v2.0 plan.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "v2.0 plan/data.csv",
            documentURL: url
        )
        assertOK(result, "/Users/test/workspace/v2.0 plan/data.csv")
    }

    func testDotLeadingDocumentNameResolvesByDirectory() {
        // Formerly the docname-derivation edge case (a note named ".md").
        // The directory basis has no docname concept: resolution works.
        let oddURL = URL(fileURLWithPath: "/Users/test/.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "anything/foo.csv",
            documentURL: oddURL
        )
        assertOK(result, "/Users/test/anything/foo.csv")
    }

    func testDotSlashPrefixNormalizes() {
        // "./x" standardizes to "x" inside the directory: allowed.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "./AAPL.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/AAPL.csv")
    }

    // MARK: - Absolute paths

    func testRejectsAbsolutePath() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "/etc/passwd",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    func testRejectsAbsolutePathIntoDirectory() {
        // Even an absolute path that would land inside the directory is
        // rejected — the contract requires the relative form.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "/Users/test/workspace/my-note/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    // MARK: - Path traversal

    func testRejectsParentTraversal() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/../../../etc/passwd",
            documentURL: docURL
        )
        assertError(result, .outsideAttachmentDir)
    }

    func testRejectsEscapeToSiblingDirectory() {
        // Leaves the note's directory entirely: out of bounds even though
        // the target is the user's own tree.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "../other-workspace/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .outsideAttachmentDir)
    }

    func testRejectsEscapeAndReturnAboveBoundary() {
        // Sneaks up one level and back into a prefix-confusable sibling:
        // "/Users/test/workspace-evil" shares the string prefix of
        // "/Users/test/workspace" — the trailing-slash check must catch it.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "../workspace-evil/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .outsideAttachmentDir)
    }

    func testTraversalWithinBoundsIsAllowed() {
        // Dips into a subfolder and back: never leaves the directory.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/../other-note/AAPL.csv",
            documentURL: docURL
        )
        assertOK(result, "/Users/test/workspace/other-note/AAPL.csv")
    }

    // MARK: - Degenerate paths

    func testRejectsEmptyPath() {
        assertError(
            InkwellFileReadResolver.resolve(relativePath: "", documentURL: docURL),
            .outsideAttachmentDir
        )
    }

    func testRejectsDotPath() {
        // "." resolves to the directory itself, not a file strictly inside it.
        assertError(
            InkwellFileReadResolver.resolve(relativePath: ".", documentURL: docURL),
            .outsideAttachmentDir
        )
    }

    func testRejectsFullRoundTripToDirectory() {
        // "my-note/.." lands exactly on the directory: rejected.
        assertError(
            InkwellFileReadResolver.resolve(relativePath: "my-note/..", documentURL: docURL),
            .outsideAttachmentDir
        )
    }
}
