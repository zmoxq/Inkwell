import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UniformTypeIdentifiers
#endif

// MARK: - MarkdownEditorView (SwiftUI)

struct MarkdownEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var markdownContent: String
    var documentURL: URL?
    var onContentChange: ((String) -> Void)?
    var onSaveRequest: (() -> Void)?
    var onCoordinatorReady: ((EditorCoordinator) -> Void)?
    
    var body: some View {
        EditorWebViewRepresentable(
            markdownContent: $markdownContent,
            themeCSS: appState.currentThemeCSS,
            documentURL: documentURL,
            onContentChange: onContentChange,
            onSaveRequest: onSaveRequest,
            onEditorReady: {
                appState.isEditorReady = true
            },
            onCoordinatorReady: onCoordinatorReady
        )
    }
}

// MARK: - Platform-specific Representable

#if os(macOS)
struct EditorWebViewRepresentable: NSViewRepresentable {
    @Binding var markdownContent: String
    let themeCSS: String
    var documentURL: URL?
    var onContentChange: ((String) -> Void)?
    var onSaveRequest: (() -> Void)?
    var onEditorReady: (() -> Void)?
    var onCoordinatorReady: ((EditorCoordinator) -> Void)?
    
    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            markdownContent: $markdownContent,
            themeCSS: themeCSS,
            documentURL: documentURL,
            onContentChange: onContentChange,
            onSaveRequest: onSaveRequest,
            onEditorReady: onEditorReady
        )
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = context.coordinator.createWebView()
        context.coordinator.loadEditorHTML()
        onCoordinatorReady?(context.coordinator)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.handleSwiftUIUpdate(
            markdown: markdownContent,
            theme: themeCSS
        )
    }
}
#else
struct EditorWebViewRepresentable: UIViewRepresentable {
    @Binding var markdownContent: String
    let themeCSS: String
    var documentURL: URL?
    var onContentChange: ((String) -> Void)?
    var onSaveRequest: (() -> Void)?
    var onEditorReady: (() -> Void)?
    var onCoordinatorReady: ((EditorCoordinator) -> Void)?
    
    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            markdownContent: $markdownContent,
            themeCSS: themeCSS,
            documentURL: documentURL,
            onContentChange: onContentChange,
            onSaveRequest: onSaveRequest,
            onEditorReady: onEditorReady
        )
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.createWebView()
        context.coordinator.loadEditorHTML()
        onCoordinatorReady?(context.coordinator)
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.handleSwiftUIUpdate(
            markdown: markdownContent,
            theme: themeCSS
        )
    }
}
#endif

// MARK: - Editor Coordinator

