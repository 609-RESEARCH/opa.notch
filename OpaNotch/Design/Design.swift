//
//  Design.swift
//  opa.notch
//
//  Design tokens. Motion follows Apple's fluid-interface guidance: springs everywhere
//  (they retarget from the on-screen value, so every transition is interruptible),
//  critically damped by default, a touch of bounce only for drawer-like expansion.
//

import AppKit
import SwiftUI

enum Motion {
    /// The notch expanding out of the hardware notch. Drawer-like, so a little overshoot.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Collapsing back. Critically damped: no overshoot into the camera housing.
    static let close = Animation.spring(response: 0.36, dampingFraction: 1.0)
    /// Default for list changes, selection, layout.
    static let standard = Animation.spring(response: 0.32, dampingFraction: 1.0)
    /// Hover and press release.
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 1.0)
    /// Reduced-motion replacement: a short cross-fade, no travel.
    static let reduced = Animation.easeOut(duration: 0.18)

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func adaptive(_ animation: Animation) -> Animation {
        reduceMotion ? reduced : animation
    }
}

/// Text sits on pure black, so "vibrancy" here means higher-contrast whites,
/// slightly heavier weights and a small tracking bump at small sizes.
enum Palette {
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.36)
    static let surface = Color.white.opacity(0.055)
    static let surfaceHover = Color.white.opacity(0.09)
    static let surfacePressed = Color.white.opacity(0.13)
    /// Inset containers inside the notch. Opaque on purpose: nothing behind the notch
    /// should ever show through it.
    static let panel = Color(white: 0.1)
    static let overdue = Color(red: 1.0, green: 0.42, blue: 0.38)
    /// opa.notch orange, used inside the notch only. Standard controls elsewhere
    /// (Settings toggles, sidebar selection) follow the user's system accent, as in System Settings.
    static let accent = Color(red: 1.0, green: 0.624, blue: 0.039)
}

enum Typography {
    static let section = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let numeric = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
    static let wing = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    // Expanded presentation: one big, heavy hero per block, small labels sparingly.
    static let eyebrow = Font.system(size: 11, weight: .bold)
    static let heroTitle = Font.system(size: 20, weight: .bold)
    static let heroNumber = Font.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()
    static let headerValue = Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
}

/// Concentric geometry: every inner radius is its container's radius minus the gap to it,
/// so corners nest the way they do across macOS 26+ (notch 28 → panel 16 → row 8).
enum Metrics {
    static let notchInset: CGFloat = 12
    static let panelRadius: CGFloat = NotchGeometry.openRadii.bottom - notchInset
    static let panelInset: CGFloat = 6
    static let rowRadius: CGFloat = panelRadius - panelInset
    static let rowHeight: CGFloat = 34

    // Panel layout, shared by the views and the notch's content-sized height.
    static let panelTopInset: CGFloat = 6
    static let panelBottomInset: CGFloat = 6
    static let panelSpacing: CGFloat = 8
    static let panelChrome: CGFloat = panelTopInset + panelBottomInset
    static let accessPromptHeight: CGFloat = 150
}

// MARK: - Press & hover feedback

/// Feedback lands on press-down with no animation (zero latency),
/// and springs back on release.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(configuration.isPressed ? nil : Motion.snappy, value: configuration.isPressed)
    }
}

/// Small round icon button on a solid fill.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? Palette.surfacePressed : Palette.panel))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help(help)
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
    }
}

struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = Metrics.rowRadius
    var tint: Color? = nil
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint ?? Palette.surfaceHover)
                    .opacity(hovering ? 1 : 0)
            )
            .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = Metrics.rowRadius) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }

    /// Scroll edge effect instead of hard dividers: content fades where it meets the panel edge.
    func scrollEdgeFade(top: CGFloat = 8, bottom: CGFloat = 16) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: top)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottom)
            }
        )
    }
}

// MARK: - Materialize transition

/// The open notch arrives as a material: blur, scale and opacity move together,
/// anchored to the notch they grow out of.
private struct MaterializeModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .blur(radius: (1 - progress) * 10)
            .opacity(progress)
    }
}

extension AnyTransition {
    static var materialize: AnyTransition {
        if Motion.reduceMotion { return .opacity }
        return .modifier(
            active: MaterializeModifier(progress: 0),
            identity: MaterializeModifier(progress: 1)
        )
    }
}

// MARK: - Haptics

enum Haptics {
    static var enabled: Bool { Preferences.hapticsEnabled }

    /// Used when the pointer reaches the notch and on drag thresholds.
    static func alignment() {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Used on commits: a reminder checked off, a reminder added.
    static func levelChange() {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: - Progress bar

/// Thick capsule progress with a bright tip, the way ride and delivery activities show
/// how far along something is.
struct ProgressBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = max(height, proxy.size.width * min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.22))
                Capsule().fill(color).frame(width: width)
                Circle()
                    .fill(Palette.primary)
                    .frame(width: height + 4, height: height + 4)
                    .offset(x: width - (height + 4))
            }
        }
        .frame(height: height + 4)
        .animation(Motion.adaptive(Motion.standard), value: progress)
    }
}
