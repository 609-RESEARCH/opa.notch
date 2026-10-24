//
//  RemindersStore.swift
//  opa.notch
//

import AppKit
import Defaults
import EventKit
import SwiftUI

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let dueHasTime: Bool
    let isCompleted: Bool
    /// EventKit priority: 1 (high) … 9 (low), 0 = none.
    let priority: Int
    let listID: String
    let listTitle: String
    let listColor: Color

    func isOverdue(at now: Date) -> Bool {
        guard let due, !isCompleted else { return false }
        return dueHasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    func isDueToday(at now: Date) -> Bool {
        guard let due else { return false }
        return Calendar.current.isDate(due, inSameDayAs: now)
    }

    var priorityLevel: ReminderPriority { ReminderPriority(eventKitValue: priority) }

    var priorityMarks: String { priorityLevel.marks }

    var remindersAppURL: URL? {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            .flatMap { URL(string: "x-apple-reminderkit://REMCDReminder/\($0)") }
    }

    func with(completed: Bool? = nil, priority: Int? = nil) -> ReminderItem {
        ReminderItem(id: id, title: title, due: due, dueHasTime: dueHasTime, isCompleted: completed ?? isCompleted,
                     priority: priority ?? self.priority, listID: listID, listTitle: listTitle, listColor: listColor)
    }
}

/// The quick due dates the Reminders app offers in its context menu.
enum DueShortcut: CaseIterable, Identifiable {
    case none
    case today
    case tomorrow
    case nextWeekend
    case nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeekend: "Next Weekend"
        case .nextWeek: "Next Week"
        }
    }

    func day(from now: Date = .now, calendar cal: Calendar = .current) -> Date? {
        let today = cal.startOfDay(for: now)
        switch self {
        case .none:
            return nil
        case .today:
            return today
        case .tomorrow:
            return cal.date(byAdding: .day, value: 1, to: today)
        case .nextWeekend:
            // The coming weekend; on a weekend, the one after.
            return cal.nextWeekend(startingAfter: now)?.start
        case .nextWeek:
            // The first day of next week, per the user's locale (Monday in most of Europe).
            return cal.nextDate(after: today, matching: DateComponents(weekday: cal.firstWeekday), matchingPolicy: .nextTime)
        }
    }

    /// The shortcut a due date corresponds to, so the menu can tick it.
    static func matching(_ due: Date?, now: Date = .now) -> DueShortcut? {
        guard let due else { return DueShortcut.none }
        return allCases.first { shortcut in
            shortcut.day(from: now).map { Calendar.current.isDate($0, inSameDayAs: due) } ?? false
        }
    }
}

