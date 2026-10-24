//
//  RemindersPanel.swift
//  opa.notch
//

import Defaults
import SwiftUI

struct RemindersPanel: View {
    @ObservedObject var store = RemindersStore.shared
    @Default(.reminderScope) private var scope
    let now: Date

    var body: some View {
        PanelSurface {
            switch store.access {
            case .granted:
                header
                QuickAddField(scope: scope)
                list
            case .notDetermined, .denied:
                AccessPrompt(
                    symbol: "checklist",
                    title: "Your reminders, one glance away",
                    message: "See, add and check off reminders without leaving your work.",
                    status: store.access,
                    request: { await store.requestAccess() },
                    openSettings: { EventKitAccess.openPrivacySettings(for: .reminder) }
                )
            }
        }
    }

    /// The block's hero: one big number in the brand colour (red once anything is overdue).
    private var header: some View {
        let count = counts[scope] ?? 0
        let overdue = scope == .today ? store.dueCount(at: now).overdue : 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .font(Typography.heroNumber)
                .foregroundStyle(count == 0 ? Palette.tertiary : (overdue > 0 ? Palette.overdue : Palette.accent))
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 0) {
                Text(scope == .today ? "due today" : (count == 1 ? "reminder" : "reminders"))
                    .font(Typography.section)
                    .foregroundStyle(Palette.primary)
                if overdue > 0 {
                    Text("\(overdue) overdue")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.overdue)
                }
            }
            Spacer(minLength: 4)
            ScopePicker(selection: $scope, counts: counts)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.headerHeight)
        .animation(Motion.adaptive(Motion.standard), value: count)
    }

    // MARK: Sizing

    static let headerHeight: CGFloat = 38
    static let quickAddHeight: CGFloat = 30
    static let emptyHeight: CGFloat = 80

    /// The height this block wants, so the notch can size itself to its content.
    @MainActor
    static func idealHeight(store: RemindersStore, scope: ReminderScope, now: Date) -> CGFloat {
        guard store.access == .granted else { return Metrics.panelChrome + Metrics.accessPromptHeight }
        let count = store.visibleItems(scope: scope, at: now).count
        let list = count == 0 ? emptyHeight : CGFloat(count) * Metrics.rowHeight + 8
        return Metrics.panelChrome + headerHeight + Metrics.panelSpacing + quickAddHeight + Metrics.panelSpacing + list
    }

    private var counts: [ReminderScope: Int] {
        [
            .today: store.visibleItems(scope: .today, at: now).filter { !$0.isCompleted }.count,
            .all: store.items.filter { !$0.isCompleted }.count,
        ]
    }

    @ViewBuilder
    private var list: some View {
        let items = store.visibleItems(scope: scope, at: now)
        if items.isEmpty {
            EmptyPanelState(
                symbol: "checkmark.circle",
                title: scope == .today ? "All clear for today" : "No reminders",
                detail: scope == .today && !store.items.isEmpty ? "\(store.items.count) more in All" : nil
            )
            .transition(.opacity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        ReminderRow(item: item, showList: scope == .all, now: now)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
                            ))
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeFade(top: 2, bottom: 10)
            .animation(Motion.adaptive(Motion.standard), value: items.map(\.id))
        }
    }
}

// MARK: - Scope picker

/// Two-segment control whose highlight slides between options on a spring.
private struct ScopePicker: View {
    @Binding var selection: ReminderScope
    let counts: [ReminderScope: Int]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReminderScope.allCases) { scope in
                Button {
                    withAnimation(Motion.adaptive(Motion.standard)) { selection = scope }
                } label: {
                    HStack(spacing: 4) {
                        Text(scope.title)
                        if let count = counts[scope], count > 0 {
                            Text("\(count)")
                                .foregroundStyle(selection == scope ? Palette.secondary : Palette.tertiary)
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selection == scope ? Palette.primary : Palette.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background {
                        if selection == scope {
                            Capsule()
                                .fill(Palette.surfacePressed)
                                .matchedGeometryEffect(id: "scope", in: namespace)
                        }
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.94))
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.surface))
    }
}

// MARK: - Quick add

private struct QuickAddField: View {
    let scope: ReminderScope
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var store = RemindersStore.shared
    @State private var text = ""
    @State private var shake = 0
    @FocusState private var focused: Bool

    private var preview: ReminderParser.Result? {
        let result = ReminderParser.parse(text)
        return result.due == nil ? nil : result
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(focused ? Palette.accent : Palette.tertiary)

            TextField("", text: $text, prompt: Text("New reminder").foregroundStyle(Palette.tertiary))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.primary)
                .focused($focused)
                .onSubmit(submit)

