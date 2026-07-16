// =============================================================================
// TagBarView.swift
// =============================================================================
//
// Tag chip row (Phase 4 PR 4): pinned between the toolbar and the editor,
// outside the WKWebView — document content scrolls beneath it. Reads and
// writes user.tags through SidecarStore; the sidecar on disk is the source
// of truth and local state is a display cache, reloaded per tab (the editor
// block's identity is doc.id) and on rename (document.url change).
//
// Empty state stays near-invisible: a faint tag glyph at ~25% opacity,
// revealed with an "Add Tag" label when the row is hovered. Row height is
// constant so adding/removing tags never shifts the WebView.
// -----------------------------------------------------------------------------

import SwiftUI

struct TagBarView: View {
    /// Observed so a rename (url change) re-renders and reloads the row.
    @ObservedObject var document: MarkdownDocument

    /// Editability of the sidecar behind the row.
    enum SidecarAccess {
        case writable
        /// schemaVersion newer than this build: view only.
        case readOnly(version: Int)
        /// Sidecar exists but couldn't be parsed: view nothing, edit nothing.
        case unreadable
    }

    @State private var tags: [String] = []
    @State private var access: SidecarAccess = .writable
    @State private var isAdding = false
    @State private var newTag = ""
    @State private var isRowHovered = false
    @State private var saveFailed = false
    @FocusState private var addFieldFocused: Bool

    private var canEdit: Bool {
        if case .writable = access { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag, canEdit: canEdit) { removeTag(tag) }
            }

            if canEdit {
                if isAdding {
                    addField
                } else {
                    addButton
                }
            } else {
                accessNotice
            }

            if saveFailed {
                Text("Couldn't save tags")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        .onAppear(perform: reload)
        .onChange(of: document.url) { _, _ in reload() }
    }

    // MARK: - Add affordance

    /// Near-invisible at rest (faint glyph), fully visible with a label on
    /// row hover. Constant height either way.
    private var addButton: some View {
        Button {
            saveFailed = false
            isAdding = true
            newTag = ""
            addFieldFocused = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                if isRowHovered {
                    Text("Add Tag")
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(.primary.opacity(isRowHovered ? 0.6 : 0.25))
        }
        .buttonStyle(.plain)
        .help("Add Tag")
    }

    /// Shown instead of the add button when the sidecar can't be edited.
    /// Jargon-free: the user never needs to know what a sidecar is.
    private var accessNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForAccess)
                .font(.system(size: 10))
            if isRowHovered {
                Text(noticeForAccess)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary.opacity(isRowHovered ? 1.0 : 0.5))
        .help(noticeForAccess)
    }

    private var iconForAccess: String {
        if case .readOnly = access { return "lock" }
        return "exclamationmark.triangle"
    }

    private var noticeForAccess: String {
        switch access {
        case .readOnly:
            return "Created by a newer version of Inkwell — view only."
        case .unreadable:
            return "This note's extra info couldn't be read."
        case .writable:
            return ""
        }
    }

    private var addField: some View {
        TextField("Tag name", text: $newTag)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .frame(width: 100)
            .focused($addFieldFocused)
            .onSubmit(commitNewTag)
            #if os(macOS)
            .onExitCommand { isAdding = false }
            #endif
    }

    // MARK: - Mutations

    private func commitNewTag() {
        isAdding = false
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        save(tags + [tag])
    }

    private func removeTag(_ tag: String) {
        save(tags.filter { $0 != tag })
    }

    /// Optimistic update, rolled back if the disk write fails.
    private func save(_ newTags: [String]) {
        let previous = tags
        tags = newTags
        saveFailed = false
        do {
            try SidecarStore.setTags(newTags, forMarkdownAt: document.url)
        } catch {
            print("[Inkwell] Failed to save tags for \(document.url.lastPathComponent): \(error)")
            tags = previous
            saveFailed = true
        }
    }

    // MARK: - Loading

    private func reload() {
        isAdding = false
        saveFailed = false
        do {
            switch try SidecarStore.read(forMarkdownAt: document.url) {
            case .absent:
                tags = []
                access = .writable
            case .writable(let doc):
                tags = doc.tags
                access = .writable
            case .readOnly(let doc, let version):
                tags = doc.tags
                access = .readOnly(version: version)
            }
        } catch {
            print("[Inkwell] Failed to read sidecar for \(document.url.lastPathComponent): \(error)")
            tags = []
            access = .unreadable
        }
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: String
    let canEdit: Bool
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
            if canEdit && isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove Tag")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .onHover { isHovered = $0 }
    }
}
