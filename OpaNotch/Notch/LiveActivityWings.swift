//
//  LiveActivityWings.swift
//  opa.notch
//
//  The closed notch's presentations, following Apple's Live Activity guidance:
//  - compact: one piece of information split across both sides of the camera (a graphic
//    on the leading side, its value on the trailing side), in one colour, snug against
//    the camera and only as wide as it needs to be;
//  - detached minimal: when a second activity is running, it floats beside the notch in
//    its own black capsule, circular or oval depending on its content.
//

import SwiftUI

struct LiveActivity: Equatable {
    enum Kind: Equatable {
        /// A meeting in progress or starting within the look-ahead window.
        case meeting(AgendaEvent)
        /// Nothing time-bound: reminders due today (or overdue).
        case reminders(due: Int, overdue: Int)
    }

    var kind: Kind?
    /// A second, concurrent activity, shown detached beside the notch.
    var secondary: Kind? = nil

    var isEmpty: Bool { kind == nil }

    /// The activity's single colour, shared by both sides of the camera.
    var tint: Color {
        switch kind {
        case .meeting(let event): event.color
        case .reminders(_, let overdue): overdue > 0 ? Palette.overdue : Palette.accent
        case nil: .clear
        }
    }
}

struct LiveActivityWings: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let height: CGFloat
    let now: Date

    var body: some View {
        BalancedWings(cameraWidth: notchWidth) {
            leading
            trailing
        }
        .frame(height: height)
        .foregroundStyle(activity.tint)
        .help(helpText)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity.kind {
        case .meeting(let event):
            ProgressRing(progress: event.ringProgress(at: now), color: event.color)
                .frame(width: 14, height: 14)
        case .reminders(_, let overdue):
            Image(systemName: overdue > 0 ? "exclamationmark.circle.fill" : "checklist")
                .font(.system(size: 13, weight: .semibold))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity.kind {
        case .meeting(let event):
            Text(event.countdown(at: now))
                .font(Typography.wing)
                .contentTransition(.numericText(countsDown: true))
        case .reminders(let due, _):
            Text("\(due)")
                .font(Typography.wing)
                .contentTransition(.numericText())
        case nil:
            EmptyView()
        }
    }

    private var helpText: String {
        switch activity.kind {
        case .meeting(let event):
            event.phase(at: now) == .now ? "\(event.title) — ends \(TimeFormatting.time(event.end))" : "\(event.title) — \(TimeFormatting.time(event.start))"
        case .reminders(let due, let overdue):
            overdue > 0 ? "\(overdue) overdue, \(due) due today" : "\(due) due today"
        case nil:
            ""
        }
    }
}

/// Lays out [leading, trailing] on either side of the camera: both get the width of the
/// wider one (balanced), each sits snug against the camera, and the whole thing is only
/// as wide as that content plus an outer margin.
struct BalancedWings: Layout {
    let cameraWidth: CGFloat
    /// The closed notch's measured width already includes a hair of slack past the camera.
    var cameraGap: CGFloat = 2
    /// Keeps content clear of the notch's flared top corners.
    var outerMargin: CGFloat = 11

    private func wingWidth(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let wing = wingWidth(subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: cameraWidth + 2 * (wing + cameraGap + outerMargin), height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let cameraMinX = bounds.midX - cameraWidth / 2
        let cameraMaxX = bounds.midX + cameraWidth / 2

        // Leading: right edge against the camera. Trailing: left edge against it.
        subviews[0].place(at: CGPoint(x: cameraMinX - cameraGap, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: cameraMaxX + cameraGap, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}

/// Lays out the notch, plus a detached activity placed `gap` points past its trailing
/// edge and vertically centred on it. Only the notch counts toward this layout's size,
/// so the notch (and the camera it surrounds) stays centred on screen.
struct DetachedLayout: Layout {
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let notch = subviews.first else { return }
        notch.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        for detached in subviews.dropFirst() {
            detached.place(at: CGPoint(x: bounds.maxX + gap, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        }
    }
}

/// Apple's detached minimal presentation for the reminders count: its own black capsule
/// floating beside the notch, vertically centred on it, circular for short content and
/// oval as the count grows.
struct DetachedRemindersBubble: View {
    let due: Int
    let overdue: Int
    let height: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: overdue > 0 ? "exclamationmark.circle.fill" : "checklist")
                .font(.system(size: 11, weight: .semibold))
            Text("\(due)")
                .font(Typography.wing)
                .contentTransition(.numericText())
        }
        .foregroundStyle(overdue > 0 ? Palette.overdue : Palette.accent)
        .padding(.horizontal, 9)
        .frame(minWidth: height, minHeight: height, maxHeight: height)
        .background(Capsule().fill(.black))
        .contentShape(Capsule())
        .help(overdue > 0 ? "\(overdue) overdue, \(due) due today" : "\(due) due today")
    }
}

extension AnyTransition {
    /// The detached capsule splits off the notch's edge rather than just appearing.
    static var detach: AnyTransition {
        if Motion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .offset(x: -14)).combined(with: .opacity),
            removal: .scale(scale: 0.4, anchor: .leading).combined(with: .offset(x: -14)).combined(with: .opacity)
        )
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 2.4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.28), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.adaptive(Motion.standard), value: progress)
    }
}
