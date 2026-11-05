//
//  DueShortcut.swift
//  opa.notch
//

import Foundation

/// A reminder's due date. Without a time it's due that day, with no alert.
struct DueDate: Equatable {
    var date: Date
    var hasTime: Bool
}

/// The quick due dates in a reminder's right-click menu. "None" is always offered too.
enum DueShortcut: CaseIterable, Identifiable {
    case none
    case today
    case tomorrow
    case friday
    case monday

    /// The time Friday and Monday are set for.
    private static let workdayStartHour = 9

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .friday: "Friday \(Self.workdayStartLabel)"
        case .monday: "Monday \(Self.workdayStartLabel)"
        }
    }

    private static var workdayStartLabel: String {
        let date = Calendar.current.date(bySettingHour: workdayStartHour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The date this shortcut sets. Today and Tomorrow keep the time `current` has, if any.
    func due(replacing current: DueDate?, now: Date = .now, calendar cal: Calendar = .current) -> DueDate? {
        switch self {
        case .none:
            return nil
        case .today:
            return Self.day(cal.startOfDay(for: now), keepingTimeOf: current, calendar: cal)
        case .tomorrow:
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
            return Self.day(tomorrow, keepingTimeOf: current, calendar: cal)
        case .friday:
            return Self.next(weekday: 6, after: now, calendar: cal)
        case .monday:
            return Self.next(weekday: 2, after: now, calendar: cal)
        }
    }

    private static func day(_ day: Date, keepingTimeOf current: DueDate?, calendar cal: Calendar) -> DueDate {
        guard let current, current.hasTime else { return DueDate(date: day, hasTime: false) }
        let time = cal.dateComponents([.hour, .minute], from: current.date)
        let date = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return DueDate(date: date, hasTime: true)
    }

    /// The next time that weekday's 9:00 comes around. `weekday` runs from 1 (Sunday) to 7.
    private static func next(weekday: Int, after now: Date, calendar cal: Calendar) -> DueDate? {
        let target = DateComponents(hour: workdayStartHour, minute: 0, second: 0, weekday: weekday)
        return cal.nextDate(after: now, matching: target, matchingPolicy: .nextTime).map { DueDate(date: $0, hasTime: true) }
    }

    /// The dates to offer in the menu. Friday or Monday is left out when it would land on
    /// today or tomorrow: on a Thursday, "Tomorrow" and "Friday" are the same day.
    static func available(now: Date = .now, calendar cal: Calendar = .current) -> [DueShortcut] {
        [.today, .tomorrow] + [.friday, .monday].filter { shortcut in
            guard let date = shortcut.due(replacing: nil, now: now, calendar: cal)?.date else { return false }
            return !cal.isDateInToday(date, relativeTo: now) && !cal.isDateInTomorrow(date, relativeTo: now)
        }
    }

    /// The offered shortcut a due date corresponds to, so the menu can tick it. Friday and
    /// Monday need the exact time; Today and Tomorrow match the whole day.
    static func matching(_ current: DueDate?, now: Date = .now, calendar cal: Calendar = .current) -> DueShortcut? {
        guard let current else { return DueShortcut.none }
        return available(now: now, calendar: cal).first { shortcut in
            guard let due = shortcut.due(replacing: nil, now: now, calendar: cal) else { return false }
            switch shortcut {
            case .friday, .monday:
                return current.hasTime && abs(due.date.timeIntervalSince(current.date)) < 60
            default:
                return cal.isDate(due.date, inSameDayAs: current.date)
            }
        }
    }
}

/// The date arithmetic behind the custom due date picker.
enum DuePickerDate {
    /// Six weeks starting on the locale's first weekday. A constant six rows keeps the
    /// calendar the same height from month to month.
    static func gridDays(forMonthOf date: Date, calendar cal: Calendar = .current) -> [Date] {
        guard let month = cal.dateInterval(of: .month, for: date)?.start else { return [] }
        let leadingDays = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0 - leadingDays, to: month) }
    }

    /// Moves to `day`, keeping the time of day.
    static func moving(_ date: Date, toDay day: Date, calendar cal: Calendar = .current) -> Date {
        let time = cal.dateComponents([.hour, .minute], from: date)
        return setting(hour: time.hour ?? 0, minute: time.minute ?? 0, of: day, calendar: cal)
    }

    /// Steps the hour, wrapping around midnight without changing the day.
    static func steppingHour(_ date: Date, by delta: Int, calendar cal: Calendar = .current) -> Date {
        let time = cal.dateComponents([.hour, .minute], from: date)
        let hour = ((time.hour ?? 0) + delta + 24) % 24
        return setting(hour: hour, minute: time.minute ?? 0, of: date, calendar: cal)
    }

    /// Steps to the next multiple of five minutes, wrapping within the hour.
    static func steppingMinute(_ date: Date, up: Bool, calendar cal: Calendar = .current) -> Date {
        let time = cal.dateComponents([.hour, .minute], from: date)
        let minute = time.minute ?? 0
        let stepped = up ? (minute / 5 + 1) * 5 : (minute - 1 + 60) / 5 * 5 - 60
        return setting(hour: time.hour ?? 0, minute: (stepped + 60) % 60, of: date, calendar: cal)
    }

    private static func setting(hour: Int, minute: Int, of day: Date, calendar cal: Calendar) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

private extension Calendar {
    func isDateInToday(_ date: Date, relativeTo now: Date) -> Bool {
        isDate(date, inSameDayAs: now)
    }

    func isDateInTomorrow(_ date: Date, relativeTo now: Date) -> Bool {
        guard let tomorrow = self.date(byAdding: .day, value: 1, to: now) else { return false }
        return isDate(date, inSameDayAs: tomorrow)
    }
}
