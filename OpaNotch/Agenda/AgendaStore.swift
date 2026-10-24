//
//  AgendaStore.swift
//  opa.notch
//
//  Calendar deep-link logic adapted from Calendr (pakerwreah/Calendr) via boring.notch, GPL-3.0.
//

import AppKit
import Defaults
import EventKit
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    /// Recurring occurrences share an event identifier, so the start date disambiguates.
    let id: String
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarTitle: String
    let location: String?
    let meetingURL: URL?
    let isRecurring: Bool

    enum Phase {
        case upcoming
        case now
        case ended
    }

    func phase(at now: Date) -> Phase {
        if now < start { return .upcoming }
        if now < end { return .now }
        return .ended
    }

    /// 0 → 1 across the event's duration.
    func progress(at now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// How the notch counts down to (or through) this event: "in 12m", "now", "25m left".
    func countdown(at now: Date, verbose: Bool = false) -> String {
        if phase(at: now) == .now {
            let left = TimeFormatting.compactDuration(end.timeIntervalSince(now))
            return verbose ? "\(left) left" : left
        }
        let untilStart = start.timeIntervalSince(now)
        return untilStart < 60 ? "now" : "in \(TimeFormatting.compactDuration(untilStart))"
    }

    /// While it runs, the ring fills with elapsed time; before it, it fills as it approaches.
    func ringProgress(at now: Date) -> Double {
        if phase(at: now) == .now { return progress(at: now) }
        let window: TimeInterval = 60 * 60
        return 1 - min(1, max(0, start.timeIntervalSince(now) / window))
    }

    var calendarAppURL: URL? {
        guard let encoded = eventIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var datePart = ""
        if isRecurring {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay { formatter.timeZone = .init(secondsFromGMT: 0) }
            datePart = "/" + formatter.string(from: start)
        }
        return URL(string: "ical://ekevent\(datePart)/\(encoded)?method=show&options=more")
    }
}

struct CalendarSource: Identifiable, Hashable {
    let id: String
    let title: String
    let account: String
    let color: Color
}

@MainActor
final class AgendaStore: ObservableObject {
    static let shared = AgendaStore()

    @Published private(set) var access: EventKitAccess.Status = EventKitAccess.status(for: .event)
    @Published private(set) var today: [AgendaEvent] = []
    @Published private(set) var tomorrow: [AgendaEvent] = []
    @Published private(set) var calendars: [CalendarSource] = []

    private var observer: EventKitChangeObserver?

    private init() {
        observer = EventKitChangeObserver { [weak self] in self?.reload() }
        reload()
    }

    func requestAccess() async {
        access = await EventKitAccess.request(.event)
        reload()
    }

    func reload() {
        access = EventKitAccess.status(for: .event)
        guard access == .granted else {
            today = []
            tomorrow = []
            calendars = []
            return
        }

        let store = EventKitAccess.store
        let allCalendars = store.calendars(for: .event)
        calendars = allCalendars
            .map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: Color(nsColor: $0.color)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }

        let hidden = Defaults[.hiddenCalendarIDs]
        let visible = allCalendars.filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            today = []
            tomorrow = []
            return
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday)!

        let predicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: visible)
        let events = store.events(matching: predicate)
            .filter { !$0.isDeclinedByCurrentUser }
            .map(AgendaEvent.init)
            .filter { !(Defaults[.hideAllDayEvents] && $0.isAllDay) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }

        today = events.filter { $0.start < startOfTomorrow && $0.end > startOfToday }
        tomorrow = events.filter { $0.start >= startOfTomorrow }
    }

    /// The event the closed notch should talk about: one in progress,
    /// otherwise the next one starting within the look-ahead window.
    func focusEvent(at now: Date) -> AgendaEvent? {
        let timed = today.filter { !$0.isAllDay }
        if let current = timed.last(where: { $0.phase(at: now) == .now }) {
            return current
        }
        let lookahead = TimeInterval(Defaults[.eventLookaheadMinutes] * 60)
        return timed.first { $0.start > now && $0.start.timeIntervalSince(now) <= lookahead }
    }

    func setCalendar(_ id: String, visible: Bool) {
        if visible {
            Defaults[.hiddenCalendarIDs].remove(id)
        } else {
            Defaults[.hiddenCalendarIDs].insert(id)
        }
        reload()
    }
}

// MARK: - Mapping

private extension AgendaEvent {
    init(_ event: EKEvent) {
        self.init(
            id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
            eventIdentifier: event.calendarItemIdentifier,
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar?.color ?? .systemBlue),
            calendarTitle: event.calendar?.title ?? "",
            location: event.location?.isEmpty == false ? event.location : nil,
            meetingURL: MeetingLink.find(in: event),
            isRecurring: event.hasRecurrenceRules || event.isDetached
        )
    }
}

private extension EKEvent {
    var isDeclinedByCurrentUser: Bool {
        attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}

/// Finds a video-call link in an event's URL, location or notes.
enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "around.co", "facetime.apple.com", "meet.jit.si",
        "chime.aws", "gotomeeting.com", "bluejeans.com", "slack.com/huddle",
    ]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                if let url = match.url, isMeeting(url) { return url }
            }
        }
        return nil
    }

    private static func isMeeting(_ url: URL) -> Bool {
        let string = url.absoluteString.lowercased()
        return hosts.contains { string.contains($0) }
    }
}
