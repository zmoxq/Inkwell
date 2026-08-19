#if os(iOS)
import UIKit
import UniformTypeIdentifiers

// MARK: - iOS folder picker (PHASE_5A §二)
//
// Presents the system folder picker (UIDocumentPickerViewController in folder
// mode) and hands back the chosen security-scoped folder URL. iOS-only: macOS
// keeps NSOpenPanel at its call sites. The presenter retains itself for the
// lifetime of the presentation (self-reference released in cleanup), so callers
// don't have to hold it — mirroring the image-picker pattern.
final class FolderPickerPresenter: NSObject, UIDocumentPickerDelegate {
    private var onPick: ((URL) -> Void)?
    private var keepAlive: FolderPickerPresenter?

    static func present(onPick: @escaping (URL) -> Void) {
        let presenter = FolderPickerPresenter()
        presenter.onPick = onPick
        presenter.keepAlive = presenter  // retain until the picker finishes

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = presenter

        guard let top = presenter.topViewController() else {
            presenter.cleanup()
            return
        }
        top.present(picker, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene?.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first { onPick?(url) }
        cleanup()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        cleanup()
    }

    private func cleanup() {
        onPick = nil
        keepAlive = nil
    }
}
#endif
