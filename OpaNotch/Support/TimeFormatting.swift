//
//  TimeFormatting.swift
//  opa.notch
//

import Foundation

enum TimeFormatting {
    /// "12m", "1h", "1h 5m" — rounded up so "in 1m" never shows for an event that started.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// Short, specific due labels: "3:00 PM", "Tomorrow", "Yesterday", "Mon 27 Oct".
    static func due(_ date: Date, hasTime: Bool, now: Date = .now) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDate(date, inSameDayAs: now) {
            day = hasTime ? "" : "Today"
        } else if cal.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if cal.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        guard hasTime else { return day }
        return day.isEmpty ? time(date) : "\(day), \(time(date))"
    }
}
