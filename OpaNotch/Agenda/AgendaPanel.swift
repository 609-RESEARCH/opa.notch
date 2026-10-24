//
//  AgendaPanel.swift
//  opa.notch
//
//  The left block of the expanded notch. One hero, the meeting in progress or the next
//  one, carries the calendar's colour; everything after it is a quiet list.
//

import SwiftUI

struct AgendaPanel: View {
    @ObservedObject var store = AgendaStore.shared
    let now: Date

    var body: some View {
        PanelSurface {
            switch store.access {
            case .granted:
                content
            case .notDetermined, .denied:
                AccessPrompt(
                    symbol: "calendar",
                    title: "See your day at a glance",
                    message: "Your next meeting, right in the notch.",
                    status: store.access,
                    request: { await store.requestAccess() },
                    openSettings: { EventKitAccess.openPrivacySettings(for: .event) }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let plan = AgendaPlan(store: store, now: now)
        if let hero = plan.hero {
            HeroEvent(event: hero, now: now)
            if !plan.later.isEmpty || !plan.allDay.isEmpty {
                LaterList(events: plan.later, allDay: plan.allDay)
            }
        } else {
            FreeState(hadEvents: !store.today.isEmpty, allDay: plan.allDay, tomorrow: store.tomorrow.first { !$0.isAllDay })
        }
    }

    // MARK: Sizing

    static let heroHeight: (now: CGFloat, next: CGFloat) = (106, 93)
    static let laterLabelHeight: CGFloat = 20
    static let laterRowHeight: CGFloat = 24
    static let laterBottomPadding: CGFloat = 10
    static let allDayHeight: CGFloat = 26
    static let freeHeight: CGFloat = 96

    /// The height this block wants, so the notch can size itself to its content.
    @MainActor
    static func idealHeight(store: AgendaStore, now: Date) -> CGFloat {
        guard store.access == .granted else { return Metrics.panelChrome + Metrics.accessPromptHeight }
        let plan = AgendaPlan(store: store, now: now)
        guard let hero = plan.hero else { return Metrics.panelChrome + freeHeight }
        var height = hero.phase(at: now) == .now ? heroHeight.now : heroHeight.next
        if !plan.later.isEmpty || !plan.allDay.isEmpty {
            height += Metrics.panelSpacing + laterLabelHeight
            height += plan.allDay.isEmpty ? 0 : allDayHeight
            height += CGFloat(plan.later.count) * laterRowHeight + laterBottomPadding
        }
        return Metrics.panelChrome + height
    }
}

/// Which of today's events go where.
private struct AgendaPlan {
    let allDay: [AgendaEvent]
    /// The meeting in progress, otherwise the next one today.
    let hero: AgendaEvent?
    /// Everything still to come after the hero.
    let later: [AgendaEvent]

    @MainActor
    init(store: AgendaStore, now: Date) {
        allDay = store.today.filter(\.isAllDay)
        let timed = store.today.filter { !$0.isAllDay }
        let hero = timed.last { $0.phase(at: now) == .now } ?? timed.first { $0.phase(at: now) == .upcoming }
        self.hero = hero
        later = timed.filter { $0.phase(at: now) == .upcoming && $0.id != hero?.id }
    }
}

// MARK: - Hero

private struct HeroEvent: View {
    let event: AgendaEvent
    let now: Date
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        let isNow = event.phase(at: now) == .now

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(isNow ? "NOW" : "NEXT · \(TimeFormatting.time(event.start))")
                    .font(Typography.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(event.color)
                Spacer(minLength: 4)
                if let url = event.meetingURL {
                    JoinButton(color: event.color) {
                        NSWorkspace.shared.open(url)
                        vm.close(force: true, restoreFocus: false)
                    }
                }
            }
            .frame(height: 22)

            Text(event.title)
                .font(Typography.heroTitle)
                .tracking(-0.3)
                .foregroundStyle(Palette.primary)
                .lineLimit(1)

            if isNow {
                ProgressBar(progress: event.progress(at: now), color: event.color)
                    .padding(.top, 4)
                HStack {
                    Text(TimeFormatting.time(event.start))
                    Spacer()
                    if let location = event.location {
                        Text(location).lineLimit(1)
                        Spacer()
                    }
                    Text(TimeFormatting.time(event.end))
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.secondary)
            } else {
                Text([TimeFormatting.timeRange(event.start, event.end), event.location].compactMap { $0 }.joined(separator: " · "))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A tinted inset container: the calendar's colour is the block's identity.
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(event.color.opacity(0.16))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = event.calendarAppURL {
                NSWorkspace.shared.open(url)
                vm.close(force: true, restoreFocus: false)
            }
        }
        .help([event.title, event.location].compactMap { $0 }.joined(separator: "\n"))
    }
}

/// The one action in the block: tinted with the event's colour.
private struct JoinButton: View {
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Join")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .frame(height: 22)
            .background(Capsule().fill(color))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .help("Join video call")
    }
}

// MARK: - Later

private struct LaterList: View {
    let events: [AgendaEvent]
    let allDay: [AgendaEvent]
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(events.isEmpty ? "ALL DAY" : "LATER")
                .font(Typography.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 6)
                .frame(height: AgendaPanel.laterLabelHeight, alignment: .top)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !allDay.isEmpty {
                        AllDayStrip(events: allDay)
                            .frame(height: AgendaPanel.allDayHeight, alignment: .top)
                    }
                    ForEach(events) { event in
                        row(event)
                    }
                }
                .padding(.bottom, AgendaPanel.laterBottomPadding)
            }
            .scrollEdgeFade(top: 0, bottom: 12)
        }
    }

    private func row(_ event: AgendaEvent) -> some View {
        HStack(spacing: 8) {
            Text(TimeFormatting.time(event.start))
                .font(Typography.numeric)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)
            Circle()
                .fill(event.color)
                .frame(width: 7, height: 7)
            Text(event.title)
                .font(Typography.body)
                .foregroundStyle(Palette.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if event.meetingURL != nil {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: AgendaPanel.laterRowHeight)
        .hoverHighlight()
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = event.calendarAppURL {
                NSWorkspace.shared.open(url)
                vm.close(force: true, restoreFocus: false)
            }
        }
        .help([event.title, event.location].compactMap { $0 }.joined(separator: "\n"))
    }
}

private struct AllDayStrip: View {
    let events: [AgendaEvent]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(events) { event in
                    Button {
                        if let url = event.calendarAppURL { NSWorkspace.shared.open(url) }
                    } label: {
                        Text(event.title)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(event.color.opacity(0.24)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Free

private struct FreeState: View {
    let hadEvents: Bool
    let allDay: [AgendaEvent]
    let tomorrow: AgendaEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hadEvents ? "THAT'S A WRAP" : "TODAY")
                .font(Typography.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Palette.accent)
            Text(hadEvents ? "Free for the rest of the day" : "Nothing scheduled")
                .font(Typography.heroTitle)
                .tracking(-0.3)
                .foregroundStyle(Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tomorrow {
                Text("Tomorrow \(TimeFormatting.time(tomorrow.start)) · \(tomorrow.title)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            if !allDay.isEmpty {
                AllDayStrip(events: allDay)
                    .padding(.top, 4)
                    .padding(.horizontal, -4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(Palette.accent.opacity(0.12))
        )
    }
}
