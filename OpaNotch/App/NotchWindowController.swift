//
//  NotchWindowController.swift
//  opa.notch
//
//  Window placement adapted from boring.notch's AppDelegate (GPL-3.0).
//

import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
final class NotchWindowController {
    let viewModel = NotchViewModel()

    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?

    func start() {
        createPanel()
        reposition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        Defaults.publisher(.preferredScreenUUID, options: [])
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        KeyboardShortcuts.onKeyDown(for: .toggleNotch) { [weak self] in
            self?.viewModel.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .quickAddReminder) { [weak self] in
            guard let self else { return }
            if viewModel.isOpen && viewModel.keyboardActive {
                viewModel.close(force: true)
            } else {
                viewModel.requestQuickAdd()
            }
        }

        installMonitors()
    }

    private func createPanel() {
        let rect = NSRect(origin: .zero, size: NotchGeometry.windowSize)
        let panel = NotchPanel(contentRect: rect)
        let hosting = NSHostingView(rootView: NotchView().environmentObject(viewModel))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(panel)

        viewModel.panel = panel
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let screen = NotchGeometry.targetScreen(preferredUUID: Defaults[.preferredScreenUUID]) else { return }
        viewModel.update(for: screen)
        let frame = screen.frame
        panel.setFrame(
            NSRect(
                x: frame.midX - NotchGeometry.windowSize.width / 2,
                y: frame.maxY - NotchGeometry.windowSize.height,
                width: NotchGeometry.windowSize.width,
                height: NotchGeometry.windowSize.height
            ),
            display: true
        )
    }

    #if DEBUG
    func writeSnapshot() {
        guard let panel else { return }
        DebugCapture.write(panel, name: "opa-snapshot")
    }
    #endif

    private func installMonitors() {
        // A click anywhere else is a clear "I'm done here". That app takes focus itself.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.viewModel.isOpen else { return }
                self.viewModel.close(force: true, restoreFocus: false)
            }
        }

        // Escape always has a way out, even mid-typing.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, self.viewModel.isOpen else { return false }
                self.viewModel.close(force: true)
                return true
            }
            return handled ? nil : event
        }
    }
}