            // Inline feedback: show the date we understood before the user commits.
            if let preview, let due = preview.due {
                Text(TimeFormatting.due(due, hasTime: preview.hasTime))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Palette.accent.opacity(0.18)))
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: RemindersPanel.quickAddHeight)
        .background(Capsule().fill(focused ? Palette.surfacePressed : Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(focused ? 0.6 : 0), lineWidth: 1.5))
        .modifier(ShakeEffect(shakes: CGFloat(shake)))
        .animation(Motion.adaptive(Motion.snappy), value: focused)
        .animation(Motion.adaptive(Motion.standard), value: preview?.due)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in
            if isFocused { vm.beginKeyboard() }
        }
        .onChange(of: text) { _, newValue in
            vm.hasQuickAddDraft = !newValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .onChange(of: vm.quickAddFocusRequest) { _, _ in
            focused = true
        }
        .onChange(of: vm.isOpen) { _, isOpen in
            if !isOpen {
                focused = false
                text = ""
            }
        }
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if store.add(text, scope: scope) {
            text = ""
        } else {
            withAnimation(Motion.adaptive(.linear(duration: 0.3))) { shake += 1 }
        }
    }
}

/// Error feedback for a failed save: a short horizontal shake.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(shakes * .pi * 4), y: 0))
    }
}

// MARK: - Row

private struct ReminderRow: View {
    let item: ReminderItem
    let showList: Bool
    let now: Date
    @ObservedObject var store = RemindersStore.shared
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 9) {
            Checkbox(checked: item.isCompleted, color: item.listColor) {
                store.toggle(item)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if !item.priorityMarks.isEmpty {
                        Text(item.priorityMarks)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(item.listColor)
                    }
                    Text(item.title)
                        .font(Typography.body)
                        .foregroundStyle(item.isCompleted ? Palette.tertiary : Palette.primary)
                        .strikethrough(item.isCompleted, color: Palette.tertiary)
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(item.isOverdue(at: now) ? Palette.overdue : Palette.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.rowHeight)
        .hoverHighlight()
        .contentShape(Rectangle())
        .contextMenu { menu }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let due = item.due {
            let label = TimeFormatting.due(due, hasTime: item.dueHasTime, now: now)
            if item.isOverdue(at: now) {
                parts.append(label == "Today" ? "Overdue" : "Overdue · \(label)")
            } else if !(label == "Today" && !showList) {
                parts.append(label)
            }
        }
        if showList { parts.append(item.listTitle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            store.toggle(item)
        } label: {
            Label(item.isCompleted ? "Mark as Not Completed" : "Mark as Completed",
                  systemImage: item.isCompleted ? "circle" : "smallcircle.filled.circle")
        }

        Menu {
            // No tick when the date matches none of the shortcuts.
            Picker("Due Date", selection: Binding(
                get: { DueShortcut.matching(item.due, now: now) },
                set: { if let shortcut = $0 { store.setDue(item, to: shortcut.day()) } }
            )) {
                Text(DueShortcut.none.title).tag(Optional(DueShortcut.none))
                Divider()
                ForEach(DueShortcut.allCases.filter { $0 != .none }) { shortcut in
                    Text(shortcut.title).tag(Optional(shortcut))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Due Date", systemImage: "calendar")
        }

        Menu {
            Picker("Priority", selection: Binding(
                get: { item.priorityLevel },
                set: { store.setPriority(item, $0) }
            )) {
                ForEach(ReminderPriority.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Priority", systemImage: "exclamationmark")
        }

        Divider()
        Button {
            if let url = item.remindersAppURL {
                NSWorkspace.shared.open(url)
            } else {
                EventKitAccess.openApp(bundleIdentifier: "com.apple.reminders")
            }
            vm.close(force: true, restoreFocus: false)
        } label: {
            Label("Open in Reminders", systemImage: "arrow.up.forward.app")
        }
        Divider()
        Button(role: .destructive) {
            store.delete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// Reminders-style checkbox. The press shrinks it instantly; the check pops in on a spring.
private struct Checkbox: View {
    let checked: Bool
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? color : (hovering ? color : Palette.tertiary), lineWidth: 1.5)
                Circle()
                    .fill(color)
                    .padding(3)
                    .scaleEffect(checked ? 1 : 0.2)
                    .opacity(checked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black)
                    .scaleEffect(checked ? 1 : 0.4)
                    .opacity(checked ? 1 : 0)
            }
            .frame(width: 17, height: 17)
            .frame(width: 24, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.82))
        .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72)), value: checked)
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .help(checked ? "Mark as not done" : "Mark as done")
    }
}
