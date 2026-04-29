import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = CreditStore()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetLog.log("[App] Launched. Bundle=\(Bundle.main.bundlePath)")
        WidgetLog.log("[App] Log file: \(WidgetLog.logFileURL.path)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton()
        configurePopover()
        observeStore()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "dollarsign.circle.fill",
                            accessibilityDescription: "Claude credit balance")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        applyButtonTitle()
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func applyButtonTitle() {
        let label = store.menuBarLabel
        statusItem.button?.title = label.isEmpty ? "" : " \(label)"
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: ContentView(
            store: store,
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    private func observeStore() {
        Publishers.CombineLatest3(store.$balance, store.$error, store.$isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.applyButtonTitle()
            }
            .store(in: &cancellables)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        if store.isLoading { refresh.isEnabled = false }
        menu.addItem(refresh)

        let signIn = NSMenuItem(title: "Sign in with Chrome", action: #selector(signInAction), keyEquivalent: "")
        signIn.target = self
        if store.isImporting { signIn.isEnabled = false }
        menu.addItem(signIn)

        let openConsole = NSMenuItem(title: "Open Billing Page", action: #selector(openConsoleAction), keyEquivalent: "")
        openConsole.target = self
        menu.addItem(openConsole)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let openLog = NSMenuItem(title: "Open Log…", action: #selector(openLogAction), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        let restart = NSMenuItem(title: "Restart", action: #selector(restartAction), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit Claude Credit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshAction() {
        WidgetLog.log("[Action] Refresh")
        Task { await store.refresh() }
    }

    @objc private func signInAction() {
        WidgetLog.log("[Action] Sign in with Chrome")
        Task {
            let result = await store.signInWithChrome()
            if case .failure(let err) = result {
                presentAlert(title: "Sign in failed", message: err.localizedDescription, style: .warning)
            }
        }
    }

    @objc private func openConsoleAction() {
        if let url = URL(string: "https://platform.claude.com/settings/billing") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func openLogAction() {
        WidgetLog.log("[Action] Open Log")
        NSWorkspace.shared.open(WidgetLog.logFileURL)
    }

    @objc private func restartAction() {
        WidgetLog.log("[Action] Restart")
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.4 && open '\(bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    @objc private func quitAction() {
        WidgetLog.log("[Action] Quit")
        NSApplication.shared.terminate(nil)
    }

    private func openSettings() {
        WidgetLog.log("[Action] Open Settings")
        NSApp.activate(ignoringOtherApps: true)
        if popover.isShown { popover.performClose(nil) }

        if let controller = settingsWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let contentSize = NSSize(width: 460, height: 460)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Credit Widget"
        window.isReleasedWhenClosed = false

        let view = SettingsView(store: store)
            .frame(minWidth: 460, idealWidth: 460, maxWidth: .infinity,
                   minHeight: 420, idealHeight: 460, maxHeight: .infinity)
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)
        window.contentViewController = hosting
        window.setContentSize(contentSize)
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Log")
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        if resp == .alertSecondButtonReturn {
            NSWorkspace.shared.open(WidgetLog.logFileURL)
        }
    }
}
