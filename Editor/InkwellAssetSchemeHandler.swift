//
//  InkwellAssetSchemeHandler.swift
//  Inkwell
//
//  Phase 3 PR 2 — Web 扩展资产服务（URL scheme handler）
//
//  对 editor.html 暴露 `inkwell-asset:///<filename>` 路径，
//  从 app Bundle 的 WebAssets/ 文件夹读取资产文件。
//
//  好处：
//  - 资产跟随 app 二进制，用户更新 app 自动更新资产版本
//  - 不污染用户文档目录
//  - 不需要复制 IO，直接从 Bundle 读
//  - 所有未来扩展（KaTeX、自绘 timeline 等）共用此 handler
//
//  添加新资产：把文件丢进 Inkwell/WebAssets/ 并加入 Xcode target 的
//  Copy Bundle Resources 阶段，editor.html 即可通过
//  `inkwell-asset:///<filename>` 访问。详见 docs/WEBASSETS.md。
//

import Foundation
import WebKit

final class InkwellAssetSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Bundle 内 WebAssets 文件夹的 URL（启动时一次性解析）
    private let assetsRoot: URL?

    override init() {
        // WebAssets 是 Xcode 里的 folder reference（蓝色文件夹），其下文件
        // 会保留目录结构。也兼容作为 group（黄色文件夹）的情况——这时文件
        // 直接放在 Bundle 根目录。
        if let folderURL = Bundle.main.url(forResource: "WebAssets", withExtension: nil) {
            self.assetsRoot = folderURL
        } else {
            self.assetsRoot = Bundle.main.resourceURL
        }
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(makeError("missing url"))
            return
        }

        // 期望形如 inkwell-asset:///mermaid.min.js
        // url.path 给我们 "/mermaid.min.js"
        var assetPath = url.path
        if assetPath.hasPrefix("/") {
            assetPath.removeFirst()
        }

        // 安全：禁止路径穿越（".."）
        if assetPath.contains("..") || assetPath.isEmpty {
            urlSchemeTask.didFailWithError(makeError("invalid path: \(assetPath)"))
            return
        }

        guard let assetsRoot = assetsRoot else {
            urlSchemeTask.didFailWithError(makeError("WebAssets root not found in bundle"))
            return
        }

        let fileURL = assetsRoot.appendingPathComponent(assetPath)

        // 读文件
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(makeError("asset not found: \(assetPath)"))
            return
        }

        let mimeType = mimeTypeFor(path: assetPath)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                // 资产跟 app 走，可以放心长缓存
                "Cache-Control": "public, max-age=31536000, immutable"
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 同步实现，没什么可取消
    }

    // MARK: - Helpers

    private func mimeTypeFor(path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "js":   return "application/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "wasm": return "application/wasm"
        case "html": return "text/html; charset=utf-8"
        case "svg":  return "image/svg+xml"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf":  return "font/ttf"
        case "otf":  return "font/otf"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        default:     return "application/octet-stream"
        }
    }

    private func makeError(_ message: String) -> NSError {
        return NSError(
            domain: "InkwellAssetSchemeHandler",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
