import AppKit
import SwiftUI

@MainActor
final class SidebarController {
    private struct SidebarPanel {
        let panel: NSPanel
        let screen: NSScreen
    }

    private let repository: WindowRepository
    private let settings: SettingsStore
    private var panels: [SidebarPanel] = []
    private var hideWorkItems: [ObjectIdentifier: DispatchWorkItem] = [:]
    private let width: CGFloat = 304
    private let edgeHandle: CGFloat = 6

    init(repository: WindowRepository, settings: SettingsStore) {
        self.repository = repository
        self.settings = settings
    }

    func rebuild() {
        panels.forEach { $0.panel.close() }
        panels.removeAll()
        guard settings.sidebarEnabled else { return }

        for screen in NSScreen.screens {
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let panel = NSPanel(
                contentRect: hiddenFrame(for: screen),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SidebarView(
                repository: repository,
                settings: settings,
                screenID: screenID,
                edge: settings.sidebarEdge
            ))
            panel.orderFrontRegardless()
            panels.append(SidebarPanel(panel: panel, screen: screen))
        }
    }

    func handlePointer(at point: CGPoint) {
        guard settings.sidebarEnabled else { return }
        for entry in panels {
            let frame = entry.screen.frame
            let isAtEdge: Bool
            switch settings.sidebarEdge {
            case .left:
                isAtEdge = abs(point.x - frame.minX) <= 3 && frame.minY...frame.maxY ~= point.y
            case .right:
                isAtEdge = abs(point.x - frame.maxX) <= 3 && frame.minY...frame.maxY ~= point.y
            }

            if isAtEdge {
                show(entry)
            } else if !entry.panel.frame.insetBy(dx: -12, dy: -8).contains(point) {
                scheduleHide(entry)
            }
        }
    }

    func toggle() {
        guard let entry = panels.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) ?? panels.first else { return }
        let isShown = abs(entry.panel.frame.minX - shownFrame(for: entry.screen).minX) < 2
        isShown ? hide(entry) : show(entry)
    }

    private func show(_ entry: SidebarPanel) {
        let key = ObjectIdentifier(entry.panel)
        hideWorkItems.removeValue(forKey: key)?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            entry.panel.animator().setFrame(shownFrame(for: entry.screen), display: true)
        }
    }

    private func scheduleHide(_ entry: SidebarPanel) {
        let key = ObjectIdentifier(entry.panel)
        hideWorkItems.removeValue(forKey: key)?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide(entry)
            self?.hideWorkItems.removeValue(forKey: key)
        }
        hideWorkItems[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
    }

    private func hide(_ entry: SidebarPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            entry.panel.animator().setFrame(hiddenFrame(for: entry.screen), display: true)
        }
    }

    private func shownFrame(for screen: NSScreen) -> CGRect {
        let frame = screen.visibleFrame
        let x = settings.sidebarEdge == .left ? frame.minX : frame.maxX - width
        return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
    }

    private func hiddenFrame(for screen: NSScreen) -> CGRect {
        let frame = screen.visibleFrame
        let x = settings.sidebarEdge == .left
            ? frame.minX - width + edgeHandle
            : frame.maxX - edgeHandle
        return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
    }
}
