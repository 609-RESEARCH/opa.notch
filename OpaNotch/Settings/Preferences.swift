//
//  Preferences.swift
//  opa.notch
//

import Defaults
import Foundation
import KeyboardShortcuts

enum ReminderScope: String, CaseIterable, Identifiable, Defaults.Serializable {
    case today
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .all: "All"
        }
    }
}

extension Defaults.Keys {
    // General
    static let showMenuBarIcon = Key<Bool>("showMenuBarIcon", default: true)
    static let preferredScreenUUID = Key<String?>("preferredScreenUUID", default: nil)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)

    // Behavior
    static let openOnHover = Key<Bool>("openOnHover", default: true)
    static let hoverDelay = Key<Double>("hoverDelay", default: 0.25)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)

    // Agenda
    static let showLiveActivity = Key<Bool>("showLiveActivity", default: true)
    static let eventLookaheadMinutes = Key<Int>("eventLookaheadMinutes", default: 60)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let hiddenCalendarIDs = Key<Set<String>>("hiddenCalendarIDs", default: [])

    // Reminders
    static let reminderScope = Key<ReminderScope>("reminderScope", default: .today)
    static let defaultReminderListID = Key<String?>("defaultReminderListID", default: nil)
    static let hiddenReminderListIDs = Key<Set<String>>("hiddenReminderListIDs", default: [])
    static let showReminderCount = Key<Bool>("showReminderCount", default: true)
}

extension KeyboardShortcuts.Name {
    static let toggleNotch = Self("toggleNotch", default: .init(.n, modifiers: [.control, .option]))
    static let quickAddReminder = Self("quickAddReminder", default: .init(.r, modifiers: [.control, .option]))
}

enum Preferences {
    static var hapticsEnabled: Bool { Defaults[.enableHaptics] }
}
