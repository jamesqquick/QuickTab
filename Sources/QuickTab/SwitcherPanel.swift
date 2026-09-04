import AppKit
import SwiftUI

@MainActor
final class SwitcherPanelController {
    private let viewModel: SwitcherViewModel
    private let settings: SettingsStore
    private var panels: [NSPanel] = []

    init(viewModel: SwitcherViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
        viewModel.onVisibilityChange = { [weak self] visible in
            visible ? self?.show() : self?.hide()
        }
    }

    func show() {
        rebuildPanels()
        panels.forEach { $0.orderFrontRegardless() }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    func shouldDismissPointerPress(at screenPoint: CGPoint) -> Bool {
        Self.shouldDismissPointerPress(at: screenPoint, panelFrames: panels.map(\.frame))
    }

    static func shouldDismissPointerPress(at screenPoint: CGPoint, panelFrames: [CGRect]) -> Bool {
        !panelFrames.contains { $0.contains(screenPoint) }
    }

    private func rebuildPanels() {
        panels.forEach { $0.close() }
        panels.removeAll()

        let targetScreens: [NSScreen]
        if settings.showOnAllDisplays {
            targetScreens = NSScreen.screens
        } else {
            targetScreens = [screenUnderPointer() ?? NSScreen.main].compactMap { $0 }
        }

        for screen in targetScreens {
            let visibleFrame = screen.visibleFrame
            let width = min(660, visibleFrame.width - 56)
            let height = min(690, visibleFrame.height - 96)
            let origin = CGPoint(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2
            )
            let panel = NSPanel(
                contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SwitcherView(viewModel: viewModel, settings: settings))
            panels.append(panel)
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
