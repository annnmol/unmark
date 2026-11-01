import SwiftUI
import AppKit

struct WindowLifecycle: NSViewRepresentable {
    let onClose: () -> Void
    func makeNSView(context: Context) -> LifecycleView { LifecycleView(onClose: onClose) }
    func updateNSView(_ view: LifecycleView, context: Context) { view.onClose = onClose }
}

final class LifecycleView: NSView {
    var onClose: () -> Void
    private var closeObserver: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClose() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        guard let window else { return }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClose() }
        }
    }
    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
    }
}
