//
//  NotchViewModel.swift
//  opa.notch
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    enum State {
        case closed
        case open
    }

    @Published private(set) var state: State = .closed
    @Published private(set) var closedSize = CGSize(width: 185, height: 32)
    /// Closed height while showing an activity: down to the menu bar's bottom edge.
    @Published private(set) var activityHeight: CGFloat = 32
    @Published var isHovering = false {
        didSet { if isHovering { awaitingPointerReturn = false } }
    }

    /// Bumped to ask the quick-add field to take focus.
    @Published private(set) var quickAddFocusRequest = 0
    @Published private(set) var keyboardActive = false
    /// A half-typed reminder keeps the notch open when the pointer leaves.
    @Published var hasQuickAddDraft = false

    weak var panel: NSPanel?

    private var previousApp: NSRunningApplication?
    /// Counted, so a submenu closing doesn't end the hold while its parent is still open.
    private var openMenus = 0
    /// Menu items often sit outside the notch, so picking one moves the pointer "out".
    /// That isn't the user leaving: stay open until the pointer has come back in.
    private var awaitingPointerReturn = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openMenus += 1 }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuDidEnd() }
        })
    }

    var isOpen: Bool { state == .open }

    /// Something the user is in the middle of keeps the notch from collapsing under them.
    private var isPinnedOpen: Bool {
        openMenus > 0 || awaitingPointerReturn || (keyboardActive && hasQuickAddDraft)
    }

    private func menuDidEnd() {
        openMenus = max(0, openMenus - 1)
        guard openMenus == 0, isOpen else { return }
        awaitingPointerReturn = !pointerIsOverOpenNotch
    }

    private var pointerIsOverOpenNotch: Bool {
        guard let frame = panel?.frame else { return false }
        let size = NotchGeometry.openSize
        let rect = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        return rect.contains(NSEvent.mouseLocation)
    }

    func update(for screen: NSScreen) {
        closedSize = NotchGeometry.closedSize(for: screen)
        activityHeight = NotchGeometry.activityHeight(for: screen)
    }

    func open() {
        guard state != .open else { return }
        withAnimation(Motion.adaptive(Motion.open)) {
            state = .open
        }
        AgendaStore.shared.reload()
        RemindersStore.shared.reload()
    }

    /// - Parameters:
    ///   - force: close even if the user is mid-task (Escape, hotkey, click outside).
    ///   - restoreFocus: hand the keyboard back to the app that had it before quick add.
    func close(force: Bool = false, restoreFocus: Bool = true) {
        guard state != .closed else { return }
        if !force && isPinnedOpen { return }
        awaitingPointerReturn = false
        endKeyboard(restoreFocus: restoreFocus)
        withAnimation(Motion.adaptive(Motion.close)) {
            state = .closed
            isHovering = false
        }
    }

    func toggle() {
        isOpen ? close(force: true) : open()
    }

    func requestQuickAdd() {
        open()
        beginKeyboard()
        quickAddFocusRequest += 1
    }

    // MARK: - Keyboard focus

    /// The panel is non-activating, so typing needs us to briefly become the active app.
    /// Remember who had focus so it can be handed back afterwards.
    func beginKeyboard() {
        guard !keyboardActive else { return }
        keyboardActive = true
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        panel?.makeKey()
    }

    func endKeyboard(restoreFocus: Bool) {
        guard keyboardActive else { return }
        keyboardActive = false
        hasQuickAddDraft = false
        panel?.makeFirstResponder(nil)
        if restoreFocus, let app = previousApp, app != NSRunningApplication.current {
            app.activate()
        }
        previousApp = nil
    }
}
