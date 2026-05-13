// =============================================================================
// InkwellFileReadResolverTests.swift
// =============================================================================
//
// Unit tests for the path resolver. Critical because boundary check failure
// = arbitrary file read vulnerability.
//
// Add to your test target. No fixtures required — tests construct synthetic
// URLs that don't need to exist on disk (resolve() doesn't hit the filesystem).
// -----------------------------------------------------------------------------

import XCTest
@testable import Inkwell   // adjust to your module name

final class InkwellFileReadResolverTests: XCTestCase {

    // Helper: synthetic document URL "my-note.md" inside a workspace.
    private let docURL = URL(fileURLWithPath: "/Users/test/workspace/my-note.md")

    // MARK: - Happy paths

    func testAcceptsFileInAttachmentDir() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/AAPL.csv",
            documentURL: docURL
        )
        switch result {
        case .ok(let url):
            XCTAssertEqual(url.path, "/Users/test/workspace/my-note/AAPL.csv")
        case .error(let e):
            XCTFail("expected success, got error \(e.rawValue)")
        }
    }

    func testAcceptsNestedSubdirectory() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/data/AAPL_2024.csv",
            documentURL: docURL
        )
        switch result {
        case .ok(let url):
            XCTAssertEqual(url.path, "/Users/test/workspace/my-note/data/AAPL_2024.csv")
        case .error(let e):
            XCTFail("expected success, got error \(e.rawValue)")
        }
    }

    // MARK: - Invalid prefix

    func testRejectsMissingPrefix() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    func testRejectsDotSlashPrefix() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "./AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    func testRejectsOtherNoteSubdir() {
        // CRITICAL: This is the "cross-document share" case forbidden by D.15.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "other-note/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    func testRejectsAbsolutePath() {
        let result = InkwellFileReadResolver.resolve(
            relativePath: "/etc/passwd",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    func testRejectsAbsoluteToAttachmentPath() {
        // Even an absolute path that resolves into attachment dir is rejected —
        // we require the relative form, not absolute.
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

    func testRejectsParentTraversalSubtle() {
        // Sneaks out then back in to a different name.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note/../other-note/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .outsideAttachmentDir)
    }

    func testRejectsPrefixSiblingAttack() {
        // Document is "my-note.md" → attachment dir is "my-note/".
        // A sibling dir "my-note-evil/" has the right prefix as a string but
        // is NOT inside "my-note/". The trailing-slash logic should catch this.
        let result = InkwellFileReadResolver.resolve(
            relativePath: "my-note-evil/AAPL.csv",
            documentURL: docURL
        )
        assertError(result, .invalidFilePrefix)
    }

    // MARK: - Edge cases

    func testEmptyDocnameRejected() {
        // Hypothetical: a document named ".md" (just the extension).
        // docName after deletingPathExtension would be empty → reject.
        let oddURL = URL(fileURLWithPath: "/Users/test/.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "anything/foo.csv",
            documentURL: oddURL
        )
        assertError(result, .noDocument)
    }

    func testDocnameWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/test/My Notes/Stock Recap.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "Stock Recap/AAPL.csv",
            documentURL: url
        )
        switch result {
        case .ok(let resolved):
            XCTAssertEqual(resolved.path, "/Users/test/My Notes/Stock Recap/AAPL.csv")
        case .error(let e):
            XCTFail("expected success, got \(e.rawValue)")
        }
    }

    func testDocnameWithDots() {
        // "report.v2.md" → docname "report.v2"
        let url = URL(fileURLWithPath: "/Users/test/workspace/report.v2.md")
        let result = InkwellFileReadResolver.resolve(
            relativePath: "report.v2/data.csv",
            documentURL: url
        )
        switch result {
        case .ok(let resolved):
            XCTAssertEqual(resolved.path, "/Users/test/workspace/report.v2/data.csv")
        case .error(let e):
            XCTFail("expected success, got \(e.rawValue)")
        }
    }

    // MARK: - Helpers

    private func assertError(
        _ result: InkwellFileReadResolver.Result,
        _ expected: InkwellFileReadError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .ok(let url):
            XCTFail("expected \(expected.rawValue), got success: \(url.path)", file: file, line: line)
        case .error(let actual):
            XCTAssertEqual(actual, expected, file: file, line: line)
        }
    }
}
