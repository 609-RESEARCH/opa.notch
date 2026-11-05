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

/// Keeps one notch on each display, adding and removing them as displays come and go.
@MainActor
final class NotchWindowController {
    private var notches: [CGDirectDisplayID: DisplayNotch] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var fullscreenCheck: Task<Void, Never>?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var ownWindowClickMonitor: Any?

    func start() {
        syncDisplays()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncDisplays() }
        })

        // Entering or leaving full screen switches Space, which can also change a display's
        // menu bar height. Bringing a full-screen app forward activates it.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncDisplays() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleFullscreenCheck() }
        })

        Defaults.publisher(.preferredScreenUUID, options: [])
            .sink { [weak self] _ in self?.syncDisplays() }
            .store(in: &cancellables)

        KeyboardShortcuts.onKeyDown(for: .toggleNotch) { [weak self] in
            self?.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .quickAddReminder) { [weak self] in
            self?.toggleQuickAdd()
        }

        installMonitors()
    }

    // MARK: - Actions

    /// Opens the notch on the display the pointer is on.
    func open() {
        notchUnderPointer?.viewModel.open()
    }

    /// Starts a new reminder in the notch already open, otherwise under the pointer.
    func quickAdd() {
        (openNotches.first ?? notchUnderPointer)?.viewModel.requestQuickAdd()
    }

    private func toggle() {
        if openNotches.isEmpty {
            open()
        } else {
            closeAll()
        }
    }

    private func toggleQuickAdd() {
        if openNotches.contains(where: \.viewModel.keyboardActive) {
            closeAll()
        } else {
            quickAdd()
        }
    }

    private func closeAll(restoreFocus: Bool = true) {
        openNotches.forEach { $0.viewModel.close(force: true, restoreFocus: restoreFocus) }
    }

    private var openNotches: [DisplayNotch] {
        notches.values.filter(\.viewModel.isOpen)
    }

    private var notchUnderPointer: DisplayNotch? {
        // Grown by a point because the pointer can rest exactly on a display's top edge,
        // which a CGRect doesn't count as inside.
        let pointer = NSEvent.mouseLocation
        return notches.values.first { $0.screenFrame.insetBy(dx: -1, dy: -1).contains(pointer) }
            ?? notches.values.first
    }

    // MARK: - Displays

    private func syncDisplays() {
        var connected = Set<CGDirectDisplayID>()
        for screen in NotchGeometry.targetScreens(preferredUUID: Defaults[.preferredScreenUUID]) {
            guard let id = screen.displayID else { continue }
            connected.insert(id)
            if let notch = notches[id] {
                notch.place(on: screen)
            } else {
                let notch = DisplayNotch(screen: screen)
                // A notch the user is in the middle of (a half-typed reminder, say) stays put.
                notch.viewModel.onOpen = { [weak self, weak notch] in
                    self?.notches.values.filter { $0 !== notch }.forEach { $0.viewModel.close() }
                }
                notches[id] = notch
            }
        }
        for id in Set(notches.keys).subtracting(connected) {
            notches.removeValue(forKey: id)?.remove()
        }
        scheduleFullscreenCheck()
    }

    /// Checks now, and again once the full-screen animation has finished moving the window.
    private func scheduleFullscreenCheck() {
        updateFullscreen()
        fullscreenCheck?.cancel()
        fullscreenCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.updateFullscreen()
        }
    }

    private func updateFullscreen() {
        let bounds = NotchGeometry.fullscreenCandidateBounds()
        notches.values.forEach { $0.updateFullscreen(windowBounds: bounds) }
    }

    #if DEBUG
    func writeSnapshot() {
        let ordered = notches.keys.sorted().compactMap { notches[$0] }
        for (index, notch) in ordered.enumerated() {
            DebugCapture.write(notch.panel, name: index == 0 ? "opa-snapshot" : "opa-snapshot-\(index + 1)")
        }
    }
    #endif

    // MARK: - Monitors

    private func installMonitors() {
        // A click anywhere else is a clear "I'm done here". That app takes focus itself.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll(restoreFocus: false) }
        }

        // The monitor above only sees other apps. Clicking one of our own windows, like Settings,
        // is just as clear, while clicks inside a notch are for the notch.
        ownWindowClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if !(event.window is NotchPanel) {
                MainActor.assumeIsolated { self?.closeAll(restoreFocus: false) }
            }
            return event
        }

        // Escape always has a way out, even mid-typing.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, !self.openNotches.isEmpty else { return false }
                // With the due date picker up, Escape only backs out of the picker.
                if let editing = self.openNotches.first(where: { $0.viewModel.dueEditorItem != nil }) {
                    editing.viewModel.dismissDueEditor()
                } else {
                    self.closeAll()
                }
                return true
            }
            return handled ? nil : event
        }
    }
}

