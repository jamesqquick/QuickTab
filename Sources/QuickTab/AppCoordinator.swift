import AppKit
import Combine
import Sparkle
import SwiftUI

struct TapRecoveryPolicy {
    private(set) var recoveryRequested = false
    private(set) var attemptCount = 0
    private var recoveryAvailable = true

    mutating func requestRecovery() -> Bool {
        recoveryRequested = true
        guard recoveryAvailable else { return false }
        recoveryAvailable = false
        return true
    }

    mutating func beginAttempt() {
        recoveryRequested = false
        attemptCount += 1
    }

    mutating func recordFailedAttempt() -> Bool {
        guard attemptCount < 2 else {
            reset()
            return false
        }
        recoveryRequested = true
        return true
    }

    mutating func finishCooldown() -> Bool {
        if recoveryRequested {
            guard attemptCount < 2 else {
                reset()
                return false
            }
            recoveryAvailable = false
            return true
        }
        reset()
        return false
    }

    mutating func reset() {
        recoveryRequested = false
        attemptCount = 0
        recoveryAvailable = true
    }
}

@MainActor
final class AppCoordinator: NSObject, GlobalInputHandler {
    private let updaterController: SPUStandardUpdaterController
    private let settings = SettingsStore()
    private let repository = WindowRepository()
    private lazy var viewModel = SwitcherViewModel(repository: repository)
    private lazy var switcherPanel = SwitcherPanelController(viewModel: viewModel, settings: settings)
    private let input = GlobalInputController()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var inputReady = false
    private var isRunning = false
    private var tapRecoveryPolicy = TapRecoveryPolicy()
    private var tapRecoveryWork: DispatchWorkItem?
    private var tapRecoveryCooldownWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    var isSwitcherVisible: Bool { viewModel.isVisible }

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        super.init()
    }

    func start() {
        isRunning = true
        NSApp.applicationIconImage = AppIcon.make()
        _ = switcherPanel
        viewModel.onWillCommit = { [weak self] in self?.cancelSwitcherSession() }
        input.handler = self
        updateInputConfiguration()
        repository.start { [weak self] in
            self?.visibilityPreferences ?? VisibilityPreferences(
                minimized: .bottom,
                hidden: .bottom,
                excludedBundleIDs: []
            )
        }
        configureMenuBar()
        observeSettings()

        repository.$hasAccessibilityPermission
            .removeDuplicates()
            .sink { [weak self] hasPermission in
                guard let self else { return }
                if hasPermission {
                    self.resetTapRecovery()
                    self.installInput()
                    self.permissionWindow?.close()
                    self.permissionWindow = nil
                } else {
                    self.resetTapRecovery()
                    self.input.uninstall()
                    self.inputReady = false
                    self.showPermissionWindow()
                }
                self.rebuildMenu()
            }
            .store(in: &cancellables)

        if repository.hasAccessibilityPermission {
            installInput()
        } else {
            showPermissionWindow()
        }
    }

    func stop() {
        isRunning = false
        resetTapRecovery()
        viewModel.dismiss()
        input.uninstall()
        repository.stop()
    }

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        repository.refresh(preferences: visibilityPreferences)
        input.registerSwitcherPresentation()
        viewModel.present(mode, advanceImmediately: advanceImmediately)
    }

    func moveSwitcherSelection(by offset: Int) {
        viewModel.moveSelection(by: offset)
    }

    func commitSwitcherSelection() {
        cancelSwitcherSession()
        viewModel.commit()
    }

    func dismissSwitcher() {
        cancelSwitcherSession()
        viewModel.dismiss()
    }

    func performSwitcherAction(_ action: WindowAction) {
        if action == .minimize || action == .hideApplication {
            input.cancelActiveSwitcherSession()
        }
        viewModel.perform(action, keepVisible: action == .close || action == .quitApplication)
    }

    func pointerPressed(at point: CGPoint) {
        guard viewModel.isVisible, switcherPanel.shouldDismissPointerPress(at: point) else { return }
        dismissSwitcher()
    }

    func inputSessionDidReset() {
        viewModel.dismiss()
    }

    func inputTapDidDisable() {
        inputReady = false
        input.uninstall()
        rebuildMenu()

        guard tapRecoveryPolicy.requestRecovery() else { return }
        scheduleTapRecovery(after: 0.5)
    }

    private func scheduleTapRecovery(after delay: TimeInterval) {
        tapRecoveryWork?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.tapRecoveryWork = nil
            guard self.repository.hasAccessibilityPermission else {
                self.tapRecoveryPolicy.reset()
                return
            }
            self.tapRecoveryPolicy.beginAttempt()
            self.installInput()
            guard self.inputReady else {
                if self.tapRecoveryPolicy.recordFailedAttempt() {
                    self.scheduleTapRecovery(after: 5)
                }
                return
            }
            self.scheduleTapRecoveryCooldown()
        }
        tapRecoveryWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private var visibilityPreferences: VisibilityPreferences {
        VisibilityPreferences(
            minimized: settings.minimizedVisibility,
            hidden: settings.hiddenVisibility,
            excludedBundleIDs: settings.excludedBundleIDs
        )
    }

    private func observeSettings() {
        settings.objectWillChange
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateInputConfiguration()
                    self.repository.refresh(preferences: self.visibilityPreferences)
                }
            }
            .store(in: &cancellables)

    }

    private func updateInputConfiguration() {
        input.configuration = GlobalInputConfiguration(
            replaceCommandTab: settings.replaceCommandTab,
            enableOptionTab: settings.enableOptionTab
        )
    }

    private func installInput() {
        inputReady = input.install()
        rebuildMenu()
    }

    private func cancelSwitcherSession() {
        input.cancelActiveSwitcherSession()
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "QuickTab")
            button.image?.isTemplate = true
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let ready = repository.hasAccessibilityPermission && inputReady
        let statusTitle: String
        if !repository.hasAccessibilityPermission {
            statusTitle = "Accessibility access required"
        } else if !inputReady {
            statusTitle = "Global shortcuts unavailable"
        } else {
            statusTitle = "QuickTab is ready"
        }
        let status = NSMenuItem(
            title: statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        status.image = NSImage(
            systemSymbolName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Windows", action: #selector(refreshWindows), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        let checkForUpdates = menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdates.target = updaterController
        if !repository.hasAccessibilityPermission {
            menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(showPermission), keyEquivalent: "").target = self
        } else if !inputReady {
            menu.addItem(withTitle: "Retry Global Shortcuts", action: #selector(retryInput), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QuickTab", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
    }

    @objc private func refreshWindows() {
        repository.refresh(preferences: visibilityPreferences)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "QuickTab Settings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showPermission() {
        showPermissionWindow()
    }

    @objc private func retryInput() {
        resetTapRecovery()
        input.uninstall()
        installInput()
    }

    private func resetTapRecovery() {
        tapRecoveryWork?.cancel()
        tapRecoveryWork = nil
        tapRecoveryCooldownWork?.cancel()
        tapRecoveryCooldownWork = nil
        tapRecoveryPolicy.reset()
    }

    private func scheduleTapRecoveryCooldown() {
        tapRecoveryCooldownWork?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.tapRecoveryCooldownWork = nil
            if self.tapRecoveryPolicy.finishCooldown() {
                self.scheduleTapRecovery(after: 0.5)
            }
        }
        tapRecoveryCooldownWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }

    private func showPermissionWindow() {
        if permissionWindow == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 500, height: 590),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to QuickTab"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionView { [weak self] in
                self?.repository.requestAccessibilityPermission()
            })
            window.center()
            permissionWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
