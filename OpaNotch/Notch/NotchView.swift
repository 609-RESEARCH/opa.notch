//
//  NotchView.swift
//  opa.notch
//
//  Structure of the hover/gesture handling adapted from boring.notch's ContentView (GPL-3.0).
//

import Defaults
import SwiftUI

struct NotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var agenda = AgendaStore.shared
    @ObservedObject private var reminders = RemindersStore.shared

    @Default(.showLiveActivity) private var showLiveActivity
    @Default(.showReminderCount) private var showReminderCount
    @Default(.reminderScope) private var reminderScope

    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        // Minute ticks keep countdowns honest without a timer per view.
        TimelineView(.everyMinute) { context in
            let activity = liveActivity(at: context.date)
            notch(activity: activity, now: context.date)
                .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height, alignment: .top)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Shape

    private func notch(activity: LiveActivity, now: Date) -> some View {
        let isOpen = vm.isOpen
        let showWings = !isOpen && !activity.isEmpty
        let expanded = expandedSize(at: now)
        let radii = isOpen ? NotchGeometry.openRadii : NotchGeometry.closedRadii
        let shape = NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom)

        let surface = ZStack(alignment: .top) {
            if isOpen {
                OpenNotchContent(now: now, activity: activity)
                    .frame(width: expanded.width, height: expanded.height, alignment: .top)
                    .transition(.materialize)
            } else if showWings {
                LiveActivityWings(activity: activity, notchWidth: vm.closedSize.width, height: vm.activityHeight, now: now)
                    .transition(.opacity)
            }
        }
        // Closed with an activity, the wings decide the width: only the space they need.
        .frame(
            width: isOpen ? expanded.width : (showWings ? nil : vm.closedSize.width),
            // The plain notch matches the camera housing exactly; with an activity it reaches
            // the menu bar's bottom edge so the black shape lines up with it.
            height: isOpen ? expanded.height : (showWings ? vm.activityHeight : vm.closedSize.height),
            alignment: .top
        )
        .background(.black)
        .clipShape(shape)
        // Bigger surfaces read as thicker: a deeper shadow only once it's a panel.
        .shadow(color: .black.opacity(isOpen ? 0.55 : 0), radius: isOpen ? 18 : 0, y: isOpen ? 8 : 0)
        .contentShape(shape)

        // A second activity floats beside the notch, never inside it.
        return DetachedLayout(gap: Self.detachedGap) {
            surface
            if showWings, case .reminders(let due, let overdue)? = activity.secondary {
                DetachedRemindersBubble(due: due, overdue: overdue, height: vm.activityHeight - 6)
                    .transition(.detach)
            }
        }
        .animation(Motion.adaptive(Motion.standard), value: activity.secondary)
        // Hint in the direction of the gesture: the closed notch leans out toward the pointer.
        .scaleEffect(closedHintScale, anchor: .top)
        .animation(Motion.adaptive(Motion.snappy), value: vm.isHovering)
        .animation(Motion.adaptive(Motion.standard), value: showWings)
        .animation(Motion.adaptive(Motion.standard), value: expanded.height)
        .onHover(perform: handleHover)
        .onTapGesture { if !vm.isOpen { vm.open() } }
        .contextMenu {
            Button("Settings…") { SettingsWindowController.shared.showWindow() }
        }
    }


    // MARK: - Expanded height

    /// The expanded presentation only uses the height its content needs, growing as
    /// more becomes available, up to the full size (where lists start scrolling).
    private func expandedSize(at now: Date) -> CGSize {
        let header = max(28, vm.closedSize.height)
        let panels = max(
            AgendaPanel.idealHeight(store: agenda, now: now),
            RemindersPanel.idealHeight(store: reminders, scope: reminderScope, now: now)
        )
        let height = header + 8 + panels + Metrics.notchInset
        let clamped = min(NotchGeometry.openSize.height, max(NotchGeometry.minimumOpenHeight, height))
        return CGSize(width: NotchGeometry.openSize.width, height: clamped)
    }

    /// Gap between the notch and a detached activity.
    private static let detachedGap: CGFloat = 8

    private var closedHintScale: CGFloat {
        vm.isOpen || !vm.isHovering ? 1 : 1.035
    }

    /// The most time-sensitive activity takes the notch: a meeting (it has a defined
    /// start and end), otherwise what's due today. With both, reminders go detached.
    private func liveActivity(at now: Date) -> LiveActivity {
        guard showLiveActivity else { return LiveActivity(kind: nil) }
        var remindersActivity: LiveActivity.Kind?
        if showReminderCount {
            let counts = reminders.dueCount(at: now)
            if counts.total > 0 {
                remindersActivity = .reminders(due: counts.total, overdue: counts.overdue)
            }
        }
        if let event = agenda.focusEvent(at: now) {
            // Both running: the meeting keeps the notch, reminders detach beside it.
            return LiveActivity(kind: .meeting(event), secondary: remindersActivity)
        }
        return LiveActivity(kind: remindersActivity)
    }

    // MARK: - Hover

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        vm.isHovering = hovering

        if hovering {
            guard !vm.isOpen else { return }
            Haptics.alignment()
            guard Defaults[.openOnHover] else { return }
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.hoverDelay]))
                guard !Task.isCancelled, vm.isHovering else { return }
                vm.open()
            }
        } else {
            // A short grace period forgives the pointer briefly slipping off the edge.
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                vm.close()
            }
        }
    }

}

