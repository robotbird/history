import AppKit
import SwiftUI

@main
@MainActor
final class HistoryApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = RecentItemsStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = HistoryApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        store.refresh()
        store.refreshFinderFolders()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "clock.arrow.circlepath",
            accessibilityDescription: "History"
        )
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 420, height: 500)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(store)
        )
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            showContextMenu(relativeTo: sender)
        default:
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "退出",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
