import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, GlobalInputHandler {
    private let settings = SettingsStore()
    private let repository = WindowRepository()
    private let learnedSearch = LearnedSearchStore()
    private lazy var viewModel = SwitcherViewModel(repository: repository, learnedSearch: learnedSearch)
    private lazy var switcherPanel = SwitcherPanelController(viewModel: viewModel, settings: settings)
    private lazy var sidebar = SidebarController(repository: repository, settings: settings)
    private let input = GlobalInputController()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var edgeGestureCommit: DispatchWorkItem?
    private var inputReady = false
    private var cancellables: Set<AnyCancellable> = []

    var isSwitcherVisible: Bool { viewModel.isVisible }

    func start() {
        NSApp.applicationIconImage = AppIcon.make()
        _ = switcherPanel
        viewModel.onWillCommit = { [weak self] in self?.cancelEdgeGestureCommit() }
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
        sidebar.rebuild()

        repository.$hasAccessibilityPermission
            .removeDuplicates()
            .sink { [weak self] hasPermission in
                guard let self else { return }
                if hasPermission {
                    self.installInput()
                    self.permissionWindow?.close()
                    self.permissionWindow = nil
                } else {
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
        edgeGestureCommit?.cancel()
        input.uninstall()
        repository.stop()
    }

    func presentSwitcher(mode: SwitcherMode, advanceImmediately: Bool) {
        cancelEdgeGestureCommit()
        repository.refresh(preferences: visibilityPreferences)
        viewModel.present(mode, advanceImmediately: advanceImmediately)
    }

    func moveSwitcherSelection(by offset: Int) {
        viewModel.moveSelection(by: offset)
    }

    func appendSwitcherQuery(_ text: String) {
        viewModel.appendToQuery(text)
    }

    func beginSwitcherSearch() {
        viewModel.beginSearch()
    }

    func deleteSwitcherQueryCharacter() {
        viewModel.deleteBackward()
    }

    func commitSwitcherSelection() {
        cancelEdgeGestureCommit()
        viewModel.commit()
    }

    func dismissSwitcher() {
        cancelEdgeGestureCommit()
        viewModel.dismiss()
    }

    func performSwitcherAction(_ action: WindowAction) {
        cancelEdgeGestureCommit()
        viewModel.perform(action, keepVisible: action == .close || action == .quitApplication)
    }

    func pointerMoved(to point: CGPoint) {
        sidebar.handlePointer(at: point)
    }

    func edgeScrolled(delta: Double) {
        edgeGestureCommit?.cancel()
        if !viewModel.isVisible {
            viewModel.present(.recent, advanceImmediately: false)
        }
        viewModel.moveSelection(by: delta < 0 ? 1 : -1)
        let workItem = DispatchWorkItem { [weak self] in self?.viewModel.commit() }
        edgeGestureCommit = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: workItem)
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

        Publishers.CombineLatest(settings.$sidebarEnabled, settings.$sidebarEdge)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.sidebar.rebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.sidebar.rebuild() }
            .store(in: &cancellables)
    }

    private func updateInputConfiguration() {
        input.configuration = GlobalInputConfiguration(
            replaceCommandTab: settings.replaceCommandTab,
            enableOptionTab: settings.enableOptionTab,
            enableFastSearch: settings.enableFastSearch,
            fastSearchModifier: settings.fastSearchModifier,
            directTyping: settings.directTyping
        )
    }

    private func installInput() {
        inputReady = input.install()
        rebuildMenu()
    }

    private func cancelEdgeGestureCommit() {
        edgeGestureCommit?.cancel()
        edgeGestureCommit = nil
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
        menu.addItem(withTitle: "Search Windows", action: #selector(showSearch), keyEquivalent: " ").target = self
        menu.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh Windows", action: #selector(refreshWindows), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if !repository.hasAccessibilityPermission {
            menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(showPermission), keyEquivalent: "").target = self
        } else if !inputReady {
            menu.addItem(withTitle: "Retry Global Shortcuts", action: #selector(retryInput), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QuickTab", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
    }

    @objc private func showSearch() {
        presentSwitcher(mode: .search, advanceImmediately: false)
    }

    @objc private func toggleSidebar() {
        sidebar.toggle()
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
            window.contentView = NSHostingView(rootView: SettingsView(
                settings: settings,
                onSidebarChange: { [weak self] in self?.sidebar.rebuild() }
            ))
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
        input.uninstall()
        installInput()
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