// MARK: - Open layout

private struct OpenNotchContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let now: Date
    /// What the closed notch was showing. The header is its enlarged version, so elements
    /// keep their place around the camera as the notch expands.
    let activity: LiveActivity

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 10) {
                AgendaPanel(now: now)
                RemindersPanel(now: now)
            }
        }
        // Same gap to the notch's side walls and its bottom edge, so the panels' corners
        // sit concentric inside the notch's.
        .padding(.horizontal, NotchGeometry.openRadii.top + Metrics.notchInset)
        .padding(.bottom, Metrics.notchInset)
    }

    /// Header content wraps tightly around the camera instead of drifting to the far edges.
    private static let cameraSpacing: CGFloat = 8

    /// The hardware notch sits in the middle of this row. Like the compact presentation,
    /// the activity's graphic sits on the camera's leading side and its value on the
    /// trailing side, both hugging the camera.
    private var header: some View {
        HStack(spacing: 0) {
            leadingGlyph
                .padding(.trailing, Self.cameraSpacing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Color.clear.frame(width: vm.closedSize.width)

            HStack(spacing: 8) {
                trailingValue
                Spacer(minLength: 0)
                IconButton(systemName: "gearshape.fill", help: "Settings") {
                    vm.close(force: true, restoreFocus: false)
                    SettingsWindowController.shared.showWindow()
                }
            }
            .padding(.leading, Self.cameraSpacing)
            .frame(maxWidth: .infinity)
        }
        .frame(height: max(28, vm.closedSize.height))
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch activity.kind {
        case .meeting(let event):
            ProgressRing(progress: event.ringProgress(at: now), color: event.color, lineWidth: 2.8)
                .frame(width: 18, height: 18)
        case .reminders(_, let overdue):
            Image(systemName: overdue > 0 ? "exclamationmark.circle.fill" : "checklist")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activity.tint)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        switch activity.kind {
        case .meeting(let event):
            Text(event.countdown(at: now, verbose: true))
                .font(Typography.headerValue)
                .foregroundStyle(event.color)
                .contentTransition(.numericText(countsDown: true))
        case .reminders(let due, _):
            Text("\(due) due")
                .font(Typography.headerValue)
                .foregroundStyle(activity.tint)
                .contentTransition(.numericText())
        case nil:
            EmptyView()
        }
    }
}
