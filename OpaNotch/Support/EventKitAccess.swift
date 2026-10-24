//
//  EventKitAccess.swift
//  opa.notch
//

import AppKit
import EventKit

/// One EKEventStore for the whole app; EventKit is happiest with a single long-lived store.
enum EventKitAccess {
    static let store = EKEventStore()

    enum Status: Equatable {
        case notDetermined
        case granted
        case denied
    }

    static func status(for type: EKEntityType) -> Status {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request(_ type: EKEntityType) async -> Status {
        do {
            let granted = switch type {
            case .event: try await store.requestFullAccessToEvents()
            case .reminder: try await store.requestFullAccessToReminders()
            @unknown default: false
            }
            return granted ? .granted : .denied
        } catch {
            return .denied
        }
    }

    static func openPrivacySettings(for type: EKEntityType) {
        let anchor = type == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openApp(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

/// Fires `action` whenever data that EventKit-backed views depend on may have changed:
/// the store itself, the calendar day rolling over, or the Mac waking up.
final class EventKitChangeObserver {
    private var tokens: [NSObjectProtocol] = []

    init(_ action: @escaping @MainActor () -> Void) {
        let run: (Notification) -> Void = { _ in MainActor.assumeIsolated { action() } }
        tokens.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: EventKitAccess.store, queue: .main, using: run))
        tokens.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: run))
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: run))
    }

    deinit {
        tokens.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }
}