class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Binding var markdownContent: String
    var onContentChange: ((String) -> Void)?
    var onSaveRequest: (() -> Void)?
    var onEditorReady: (() -> Void)?
    
    /// Format state — set by ContentView, updated by selectionChange messages
    var formatState: EditorFormatState?
    /// Find/replace state — set by ContentView, updated by findResults messages
    var findReplaceState: FindReplaceState?
    
    private var webView: WKWebView!
    private var isEditorReady = false
    private var isUpdatingFromJS = false
    private var lastSentMarkdown: String = ""
    private var lastSentTheme: String = ""
    private var pendingMarkdown: String?
    private var pendingTheme: String?
    private var documentBaseURL: URL?
    #if os(iOS)
    var _carouselModeForPicker: Bool = false
    #endif
    
    init(
        markdownContent: Binding<String>,
        themeCSS: String,
        documentURL: URL?,
        onContentChange: ((String) -> Void)?,
        onSaveRequest: (() -> Void)?,
        onEditorReady: (() -> Void)?
    ) {
        self._markdownContent = markdownContent
        self.onContentChange = onContentChange
        self.onSaveRequest = onSaveRequest
        self.onEditorReady = onEditorReady
        self.documentBaseURL = documentURL?.deletingLastPathComponent()
        super.init()
        
        if !markdownContent.wrappedValue.isEmpty {
            self.pendingMarkdown = markdownContent.wrappedValue
        }
        if !themeCSS.isEmpty {
            self.pendingTheme = themeCSS
        }
    }
    
    // MARK: - WebView Setup
    
    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "inkwell")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        
        #if os(macOS)
        wv.setValue(false, forKey: "drawsBackground")
        #else
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.alwaysBounceVertical = true
        #endif
        
        #if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) {
            wv.isInspectable = true
        }
        #endif
        
        self.webView = wv
        return wv
    }
    
    func loadEditorHTML() {
        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") {
            // If we have a document directory, write a temp HTML there so images resolve
            if let baseDir = documentBaseURL {
                do {
                    let htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
                    let tempURL = baseDir.appendingPathComponent(".inkwell-editor.html")
                    try htmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
                    webView.loadFileURL(tempURL, allowingReadAccessTo: baseDir)
                    return
                } catch {
                    print("[Inkwell] Failed to write temp HTML: \(error)")
                }
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            print("[Inkwell] editor.html not in bundle, using embedded fallback")
            webView.loadHTMLString(Self.embeddedEditorHTML, baseURL: documentBaseURL)
        }
    }
    
    // MARK: - SwiftUI Update Handler
    
    func handleSwiftUIUpdate(markdown: String, theme: String) {
        guard !isUpdatingFromJS else { return }
        
        if theme != lastSentTheme {
            if isEditorReady { sendThemeToJS(theme) }
            else { pendingTheme = theme }
        }
        
        if markdown != lastSentMarkdown {
            if isEditorReady { sendMarkdownToJS(markdown) }
            else { pendingMarkdown = markdown }
        }
    }
    
    // MARK: - Swift → JS
    
    private func sendMarkdownToJS(_ markdown: String) {
        lastSentMarkdown = markdown
        let escaped = escapeForJS(markdown)
        webView.evaluateJavaScript("window.InkwellEditor.loadMarkdown(`\(escaped)`);") { _, error in
            if let error = error { print("[Inkwell] JS error loading markdown: \(error)") }
        }
    }
    
    private func sendThemeToJS(_ css: String) {
        lastSentTheme = css
        let escaped = escapeForJS(css)
        webView.evaluateJavaScript("window.InkwellEditor.applyTheme(`\(escaped)`);") { _, error in
            if let error = error { print("[Inkwell] JS error applying theme: \(error)") }
        }
    }
    
    func focus() {
        webView.evaluateJavaScript("window.InkwellEditor.focus();")
    }
    
    // MARK: - Find & Replace — Swift → JS
    
    func execFormat(_ format: String) {
        // format 可能是 "bold"，也可能是 "textColor:#FF3B30" 或 "bgColor:" 这种带参数形式
        let parts = format.split(separator: ":", maxSplits: 1).map(String.init)
        let cmd   = parts[0]
        let param = parts.count > 1 ? parts[1] : ""
        let escapedCmd   = escapeForJS(cmd)
        let escapedParam = escapeForJS(param)
        webView.evaluateJavaScript(
            "window.InkwellEditor.execFormat('\(escapedCmd)', '\(escapedParam)');"
        )
    }

    func findInDocument(_ query: String, caseSensitive: Bool) {
        let escaped = escapeForJS(query)
        webView.evaluateJavaScript("window.InkwellEditor.findInDocument(`\(escaped)`, \(caseSensitive));")
    }
    
    func findNext() {
        webView.evaluateJavaScript("window.InkwellEditor.findNext();")
    }
    
    func findPrevious() {
        webView.evaluateJavaScript("window.InkwellEditor.findPrevious();")
    }
    
    func replaceCurrent(_ replacement: String) {
        let escaped = escapeForJS(replacement)
        webView.evaluateJavaScript("window.InkwellEditor.replaceCurrent(`\(escaped)`);")
    }
    
    func replaceAll(_ replacement: String) {
        let escaped = escapeForJS(replacement)
        webView.evaluateJavaScript("window.InkwellEditor.replaceAll(`\(escaped)`);")
    }
    
    func closeFindReplace() {
        webView.evaluateJavaScript("window.InkwellEditor.closeFindReplace();")
    }
    
    // MARK: - Table of Contents
    
    func toggleTOC() {
        webView.evaluateJavaScript("window.InkwellEditor.toggleTOC();")
    }
    
    // MARK: - Zoom
    
    func setZoom(_ level: Int) {
        let scale = CGFloat(max(50, min(200, level))) / 100.0
        #if os(macOS)
        webView.pageZoom = scale
        #else
        webView.evaluateJavaScript("document.body.style.webkitTextSizeAdjust = '\(level)%';")
        #endif
        // Update status bar in JS
        webView.evaluateJavaScript("var z=document.getElementById('inkwell-stat-zoom');if(z)z.textContent='\(level)%';")
    }
    
    // MARK: - Export
    
    func exportHTML(completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.InkwellEditor.getHTMLForExport();") { result, error in
            completion(result as? String)
        }
    }
    
    // Retained during PDF export to prevent deallocation
    private var pdfExportWebView: WKWebView?
    private var pdfExportDelegate: PDFExportDelegate?
    
    func exportPDF(completion: @escaping (Data?) -> Void) {
        exportHTML { [weak self] html in
            guard let self = self, var html = html else {
                completion(nil)
                return
            }
            
            // Inject print-optimized CSS + reset zoom
            let printCSS = """
            <style>
            html { font-size: 100% !important; }
            html, body { height: auto !important; overflow: visible !important; margin: 0; padding: 0; }
            .editor-container { min-height: auto !important; padding: 0 !important; padding-bottom: 0 !important; }
            #editor {
                min-height: auto !important;
                max-width: 100% !important;
                padding: 20px 40px !important;
                margin: 0 !important;
                transform: none !important;
            }
            .inkwell-status-bar, .inkwell-toc-panel, .inkwell-slash-menu,
            .inkwell-drag-handle, .inkwell-fold-toggle { display: none !important; }
            pre { white-space: pre-wrap !important; word-wrap: break-word !important; }
            img { max-width: 100% !important; height: auto !important; page-break-inside: avoid; }
            table { page-break-inside: avoid; }
            h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
            </style>
            """
            html = html.replacingOccurrences(of: "</head>", with: printCSS + "</head>")
            
            DispatchQueue.main.async {
                let pageWidth: CGFloat = 595.28  // A4 width in points
                
                let config = WKWebViewConfiguration()
                let pdfView = WKWebView(frame: CGRect(x: 0, y: 0, width: pageWidth, height: 842), configuration: config)
                #if os(macOS)
                pdfView.setValue(false, forKey: "drawsBackground")
                #endif
                
                let delegate = PDFExportDelegate(pageWidth: pageWidth) { [weak self] data in
                    completion(data)
                    self?.pdfExportWebView = nil
                    self?.pdfExportDelegate = nil
                }
                
                self.pdfExportWebView = pdfView
                self.pdfExportDelegate = delegate
                
                pdfView.navigationDelegate = delegate
                pdfView.loadHTMLString(html, baseURL: self.documentBaseURL)
            }
        }
    }
    
    // MARK: - Scroll to Heading (outline navigation)
    
    func scrollToHeading(title: String, level: Int) {
        let escaped = escapeForJS(title)
        webView.evaluateJavaScript("window.InkwellEditor.scrollToHeading(`\(escaped)`, \(level));")
    }
    
    // MARK: - Link / Image
    
    func applyLink(url: String, text: String) {
        let escapedUrl = escapeForJS(url)
        let escapedText = escapeForJS(text)
        webView.evaluateJavaScript("window.InkwellEditor.applyLink(`\(escapedUrl)`, `\(escapedText)`);")
    }
    
    private func escapeForJS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "`", with: "\\`")
           .replacingOccurrences(of: "${", with: "\\${")
    }
    
    // MARK: - JS → Swift (WKScriptMessageHandler)
    
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "inkwell",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }
        
        let payload = json["data"] as? [String: Any] ?? [:]
        
        switch type {
        case "editorReady":
            isEditorReady = true
            if let theme = pendingTheme {
                sendThemeToJS(theme)
                pendingTheme = nil
            }
            if let markdown = pendingMarkdown {
                sendMarkdownToJS(markdown)
                pendingMarkdown = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.onEditorReady?()
            }
            
        case "contentChange", "contentChanged":
            guard let content = payload["content"] as? String else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isUpdatingFromJS = true
                self.lastSentMarkdown = content
                self.markdownContent = content
                self.onContentChange?(content)
                DispatchQueue.main.async {
                    self.isUpdatingFromJS = false
                }
            }
            
        case "save":
            DispatchQueue.main.async { [weak self] in
                if let content = payload["content"] as? String {
                    self?.markdownContent = content
                }
                self?.onSaveRequest?()
            }
            
        case "selectionChange":
            DispatchQueue.main.async { [weak self] in
                self?.formatState?.update(from: payload)
            }
            
        case "showFindReplace":
            DispatchQueue.main.async { [weak self] in
                self?.findReplaceState?.isVisible = true
                if payload["mode"] as? String == "replace" {
                    self?.findReplaceState?.showReplace = true
                }
            }
            
        case "findResults":
            DispatchQueue.main.async { [weak self] in
                self?.findReplaceState?.matchCount = payload["count"] as? Int ?? 0
                self?.findReplaceState?.currentMatch = payload["current"] as? Int ?? -1
            }
            
        case "requestLinkInput":
            // JS is asking for a link URL — show a native dialog
            let selectedText = payload["selectedText"] as? String ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.showLinkDialog(selectedText: selectedText)
            }
            
        case "requestImageInput":
            // JS is asking to pick an image file — open native file picker
            let carouselMode = payload["carouselMode"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.showImagePicker(carouselMode: carouselMode)
            }
            
        case "openLink":
            if let urlString = payload["url"] as? String, let url = URL(string: urlString) {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }
            
        case "zoomChanged":
            // Sync zoom state from JS (e.g. after setZoom)
            break
            
        default:
            break
        }
    }
    
    // MARK: - Image Picker

    private func showImagePicker(carouselMode: Bool) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Image"

        guard let window = webView.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            self.sendImageURLToJS(url: url, carouselMode: carouselMode)
        }
        #else
        // iOS: use UIDocumentPickerViewController for files, or PHPickerViewController for photos
        // PHPickerViewController is preferred (no permission prompt needed for read-only access)
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        self._carouselModeForPicker = carouselMode

        // Find the topmost view controller to present from
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(picker, animated: true)
        }
        #endif
    }

    #if os(macOS)
    private func sendImageURLToJS(url: URL, carouselMode: Bool) {
        // Copy image to document directory so it's accessible from the webview sandbox
        let fileName = url.lastPathComponent
        let dest: URL
        if let baseDir = documentBaseURL {
            dest = baseDir.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        } else {
            dest = url
        }
        let relativePath = dest.lastPathComponent
        let js: String
        if carouselMode {
            let escaped = relativePath.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "`", with: "\\`")
            js = "window.InkwellEditor.carouselReceiveImage(`\(escaped)`);"
        } else {
            let escaped = relativePath.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "`", with: "\\`")
            js = "window.InkwellEditor.applyImage(`\(escaped)`, ``);"
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js)
        }
    }
    #endif

    // MARK: - Link Dialog
    
    private func showLinkDialog(selectedText: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.informativeText = "Enter the URL:"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "https://"
        alert.accessoryView = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = inputField.stringValue
            if !url.isEmpty {
                let text = selectedText.isEmpty ? url : selectedText
                applyLink(url: url, text: text)
            }
        }
        #endif
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Navigation complete — JS will send editorReady
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Inkwell] WebView failed: \(error)")
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    // MARK: - Embedded Editor HTML Fallback
    
    /// Minimal fallback HTML — the real editor should be loaded from editor.html in the bundle.
    static let embeddedEditorHTML: String = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8">
    <style id="theme-style"></style>
    <style>html,body{margin:0;padding:0;height:100%}</style>
    </head><body>
    <div id="editor" contenteditable="true" style="outline:none;min-height:100vh;padding:40px 32px;max-width:760px;margin:0 auto;font-family:Georgia,serif;font-size:17px;line-height:1.75;">
    <p>Editor loading — please ensure editor.html is in the app bundle.</p>
    </div>
    <script>
    window.InkwellEditor = {
      loadMarkdown: function(md) { document.getElementById('editor').innerText = md; },
      getMarkdown: function() { return document.getElementById('editor').innerText; },
      applyTheme: function(css) { document.getElementById('theme-style').textContent = css; },
      execFormat: function(cmd) {},
      focus: function() { document.getElementById('editor').focus(); },
      findInDocument: function(){}, findNext: function(){}, findPrevious: function(){},
      replaceCurrent: function(){}, replaceAll: function(){}, closeFindReplace: function(){},
      applyLink: function(){}, applyImage: function(){}, insertTable: function(){}
    };
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.inkwell) {
      window.webkit.messageHandlers.inkwell.postMessage(JSON.stringify({type:'editorReady',data:{}}));
    }
    </script></body></html>
    """
}

// MARK: - iOS PHPickerViewControllerDelegate

#if os(iOS)
extension EditorCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            guard let self = self, let url = url else { return }

            // Copy to document directory so webview sandbox can read it
            let fileName = url.lastPathComponent
            let dest: URL
            if let baseDir = self.documentBaseURL {
                dest = baseDir.appendingPathComponent(fileName)
            } else {
                dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            }
            try? FileManager.default.copyItem(at: url, to: dest)

            let relativePath = dest.lastPathComponent
            let escaped = relativePath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")

            let js: String
            if self._carouselModeForPicker {
                js = "window.InkwellEditor.carouselReceiveImage(`\(escaped)`);"
            } else {
                js = "window.InkwellEditor.applyImage(`\(escaped)`, ``);"
            }

            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(js)
            }
        }
    }
}
#endif

// MARK: - PDF Export Delegate

class PDFExportDelegate: NSObject, WKNavigationDelegate {
    let completion: (Data?) -> Void
    let pageWidth: CGFloat
    
    init(pageWidth: CGFloat, completion: @escaping (Data?) -> Void) {
        self.pageWidth = pageWidth
        self.completion = completion
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Step 1: Wait for initial render, then measure actual content height
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, error in
                guard let self = self else { return }
                let contentHeight = (result as? CGFloat) ?? 842
                
                // Step 2: Resize webview to full content height so nothing is clipped
                webView.frame = CGRect(x: 0, y: 0, width: self.pageWidth, height: max(contentHeight, 842))
                
                // Step 3: Wait for relayout after resize, then generate PDF
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let pdfConfig = WKPDFConfiguration()
                    // Don't set pdfConfig.rect — let it use the full webview content
                    // WKWebView will automatically paginate into A4-ish pages
                    
                    webView.createPDF(configuration: pdfConfig) { result in
                        switch result {
                        case .success(let data):
                            self.completion(data)
                        case .failure(let error):
                            print("[Inkwell] PDF export error: \(error)")
                            self.completion(nil)
                        }
                    }
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Inkwell] PDF webview load failed: \(error)")
        completion(nil)
    }
}
