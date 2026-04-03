import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private let store: AppStore

    init(store: AppStore) {
        self.store = store

        let rootView = AppRootView(store: store)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Filelay"
        window.contentView = hostingView
        window.minSize = NSSize(width: 1120, height: 720)
        window.contentMinSize = NSSize(width: 1120, height: 720)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(section: AppSection = .files) {
        store.selectedSection = section
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let statusRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let itemCountRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let conflictRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private let openWindowItem = NSMenuItem(title: "", action: #selector(openMainWindow), keyEquivalent: "")
    private let openConflictsItem = NSMenuItem(title: "", action: #selector(openConflicts), keyEquivalent: "")
    private let syncNowItem = NSMenuItem(title: "", action: #selector(syncNow), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "q")

    private let store: AppStore
    private let coordinator: SyncCoordinator
    private let windowController: MainWindowController

    init(store: AppStore, coordinator: SyncCoordinator, windowController: MainWindowController) {
        self.store = store
        self.coordinator = coordinator
        self.windowController = windowController
        super.init()
        setupMenu()
        setupStatusItem()
        bindStore()
        refresh(using: store)
    }

    func showInitialUI() {
        windowController.show()
    }

    private func setupMenu() {
        statusRow.isEnabled = false
        itemCountRow.isEnabled = false
        conflictRow.isEnabled = false

        openWindowItem.target = self
        openConflictsItem.target = self
        syncNowItem.target = self
        quitItem.target = self

        menu.addItem(statusRow)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemCountRow)
        menu.addItem(conflictRow)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openWindowItem)
        menu.addItem(openConflictsItem)
        menu.addItem(syncNowItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Filelay"
        statusItem.menu = menu
        setStatusIcon(symbolName: "icloud")
    }

    private func bindStore() {
        store.onStateChange = { [weak self] store in
            self?.refresh(using: store)
        }
    }

    private func refresh(using store: AppStore) {
        let language = store.settings.language
        statusRow.title = L10n.menuTitle(store.aggregateStatus, language)
        itemCountRow.title = L10n.text(.cloudFilesCountValue(store.cloudFiles.count), language)
        conflictRow.title = L10n.text(.conflictCount(store.conflictItems.count), language)
        openWindowItem.title = L10n.text(.openApp, language)
        openConflictsItem.title = L10n.text(.openConflicts, language)
        syncNowItem.title = L10n.text(.syncNow, language)
        quitItem.title = L10n.text(.quit, language)
        openConflictsItem.isEnabled = !store.conflictItems.isEmpty

        switch store.aggregateStatus {
        case .idle:
            setStatusIcon(symbolName: "checkmark.icloud")
        case .syncing:
            setStatusIcon(symbolName: "arrow.triangle.2.circlepath.icloud")
        case .warning:
            setStatusIcon(symbolName: "exclamationmark.icloud")
        case .error:
            setStatusIcon(symbolName: "xmark.icloud")
        }
    }

    private func setStatusIcon(symbolName: String) {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Filelay") {
            image.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = "AC"
            button.imagePosition = .noImage
        }
    }

    @objc private func openMainWindow() {
        windowController.show(section: .files)
    }

    @objc private func openConflicts() {
        windowController.show(section: .conflicts)
    }

    @objc private func syncNow() {
        coordinator.triggerManualSync()
    }

    @objc private func quitApp() {
        coordinator.suspendLaunchAtLoginForCurrentSessionIfNeeded()
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var coordinator: SyncCoordinator?
    private var store: AppStore?
    private var windowController: MainWindowController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        if hasAnotherRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)

        let storage = Storage()
        let coordinator = SyncCoordinator(storage: storage)
        let store = AppStore(coordinator: coordinator)
        let windowController = MainWindowController(store: store)
        let statusBarController = StatusBarController(store: store, coordinator: coordinator, windowController: windowController)

        self.coordinator = coordinator
        self.store = store
        self.windowController = windowController
        self.statusBarController = statusBarController

        store.start()
        statusBarController.showInitialUI()
    }

    private func hasAnotherRunningInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if apps.contains(where: { $0.processIdentifier != currentPID }) {
                return true
            }
        }

        guard let executablePath = Bundle.main.executableURL?.path else {
            return false
        }

        return NSWorkspace.shared.runningApplications.contains(where: {
            $0.processIdentifier != currentPID && $0.executableURL?.path == executablePath
        })
    }
}
