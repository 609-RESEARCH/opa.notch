//
//  NotchGeometry.swift
//  opa.notch (sizing logic ported from boring.notch's matters.swift, GPL-3.0)
//

import AppKit

/// How the notch fits one particular display.
struct NotchLayout: Equatable {
    /// The largest the open notch may get. It's smaller when its content needs less.
    var openSize: CGSize
    /// The transparent window holding the notch. Never larger than the display, so it
    /// can't spill onto a neighbouring one.
    var windowSize: CGSize
    /// On very narrow displays the two panels go one above the other.
    var stacksPanels: Bool
    /// Whether there's room beside the closed notch for a detached activity.
    var fitsDetachedActivity: Bool
}

enum NotchGeometry {
    static let maxOpenSize = CGSize(width: 700, height: 296)
    /// Stacked panels trade width for height, so they get more of it.
    static let maxStackedHeight: CGFloat = 560
    /// Below this open width, two panels side by side would be too cramped to read.
    static let stackingWidth: CGFloat = 680
    /// The open notch keeps at least this much of the display visible on each side.
    static let displayMargin: CGFloat = 8
    /// Room around the open notch so its shadow and hover hint are never clipped by the window.
    static let shadowPadding: CGFloat = 36

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

    static func layout(forDisplay display: CGSize) -> NotchLayout {
        let width = min(maxOpenSize.width, display.width - displayMargin * 2)
        let stacks = width < stackingWidth
        let height = min(stacks ? maxStackedHeight : maxOpenSize.height, display.height - displayMargin * 2)
        let window = CGSize(
            width: min(width + shadowPadding * 2, display.width),
            height: min(height + shadowPadding, display.height)
        )
        return NotchLayout(
            openSize: CGSize(width: width, height: height),
            windowSize: window,
            stacksPanels: stacks,
            fitsDetachedActivity: window.width >= 440
        )
    }

    /// The window while the notch is closed: a strip along the top edge with room for the
    /// activity beside the notch. A window this high up always sits above other windows,
    /// so it stays out of the way of anything below the menu bar until the notch opens.
    static func closedWindowSize(layout: NotchLayout, notchWidth: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: min(notchWidth + 300, layout.windowSize.width), height: min(height + 6, layout.windowSize.height))
    }

    /// Centred along the display's top edge and snapped to whole pixels: a window on a
    /// half pixel, as an odd-width 1x display would give, draws blurry.
    static func panelFrame(display: CGRect, scale: CGFloat, windowSize: CGSize) -> CGRect {
        let x = display.midX - windowSize.width / 2
        return CGRect(
            x: (x * scale).rounded() / scale,
            y: display.maxY - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    /// The displays to live on: the one the user chose if it's connected, otherwise all of them.
    @MainActor
    static func targetScreens(preferredUUID: String?) -> [NSScreen] {
        let screens = NSScreen.screens
        if let preferredUUID, let chosen = screens.first(where: { $0.displayUUID == preferredUUID }) {
            return [chosen]
        }
        return screens
    }

    // MARK: - Full-screen detection

    /// Bounds of other apps' ordinary windows in the current Spaces. A full-screen app's
    /// window exactly fills its display. Reading bounds needs no Screen Recording permission.
    static func fullscreenCandidateBounds() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? pid_t != ownProcess,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
    }

    /// Whether a window fills the display. Window bounds use window-server coordinates, whose
    /// origin is the top-left of the primary display (AppKit's is its bottom-left).
    static func hasFullscreenWindow(in windowBounds: [CGRect], display: CGRect, primaryHeight: CGFloat) -> Bool {
        let target = CGRect(x: display.minX, y: primaryHeight - display.maxY, width: display.width, height: display.height)
        return windowBounds.contains { window in
            abs(window.minX - target.minX) <= 1 && abs(window.minY - target.minY) <= 1
                && abs(window.width - target.width) <= 1 && abs(window.height - target.height) <= 1
        }
    }
}
