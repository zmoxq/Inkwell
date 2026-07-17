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
        try await injectInteractiveHelpers()
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

    // MARK: - Interactive editing (INTERACTIVE_PLAN Approach A)

    /// Loads markdown and settles, without serializing.
    func load(_ markdown: String) async throws {
        _ = try await webView.evaluateJavaScript("window.InkwellEditor.loadMarkdown(\(jsStringLiteral(markdown)));")
        try await Task.sleep(nanoseconds: 600_000_000)
    }

    /// Enters edit on the first block matching `selector`, leaves edit, then
    /// returns the serialized markdown.
    func roundTripThroughEdit(_ markdown: String, blockSelector: String) async throws -> String {
        try await load(markdown)
        _ = try await webView.evaluateJavaScript("window.__IE.editCycle(\(jsStringLiteral(blockSelector)))")
        try await Task.sleep(nanoseconds: 400_000_000)
        return try await getMarkdown()
    }

    /// Places the caret at the END of the first block matching `selector`,
    /// dispatches a keydown, and returns whether the editor prevented its
    /// default action. A real key press takes this same keydown path; a
    /// prevented default is what stops WebKit's native block merge (the
    /// heading-absorption corruption). Caret placement and dispatch happen
    /// in one evaluation so the selection persists.
    func keydownPreventedAtEndOf(_ markdown: String, selector: String, key: String) async throws -> Bool {
        try await load(markdown)
        let js = "(function(){ if(!window.__IE.caretEndOf(\(jsStringLiteral(selector)))) return null; return window.__IE.pressKey(\(jsStringLiteral(key))); })()"
        let result = try await webView.evaluateJavaScript(js)
        return (result as? Bool) ?? false
    }

    /// Places the caret at the START of the first code block's content,
    /// dispatches a keydown, returns whether the default was prevented.
    func keydownPreventedAtCodeStart(_ markdown: String, key: String) async throws -> Bool {
        try await load(markdown)
        let js = "(function(){ if(!window.__IE.caretStartOfCode()) return null; return window.__IE.pressKey(\(jsStringLiteral(key))); })()"
        let result = try await webView.evaluateJavaScript(js)
        return (result as? Bool) ?? false
    }

    /// DOM-integrity invariant violations in the current document (empty =
    /// clean). Detects the corruption signatures from INTERACTIVE_PLAN §4b.
    func invariantViolations() async throws -> [String] {
        let result = try await webView.evaluateJavaScript("window.__IE.invariants()")
        return (result as? [String]) ?? []
    }

    // MARK: - Private

    private func getMarkdown() async throws -> String {
        let result = try await webView.evaluateJavaScript("window.InkwellEditor.getMarkdown()")
        return (result as? String) ?? ""
    }

    /// Injects the interactive-edit test helpers (caret placement, key
    /// dispatch, edit cycle, invariant checker) as `window.__IE`.
    private func injectInteractiveHelpers() async throws {
        let helpers = """
        window.__IE = {
          ed: document.getElementById('editor'),
          caretEndOf: function(sel){ var el=this.ed.querySelector(sel); if(!el) return false; this.ed.focus(); var r=document.createRange(); r.selectNodeContents(el); r.collapse(false); var s=getSelection(); s.removeAllRanges(); s.addRange(r); return true; },
          caretStartOfCode: function(){ var code=this.ed.querySelector('pre code'); if(!code) return false; this.ed.focus(); var r=document.createRange(); r.setStart(code.firstChild||code,0); r.collapse(true); var s=getSelection(); s.removeAllRanges(); s.addRange(r); return true; },
          pressKey: function(key){ var e=new KeyboardEvent('keydown',{key:key,bubbles:true,cancelable:true}); this.ed.dispatchEvent(e); return e.defaultPrevented; },
          editCycle: function(sel){ var el=this.ed.querySelector(sel); if(!el||typeof EditMode==='undefined') return false; EditMode.requestEnterEdit(el,{via:'click'}); var f=this.ed.querySelector('pre[data-block-type]') || (this.ed.querySelector('code.inkwell-live-fence') && this.ed.querySelector('code.inkwell-live-fence').closest('pre')); if(!f) return false; EditMode.requestLeaveEdit(f); return true; },
          invariants: function(){ var v=[]; var ed=this.ed;
            ed.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h){ if(h.querySelector('pre,div,table,ul,ol,blockquote')) v.push('block-in-heading'); h.querySelectorAll('span[style]').forEach(function(s){ if(/color/.test(s.getAttribute('style')||'')) v.push('styled-span-in-heading'); }); });
            ed.querySelectorAll('span[style]').forEach(function(s){ if(/color/.test(s.getAttribute('style')||'') && !s.closest('pre') && !s.closest('code')) v.push('color-span-loose'); });
            if(typeof EditMode!=='undefined' && EditMode._editingFence!==null) v.push('stuck-editingFence');
            return v; }
        };
        """
        _ = try await webView.evaluateJavaScript(helpers)
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
