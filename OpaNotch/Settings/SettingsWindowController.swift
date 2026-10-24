//
//  SettingsWindowController.swift
//  opa.notch (adapted from boring.notch, GPL-3.0)
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private let selection = SettingsSelection()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Built like System Settings: an AppKit sidebar split item (which macOS draws as the
        // floating glass panel) and a detail pane, with the pane's name as the toolbar title.
        let split = NSSplitViewController()

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SettingsSidebar(selection: selection)))
        sidebar.canCollapse = false
        sidebar.minimumThickness = 230
        sidebar.maximumThickness = 230
        split.addSplitViewItem(sidebar)

        let detail = NSSplitViewItem(viewController: NSHostingController(rootView: SettingsDetail(selection: selection)))
        split.addSplitViewItem(detail)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 780, height: 560))
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "OpaNotchSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.delegate = self

        selection.$pane
            .sink { [weak window] pane in window?.title = pane.title }
            .store(in: &cancellables)
    }

    // The tracking separator lines the title up with the detail pane, past the sidebar.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// An accessory app has no Dock icon; become a regular app while Settings is up
    /// so the window can take focus and shows in ⌘-Tab.
    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    #if DEBUG
    func writeSnapshot() {
        guard let window else { return }
        DebugCapture.write(window, name: "opa-settings")
    }
    #endif

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
