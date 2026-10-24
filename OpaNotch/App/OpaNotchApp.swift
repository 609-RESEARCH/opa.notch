//
//  OpaNotchApp.swift
//  opa.notch
//

import Defaults
import SwiftUI

@main
struct OpaNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Default(.showMenuBarIcon) private var showMenuBarIcon

    var body: some Scene {
        // A template image: the app icon's cut disc, tinted by the system for the menu bar.
        MenuBarExtra("opa.notch", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            Button("Open Notch") { appDelegate.notch.viewModel.open() }
            Button("New Reminder…") { appDelegate.notch.viewModel.requestQuickAdd() }
            Divider()
            Button("Settings…") { SettingsWindowController.shared.showWindow() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit opa.notch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notch = NotchWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch.start()

        // Debug aid: `open opa.notch.app --args -OpaOpenOnLaunch YES` to inspect the open state.
        if UserDefaults.standard.bool(forKey: "OpaOpenOnLaunch") {
            notch.viewModel.open()
        }

        #if DEBUG
        // `--args -OpaSnapshot YES` writes the panel's rendering to the sandbox tmp dir.
        if UserDefaults.standard.bool(forKey: "OpaSnapshot") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                notch.writeSnapshot()
            }
        }
        // `--args -OpaSettingsSnapshot YES` opens Settings and renders the whole window.
        if UserDefaults.standard.bool(forKey: "OpaSettingsSnapshot") {
            SettingsWindowController.shared.showWindow()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                SettingsWindowController.shared.writeSnapshot()
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
