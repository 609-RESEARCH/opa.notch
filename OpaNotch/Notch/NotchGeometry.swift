//
//  NotchGeometry.swift
//  opa.notch (sizing logic ported from boring.notch's matters.swift, GPL-3.0)
//

import AppKit

enum NotchGeometry {
    static let openSize = CGSize(width: 700, height: 296)
    /// Room around the open notch so its shadow and hover hint are never clipped by the window.
    static let shadowPadding: CGFloat = 36
    static let windowSize = CGSize(
        width: openSize.width + shadowPadding * 2,
        height: openSize.height + shadowPadding
    )

    static let closedRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openRadii = (top: CGFloat(20), bottom: CGFloat(28))

    /// The expanded notch shrinks to fit sparse content, but never below this.
    static let minimumOpenHeight: CGFloat = 150

    /// Exact size of the hardware notch, or a menu-bar-height pill on displays without one.
    @MainActor
    static func closedSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return CGSize(width: 185, height: 32) }

        var width: CGFloat = 185
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            width = screen.frame.width - left - right + 4
        }

        let height: CGFloat
        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        } else {
            height = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        return CGSize(width: width, height: height)
    }

    /// Height for the closed notch while it shows an activity. The menu bar can sit a point
    /// or two below the camera housing (33 vs 32 pt on a 13" MacBook Air); the visible black
    /// shape should end exactly where the menu bar does. An auto-hidden menu bar reports 0,
    /// so this falls back to the hardware height.
    @MainActor
    static func activityHeight(for screen: NSScreen?) -> CGFloat {
        let hardware = closedSize(for: screen).height
        guard let screen else { return hardware }
        return max(hardware, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// The screen to live on: the user's choice, else the built-in display with a notch, else main.
    @MainActor
    static func targetScreen(preferredUUID: String?) -> NSScreen? {
        if let uuid = preferredUUID, let screen = NSScreen.screen(withUUID: uuid) {
            return screen
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
