import Foundation

// MARK: - Security-scoped bookmark (PHASE_5A §二)
//
// Both macOS and iOS builds are sandboxed (ENABLE_APP_SANDBOX = YES,
// user-selected.read-write), so a user-chosen library folder is only reachable
// across launches through a security-scoped bookmark. macOS requires the
// `.withSecurityScope` option on both create and resolve; iOS does not expose
// that option (picker URLs are already scoped). This helper hides the split.
//
// Access lifecycle (startAccessing/stopAccessing pairing) is owned by AppState
// — see `activateLibrary` / `accessedSecurityScopedURL`. This type only turns a
// URL into bookmark Data and back.
enum SecurityScopedBookmark {
    static func create(from url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        return (url, isStale)
    }
}
