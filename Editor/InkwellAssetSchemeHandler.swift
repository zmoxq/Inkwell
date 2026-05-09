//
//  InkwellAssetSchemeHandler.swift
//  Inkwell
//
//  Phase 3 PR 2 — Web 扩展资产服务（URL scheme handler）
//  Phase 3 PR 3 — 加 Bundle.main 路径兜底,适配 Xcode 16 synchronized groups
//
//  对 editor.html 暴露 `inkwell-asset:///<path>` 路径，从 app Bundle 内
//  的 WebAssets/ 文件夹读取资产文件。
//
//  好处：
//  - 资产跟随 app 二进制，用户更新 app 自动更新资产版本
//  - 不污染用户文档目录
//  - 不需要复制 IO，直接从 Bundle 读
//  - 所有未来扩展（KaTeX、自绘 timeline 等）共用此 handler
//
//  关于 Bundle 内资产布局（2026-05-08 弄清楚的事实，PR 3 期间）:
//  Inkwell 当前用 Xcode 16 引入的 file system synchronized groups（蓝色文件夹）
//  在 Project Navigator 里显示。但这跟旧式 folder reference 行为不同 ——
//  synchronized groups 在 build 时把所有内嵌文件平铺到 .app/Contents/Resources/
//  根目录，不保留磁盘上的子目录结构。即源码里 WebAssets/katex/katex.min.js
//  在 build 后位于 .app/Contents/Resources/katex.min.js（不在子目录下）。
//
//  本 handler 因此采用两层查找：
//  1. 优先按子目录路径查找（兼容未来若 Xcode 改回保留结构 / 用户自己手工
//     组织 Bundle 时）
//  2. 找不到时 fallback 到 Bundle.main.url(forResource:) 按 basename 查找
//     （适配当前 synchronized groups 的平铺现状）
//
//  这样 editor.html 里的 inkwell-asset:///katex/katex.min.js 路径仍然有意义
//  （表达"这是 KaTeX 扩展的 JS 库"），即使 Bundle 内实际平铺存放也不影响加载。
//  KaTeX CSS 内 url(fonts/KaTeX_Main-Regular.woff2) 相对路径同理：
//  会请求 inkwell-asset:///katex/fonts/KaTeX_Main-Regular.woff2，
//  子目录找不到，按 basename "KaTeX_Main-Regular.woff2" fallback 命中。
//
//  添加新资产：把文件丢进 Inkwell/Resources/WebAssets/<extension-name>/，
//  Xcode 会自动收进 Bundle（synchronized group 行为）。详见 docs/WEBASSETS.md
//  和 PHASE_3_ARCHITECTURE.md 附录 C.5.1。
//

import Foundation
import WebKit

final class InkwellAssetSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Bundle 内 WebAssets 文件夹的 URL（启动时一次性解析）
    private let assetsRoot: URL?

    override init() {
        // 历史背景：本字段最初是为旧式 folder reference（蓝色文件夹但保留目录
        // 结构的版本）设计的，期望从 WebAssets/<path> 直接读。
        //
        // Xcode 16 synchronized groups 改变了行为 —— 子目录被平铺到 Bundle
        // 资源根目录（即 Bundle.main.resourceURL）。现在 assetsRoot 实际上
        // 大多数情况会等于 Bundle.main.resourceURL（因为 forResource: "WebAssets"
        // 找不到一个真正叫 WebAssets 的目录）。
        //
        // 保留这个查找作为"先按相对路径试一下"的优化路径 —— 万一 Xcode 项目
        // 配置改回保留结构，或者将来某种新机制让子目录真的存在 ——
        // 子目录命中时不需要走 Bundle.main basename fallback。
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

        // 两层查找:
        // 1. 子目录路径（兼容未来 Xcode 行为变化或手工组织的 Bundle）
        // 2. Bundle.main.url(forResource:) 按 basename（适配 Xcode 16
        //    synchronized groups 的平铺现状）
        let data: Data
        if let subpathData = try? Data(contentsOf: assetsRoot.appendingPathComponent(assetPath)) {
            data = subpathData
        } else if let fallbackURL = bundleFallbackURL(for: assetPath),
                  let fallbackData = try? Data(contentsOf: fallbackURL) {
            data = fallbackData
        } else {
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

    /// 把 path 拆成 basename + extension,通过 Bundle.main.url(forResource:withExtension:)
    /// 在整个 Bundle 资源里查找 —— 适配 Xcode 16 synchronized groups 平铺布局。
    ///
    /// 例 1:assetPath = "katex/katex.min.js" → basename "katex.min", ext "js"
    ///       → Bundle.main.url(forResource: "katex.min", withExtension: "js")
    /// 例 2:assetPath = "katex/fonts/KaTeX_Main-Regular.woff2"
    ///       → basename "KaTeX_Main-Regular", ext "woff2"
    ///       → Bundle.main.url(forResource: "KaTeX_Main-Regular", withExtension: "woff2")
    ///
    /// 注意:Bundle.main.url(forResource:) 在整个 Resources 目录递归查找,所以
    /// 即使资产平铺在根目录或散落在某个子目录里都能命中。
    private func bundleFallbackURL(for assetPath: String) -> URL? {
        let filename = (assetPath as NSString).lastPathComponent
        let ext = (filename as NSString).pathExtension
        let nameNoExt = (filename as NSString).deletingPathExtension
        if nameNoExt.isEmpty { return nil }
        return Bundle.main.url(forResource: nameNoExt, withExtension: ext.isEmpty ? nil : ext)
    }

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