/// The notch on one display: its window and its own open or closed state.
@MainActor
private final class DisplayNotch {
    let viewModel = NotchViewModel()
    let panel: NotchPanel
    private(set) var screenFrame: CGRect
    private var hasHardwareNotch: Bool
    private var hiddenForFullscreen = false
    private var cancellable: AnyCancellable?
    private var scale: CGFloat
    private var shrinkTask: Task<Void, Never>?

    /// Long enough for the closing spring to finish inside the larger window.
    private static let closeAnimationTime: Duration = .milliseconds(700)

    init(screen: NSScreen) {
        screenFrame = screen.frame
        hasHardwareNotch = screen.safeAreaInsets.top > 0
        scale = screen.backingScaleFactor
        viewModel.update(for: screen)
        panel = NotchPanel(contentRect: .zero)
        panel.setFrame(panelFrame(isOpen: false), display: false)
        viewModel.panel = panel

        let hosting = NSHostingView(rootView: NotchView().environmentObject(viewModel))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(panel)

        // $state publishes before the property changes, so use the value it's handed.
        cancellable = viewModel.$state.sink { [weak self] state in
            self?.updateVisibility(isOpen: state == .open)
            self?.resizePanel(isOpen: state == .open)
        }
    }

    func place(on screen: NSScreen) {
        screenFrame = screen.frame
        hasHardwareNotch = screen.safeAreaInsets.top > 0
        scale = screen.backingScaleFactor
        viewModel.update(for: screen)
        panel.setFrame(panelFrame(isOpen: viewModel.isOpen), display: true)
    }

    func remove() {
        shrinkTask?.cancel()
        viewModel.close(force: true)
        NotchSpaceManager.shared.notchSpace.windows.remove(panel)
        panel.contentView = nil
        panel.close()
    }

    /// A display with a camera housing already has a black band in full screen, so its notch
    /// can stay. Elsewhere the closed shape would sit on top of the app's content.
    func updateFullscreen(windowBounds: [CGRect]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        hiddenForFullscreen = !hasHardwareNotch
            && NotchGeometry.hasFullscreenWindow(in: windowBounds, display: screenFrame, primaryHeight: primaryHeight)
        updateVisibility(isOpen: viewModel.isOpen)
    }

    private func updateVisibility(isOpen: Bool) {
        // The shortcuts can still open a hidden notch.
        let visible = isOpen || !hiddenForFullscreen
        panel.alphaValue = visible ? 1 : 0
        panel.ignoresMouseEvents = !visible
    }

    /// Grows before the notch opens so the spring has room, and shrinks once it has closed.
    private func resizePanel(isOpen: Bool) {
        shrinkTask?.cancel()
        guard !isOpen else {
            panel.setFrame(panelFrame(isOpen: true), display: false)
            return
        }
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeAnimationTime)
            guard !Task.isCancelled, let self, !self.viewModel.isOpen else { return }
            self.panel.setFrame(self.panelFrame(isOpen: false), display: true)
        }
    }

    private func panelFrame(isOpen: Bool) -> NSRect {
        let layout = viewModel.layout
        let size = isOpen
            ? layout.windowSize
            : NotchGeometry.closedWindowSize(layout: layout, notchWidth: viewModel.closedSize.width, height: viewModel.activityHeight)
        return NotchGeometry.panelFrame(display: screenFrame, scale: scale, windowSize: size)
    }
}
