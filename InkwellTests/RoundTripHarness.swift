// =============================================================================
// RoundTripHarness.swift
// =============================================================================
//
// Drives the real editor.html in an offscreen WKWebView so the round-trip
// test net exercises the exact parser / decorator / serializer the app ships
// (same WebKit, same editor.html from the bundle, same inkwell-asset:// scheme
// handler). Hosted by Inkwell.app, so Bundle.main resolves to the app bundle
// exactly as in production.
//
// A single booted harness is reused across fixtures (loading mermaid/katex/
// hljs once), then loadMarkdown/getMarkdown run per fixture.
// -----------------------------------------------------------------------------

import Foundation
import WebKit

enum RoundTripError: Error {
    case editorHTMLNotFound
    case editorNeverReady
}

@MainActor
final class RoundTripHarness: NSObject, WKNavigationDelegate {

    private var webView: WKWebView!
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// Loads editor.html and waits until the editor engine and all vendored
    /// libraries are present.
    func boot() async throws {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        // Same scheme handler the app registers — serves inkwell-asset:///
        // scripts from the bundle's WebAssets.
        config.setURLSchemeHandler(InkwellAssetSchemeHandler(), forURLScheme: "inkwell-asset")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self

        guard let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            throw RoundTripError.editorHTMLNotFound
        }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loadContinuation = c
            webView.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
        }
        try await waitUntilReady()
    }

    // MARK: - Navigation delegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    // MARK: - Round-trip

    /// parse → decorate → serialize. Settles by polling getMarkdown until two
    /// consecutive reads agree, so async decoration/rendering can finish
    /// without a fixed sleep.
    func roundTrip(_ markdown: String) async throws -> String {
        _ = try await webView.evaluateJavaScript("window.InkwellEditor.loadMarkdown(\(jsStringLiteral(markdown)));")
        var previous = try await getMarkdown()
        for _ in 0..<40 {   // up to ~4s
            try await Task.sleep(nanoseconds: 100_000_000)
            let current = try await getMarkdown()
            if current == previous { return current }
            previous = current
        }
        return previous
    }

    // MARK: - Private

    private func getMarkdown() async throws -> String {
        let result = try await webView.evaluateJavaScript("window.InkwellEditor.getMarkdown()")
        return (result as? String) ?? ""
    }

    private func waitUntilReady() async throws {
        let readyExpr = """
        (typeof window.InkwellEditor === 'object'
         && typeof hljs !== 'undefined'
         && typeof katex !== 'undefined'
         && typeof mermaid !== 'undefined'
         && typeof LightweightCharts !== 'undefined')
        """
        for _ in 0..<200 {   // up to ~20s
            let result = try await webView.evaluateJavaScript(readyExpr)
            if (result as? Bool) == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw RoundTripError.editorNeverReady
    }

    /// Encodes a Swift string as a safe JS string literal (quotes included).
    private func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
}