/// The four levels the Reminders app offers, mapped onto EventKit's RFC 5545 values
/// (1–4 high, 5 medium, 6–9 low, 0 none).
enum ReminderPriority: CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: Self { self }

    init(eventKitValue: Int) {
        switch eventKitValue {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var eventKitValue: Int {
        switch self {
        case .none: Int(EKReminderPriority.none.rawValue)
        case .low: Int(EKReminderPriority.low.rawValue)
        case .medium: Int(EKReminderPriority.medium.rawValue)
        case .high: Int(EKReminderPriority.high.rawValue)
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var marks: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }
}

struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

@MainActor
final class RemindersStore: ObservableObject {
    static let shared = RemindersStore()

    /// How long a checked-off reminder lingers (struck through) so a slip can be undone.
    static let completionGrace: Duration = .seconds(1.6)

    @Published private(set) var access: EventKitAccess.Status = EventKitAccess.status(for: .reminder)
    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var lists: [ReminderList] = []

    private var lingering: [String: ReminderItem] = [:]
    private var lingerTasks: [String: Task<Void, Never>] = [:]
    private var observer: EventKitChangeObserver?
    private var fetchGeneration = 0

    private init() {
        observer = EventKitChangeObserver { [weak self] in self?.reload() }
        reload()
    }

    // MARK: - Reading

    func requestAccess() async {
        access = await EventKitAccess.request(.reminder)
        reload()
    }

    func reload() {
        access = EventKitAccess.status(for: .reminder)
        guard access == .granted else {
            items = []
            lists = []
            return
        }

        let store = EventKitAccess.store
        let calendars = store.calendars(for: .reminder)
        lists = calendars
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let hidden = Defaults[.hiddenReminderListIDs]
        let visible = calendars.filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            items = Array(lingering.values)
            return
        }

        fetchGeneration += 1
        let generation = fetchGeneration
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: visible)
        store.fetchReminders(matching: predicate) { reminders in
            let fetched = (reminders ?? []).map(ReminderItem.init)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A newer fetch may have started while this one ran.
                    guard generation == self.fetchGeneration else { return }
                    self.apply(fetched)
                }
            }
        }
    }

    private func apply(_ fetched: [ReminderItem]) {
        let fetchedIDs = Set(fetched.map(\.id))
        let merged = fetched + lingering.values.filter { !fetchedIDs.contains($0.id) }
        items = merged.sorted(by: Self.order)
    }

    private static func order(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        let aDue = a.due ?? .distantFuture
        let bDue = b.due ?? .distantFuture
        if aDue != bDue { return aDue < bDue }
        let aPriority = a.priority == 0 ? 10 : a.priority
        let bPriority = b.priority == 0 ? 10 : b.priority
        if aPriority != bPriority { return aPriority < bPriority }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    func visibleItems(scope: ReminderScope, at now: Date) -> [ReminderItem] {
        switch scope {
        case .all:
            return items
        case .today:
            let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            return items.filter { item in
                guard let due = item.due else { return false }
                return due < startOfTomorrow
            }
        }
    }

    /// Open reminders due today or overdue, for the closed-notch badge.
    func dueCount(at now: Date) -> (total: Int, overdue: Int) {
        let open = visibleItems(scope: .today, at: now).filter { !$0.isCompleted }
        return (open.count, open.filter { $0.isOverdue(at: now) }.count)
    }

    // MARK: - Writing

    /// Creates a reminder from free text. Dates written naturally ("call Sam tomorrow 3pm")
    /// become the due date and are stripped from the title.
    @discardableResult
    func add(_ text: String, scope: ReminderScope) -> Bool {
        let parsed = ReminderParser.parse(text)
        guard !parsed.title.isEmpty, access == .granted else { return false }

        let store = EventKitAccess.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = parsed.title
        reminder.calendar = defaultList() ?? store.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else { return false }

        let due = parsed.due ?? (scope == .today ? Date.now : nil)
        if let due {
            let hasTime = parsed.due != nil && parsed.hasTime
            reminder.dueDateComponents = Self.components(for: due, includeTime: hasTime)
            if hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
        }

        do {
            try store.save(reminder, commit: true)
            Haptics.levelChange()
            reload()
            return true
        } catch {
            NSLog("opa.notch: failed to save reminder: \(error)")
            return false
        }
    }

    /// Checking off saves immediately, but the row lingers for a moment so it can be unchecked.
    func toggle(_ item: ReminderItem) {
        let completed = !item.isCompleted
        guard persistCompletion(of: item, completed: completed) else { return }

        lingerTasks[item.id]?.cancel()
        if completed {
            Haptics.levelChange()
            lingering[item.id] = item.with(completed: true)
            lingerTasks[item.id] = Task { [weak self] in
                try? await Task.sleep(for: Self.completionGrace)
                guard !Task.isCancelled, let self else { return }
                withAnimation(Motion.adaptive(Motion.standard)) {
                    self.lingering[item.id] = nil
                    self.items.removeAll { $0.id == item.id && $0.isCompleted }
                }
                self.lingerTasks[item.id] = nil
            }
        } else {
            lingering[item.id] = nil
            lingerTasks[item.id] = nil
        }

        withAnimation(Motion.adaptive(Motion.standard)) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item.with(completed: completed)
            }
        }
    }

    private func persistCompletion(of item: ReminderItem, completed: Bool) -> Bool {
        guard let reminder = EventKitAccess.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return false }
        reminder.isCompleted = completed
        do {
            try EventKitAccess.store.save(reminder, commit: true)
            return true
        } catch {
            NSLog("opa.notch: failed to update reminder: \(error)")
            return false
        }
    }

    func setPriority(_ item: ReminderItem, _ priority: ReminderPriority) {
        guard item.priorityLevel != priority,
              let reminder = EventKitAccess.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.priority = priority.eventKitValue
        do {
            try EventKitAccess.store.save(reminder, commit: true)
        } catch {
            NSLog("opa.notch: failed to set priority: \(error)")
            return
        }
        // Show the new marks immediately; the reload that follows re-sorts by priority.
        withAnimation(Motion.adaptive(Motion.standard)) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item.with(priority: priority.eventKitValue)
            }
        }
        reload()
    }

    /// Moves the reminder to `day`, keeping its time of day (and its alert) if it had one.
    func setDue(_ item: ReminderItem, to day: Date?) {
        guard let reminder = EventKitAccess.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        let cal = Calendar.current

        // The alert opa.notch adds for timed reminders is pinned to the old moment.
        if let old = item.due, item.dueHasTime {
            for alarm in reminder.alarms ?? [] where alarm.absoluteDate == old {
                reminder.removeAlarm(alarm)
            }
        }

        if let day {
            var due = cal.startOfDay(for: day)
            if let old = item.due, item.dueHasTime {
                let time = cal.dateComponents([.hour, .minute], from: old)
                due = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: due) ?? due
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
            reminder.dueDateComponents = Self.components(for: due, includeTime: item.dueHasTime)
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try EventKitAccess.store.save(reminder, commit: true)
        } catch {
            NSLog("opa.notch: failed to set due date: \(error)")
        }
        reload()
    }

    func delete(_ item: ReminderItem) {
        guard let reminder = EventKitAccess.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        try? EventKitAccess.store.remove(reminder, commit: true)
        lingering[item.id] = nil
        reload()
    }

    func setList(_ id: String, visible: Bool) {
        if visible {
            Defaults[.hiddenReminderListIDs].remove(id)
        } else {
            Defaults[.hiddenReminderListIDs].insert(id)
        }
        reload()
    }

    private func defaultList() -> EKCalendar? {
        guard let id = Defaults[.defaultReminderListID] else { return nil }
        return EventKitAccess.store.calendar(withIdentifier: id)
    }

    private static func components(for date: Date, includeTime: Bool) -> DateComponents {
        var units: Set<Calendar.Component> = [.year, .month, .day]
        if includeTime { units.formUnion([.hour, .minute]) }
        var components = Calendar.current.dateComponents(units, from: date)
        components.timeZone = includeTime ? .current : nil
        return components
    }
}

private extension ReminderItem {
    init(_ reminder: EKReminder) {
        let components = reminder.dueDateComponents
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: components.flatMap { Calendar.current.date(from: $0) },
            dueHasTime: components?.hour != nil,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "",
            listColor: Color(nsColor: reminder.calendar?.color ?? .systemOrange)
        )
    }
}
