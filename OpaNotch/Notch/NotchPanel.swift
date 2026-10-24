//
//  NotchPanel.swift
//  opa.notch (adapted from boring.notch's BoringNotchSkyLightWindow, GPL-3.0)
//

import AppKit
import Combine
import Defaults

/// Borderless, non-activating panel that sits over the menu bar.
/// It only becomes key when a text field asks for it (quick add), so clicking
/// a checkbox in the notch never steals keyboard focus from the app you're in.
final class NotchPanel: NSPanel {
    private var cancellables = Set<AnyCancellable>()

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        canHide = false
        level = .mainMenu + 3
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]

        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] change in
                self?.sharingType = change.newValue ? .none : .readOnly
            }
            .store(in: &cancellables)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps the panel above full-screen apps by parking it in a max-level CGS space.
final class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    let notchSpace = CGSSpace(level: 2147483647)
    private init() {}
}
