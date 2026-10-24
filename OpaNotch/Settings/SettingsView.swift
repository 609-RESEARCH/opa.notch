//
//  SettingsView.swift
//  opa.notch
//

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

/// Shared between the sidebar and the detail pane, which live in separate split-view items.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var pane: SettingsPane = .general
}

/// System Settings–style sidebar: app identity on top, then a coloured icon tile per pane.
/// It sits in an AppKit sidebar split item, which supplies the floating glass panel.
struct SettingsSidebar: View {
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        List(selection: $selection.pane) {
            AppIdentityRow()
                .selectionDisabled()
                .padding(.bottom, 6)

            ForEach(SettingsPane.allCases) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIconTile(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

struct SettingsDetail: View {
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        selection.pane.content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case today
    case reminders
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .today: "Today"
        case .reminders: "Reminders"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .today: "calendar"
        case .reminders: "checklist"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .today: .red
        case .reminders: .orange
        case .about: .blue
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettings()
        case .today: AgendaSettings()
        case .reminders: RemindersSettings()
        case .about: AboutSettings()
        }
    }
}

/// The rounded-square, top-lit icon System Settings uses for each pane.
private struct SettingsIconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

private struct AppIdentityRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("opa.notch")
                    .font(.system(size: 13, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Default(.showMenuBarIcon) private var showMenuBarIcon
    @Default(.preferredScreenUUID) private var preferredScreenUUID
    @Default(.hideFromScreenRecording) private var hideFromScreenRecording
    @Default(.openOnHover) private var openOnHover
    @Default(.hoverDelay) private var hoverDelay
    @Default(.enableHaptics) private var enableHaptics

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Open at login")
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                Picker("Display", selection: $preferredScreenUUID) {
                    Text("Automatic (built-in notch)").tag(String?.none)
                    ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                        Text(screen.localizedName).tag(screen.displayUUID)
                    }
                }
                Toggle("Hide from screen sharing and recordings", isOn: $hideFromScreenRecording)
            }

            Section("Opening") {
                Toggle("Open when the pointer rests on the notch", isOn: $openOnHover)
                if openOnHover {
                    LabeledContent("Delay") {
                        HStack(spacing: 10) {
                            Slider(value: $hoverDelay, in: 0...1)
                                .frame(width: 180)
                            Text(Duration.milliseconds(Int((hoverDelay * 20).rounded() * 50)), format: .units(allowed: [.seconds, .milliseconds], width: .abbreviated))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
                Toggle("Haptic feedback", isOn: $enableHaptics)
            }

            Section("Keyboard shortcuts") {
                KeyboardShortcuts.Recorder("Open or close the notch", name: .toggleNotch)
                KeyboardShortcuts.Recorder("New reminder", name: .quickAddReminder)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Today

private struct AgendaSettings: View {
    @ObservedObject private var store = AgendaStore.shared
    @Default(.showLiveActivity) private var showLiveActivity
    @Default(.eventLookaheadMinutes) private var lookahead
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hiddenCalendarIDs) private var hiddenCalendarIDs

    var body: some View {
        Form {
            Section("Closed notch") {
                Toggle("Show next meeting and reminders beside the notch", isOn: $showLiveActivity)
                Picker("Show a meeting countdown", selection: $lookahead) {
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                }
                .disabled(!showLiveActivity)
            }

            Section("Today") {
                Toggle("Hide all-day events", isOn: $hideAllDayEvents)
                    .onChange(of: hideAllDayEvents) { _, _ in store.reload() }
            }

            Section("Calendars") {
                if store.access != .granted {
                    accessRow
                } else {
                    ForEach(store.calendars) { calendar in
                        Toggle(isOn: Binding(
                            get: { !hiddenCalendarIDs.contains(calendar.id) },
                            set: { store.setCalendar(calendar.id, visible: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Circle().fill(calendar.color).frame(width: 9, height: 9)
                                Text(calendar.title)
                                Text(calendar.account).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accessRow: some View {
        HStack {
            Text("opa.notch needs Calendar access to show your day.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(store.access == .denied ? "Open Privacy Settings" : "Allow Access") {
                if store.access == .denied {
                    EventKitAccess.openPrivacySettings(for: .event)
                } else {
                    Task { await store.requestAccess() }
                }
            }
        }
    }
}

// MARK: - Reminders

private struct RemindersSettings: View {
    @ObservedObject private var store = RemindersStore.shared
    @Default(.defaultReminderListID) private var defaultListID
    @Default(.hiddenReminderListIDs) private var hiddenListIDs
    @Default(.showReminderCount) private var showReminderCount

    var body: some View {
        Form {
            Section {
                Toggle("Show today's count beside the notch", isOn: $showReminderCount)
                Picker("Add new reminders to", selection: $defaultListID) {
                    Text("Default list").tag(String?.none)
                    ForEach(store.lists) { list in
                        Text(list.title).tag(Optional(list.id))
                    }
                }
            } footer: {
                Text("Type dates naturally: “Send invoice friday 10am” is due Friday at 10:00 and gets an alert. In Today, reminders without a date are due today.")
                    .foregroundStyle(.secondary)
            }

            Section("Lists") {
                if store.access != .granted {
                    HStack {
                        Text("opa.notch needs Reminders access.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(store.access == .denied ? "Open Privacy Settings" : "Allow Access") {
                            if store.access == .denied {
                                EventKitAccess.openPrivacySettings(for: .reminder)
                            } else {
                                Task { await store.requestAccess() }
                            }
                        }
                    }
                } else {
                    ForEach(store.lists) { list in
                        Toggle(isOn: Binding(
                            get: { !hiddenListIDs.contains(list.id) },
                            set: { store.setList(list.id, visible: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Circle().fill(list.color).frame(width: 9, height: 9)
                                Text(list.title)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettings: View {
    private static let studioURL = URL(string: "https://609-research.github.io")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("opa.notch")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Your day and your reminders, living in the notch.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer().frame(height: 18)

            Text("DESIGNED, CRAFTED\nAND ENGINEERED BY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            // The logo is the link: clicking it opens the studio's website.
            Link(destination: Self.studioURL) {
                Image("609ResearchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                    .accessibilityLabel("609 Research website")
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .help("Visit 609 Research")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Spacer().frame(height: 18)

            Text("Free software under the GNU GPL v3.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
