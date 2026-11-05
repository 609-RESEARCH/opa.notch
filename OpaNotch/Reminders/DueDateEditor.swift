//
//  DueDateEditor.swift
//  opa.notch
//
//  The custom due date picker, drawn in the notch's own style rather than with the system's
//  date controls: flat on the panel, orange for what's selected, one big heading.
//

import SwiftUI

struct DueDateEditor: View {
    static let height: CGFloat = 196
    private static let dayCell: CGFloat = 24

    let item: ReminderItem
    @EnvironmentObject private var vm: NotchViewModel
    @ObservedObject private var store = RemindersStore.shared
    @State private var date: Date
    @State private var month: Date

    init(item: ReminderItem) {
        self.item = item
        let start = Self.startingDate(for: item)
        _date = State(initialValue: start)
        _month = State(initialValue: start)
    }

    /// The reminder's own time if it has one, 9:00 on its day if not, or the next full hour.
    private static func startingDate(for item: ReminderItem, now: Date = .now) -> Date {
        let cal = Calendar.current
        if let due = item.due {
            if item.dueHasTime { return due }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
        }
        return cal.dateInterval(of: .hour, for: now)?.end ?? now
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            calendar
                .frame(width: Self.dayCell * 7)
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Calendar

    private var calendar: some View {
        let cal = Calendar.current
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(Typography.section)
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                Spacer(minLength: 2)
                MonthArrow(systemName: "chevron.left", label: "Previous month") { moveMonth(by: -1) }
                MonthArrow(systemName: "chevron.right", label: "Next month") { moveMonth(by: 1) }
            }
            .frame(height: 22)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(cal.veryShortStandaloneWeekdaySymbols[(cal.firstWeekday - 1 + index) % 7])
                        .font(Typography.eyebrow)
                        .foregroundStyle(Palette.tertiary)
                        .frame(width: Self.dayCell)
                }
            }
            .frame(height: 14)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.dayCell), spacing: 0), count: 7), spacing: 0) {
                ForEach(DuePickerDate.gridDays(forMonthOf: month), id: \.self) { day in
                    DayButton(
                        day: day,
                        isSelected: cal.isDate(day, inSameDayAs: date),
                        isInMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        size: Self.dayCell
                    ) {
                        select(day)
                    }
                }
            }
            .id(cal.dateInterval(of: .month, for: month)?.start)
            .transition(.opacity)
        }
    }

    private func moveMonth(by months: Int) {
        guard let moved = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(Motion.adaptive(Motion.snappy)) { month = moved }
    }

    private func select(_ day: Date) {
        withAnimation(Motion.adaptive(Motion.snappy)) {
            date = DuePickerDate.moving(date, toDay: day)
            month = day
        }
    }

    // MARK: - Heading, time and actions

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DUE DATE")
                .font(Typography.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Palette.accent)
                .frame(height: 16, alignment: .leading)
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(Typography.heroTitle)
                .tracking(-0.3)
                .foregroundStyle(Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(item.title)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            timeField

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Button { vm.dismissDueEditor() } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.surfaceHover))
                }
                .buttonStyle(PressableStyle())

                Button(action: save) {
                    Text("Set")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.accent))
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var timeField: some View {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: date)
        let hour = time.hour ?? 0
        let minute = time.minute ?? 0
        let uses12Hours = Self.uses12HourClock
        let hourText = uses12Hours ? "\(hour % 12 == 0 ? 12 : hour % 12)" : String(format: "%02d", hour)

        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                TimeColumn(value: hourText, label: "Hour") { up in
                    step { DuePickerDate.steppingHour($0, by: up ? 1 : -1) }
                }
                Text(":")
                    .font(Typography.timeValue)
                    .foregroundStyle(Palette.tertiary)
                    .padding(.bottom, 2)
                TimeColumn(value: String(format: "%02d", minute), label: "Minute") { up in
                    step { DuePickerDate.steppingMinute($0, up: up) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .fill(Palette.surface)
            )

            if uses12Hours {
                MeridiemPicker(isPM: hour >= 12, amSymbol: cal.amSymbol, pmSymbol: cal.pmSymbol) { wantsPM in
                    guard wantsPM != (hour >= 12) else { return }
                    step { DuePickerDate.steppingHour($0, by: wantsPM ? 12 : -12) }
                }
            }
        }
    }

    /// Follows the same system time format as every other time shown in the app.
    private static var uses12HourClock: Bool {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.dateFormat.contains("a")
    }

    private func step(_ change: (Date) -> Date) {
        withAnimation(Motion.adaptive(Motion.snappy)) { date = change(date) }
    }

    private func save() {
        store.setDue(item, to: DueDate(date: date, hasTime: true))
        vm.dismissDueEditor()
    }
}

// MARK: - Pieces

private struct DayButton: View {
    let day: Date
    let isSelected: Bool
    let isInMonth: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var color: Color {
        if isSelected { return .black }
        if isToday { return Palette.accent }
        return isInMonth ? Palette.primary : Palette.tertiary
    }

    var body: some View {
        Button(action: action) {
            Text(day.formatted(.dateTime.day()))
                .font(Typography.numeric)
                .foregroundStyle(color)
                .frame(width: size - 2, height: size - 2)
                .background(
                    Circle().fill(isSelected ? Palette.accent : (hovering ? Palette.surfaceHover : .clear))
                )
                .frame(width: size, height: size)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MonthArrow: View {
    let systemName: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Palette.surfaceHover : .clear))
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .buttonRepeatBehavior(.enabled)
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .accessibilityLabel(label)
    }
}

/// A big value with an arrow above and below. Holding an arrow keeps stepping.
private struct TimeColumn: View {
    let value: String
    let label: String
    let step: (_ up: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            arrow("chevron.up", "\(label) up") { step(true) }
            Text(value)
                .font(Typography.timeValue)
                .foregroundStyle(Palette.primary)
                .contentTransition(.numericText())
                .frame(height: 26)
            arrow("chevron.down", "\(label) down") { step(false) }
        }
        .frame(width: 36)
    }

    private func arrow(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

/// AM/PM, styled like the Today/All switch.
private struct MeridiemPicker: View {
    let isPM: Bool
    let amSymbol: String
    let pmSymbol: String
    let select: (_ pm: Bool) -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            segment(amSymbol, selected: !isPM) { select(false) }
            segment(pmSymbol, selected: isPM) { select(true) }
        }
        .padding(2)
        .background(Capsule().fill(Palette.surface))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Palette.primary : Palette.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background {
                    if selected {
                        Capsule()
                            .fill(Palette.surfacePressed)
                            .matchedGeometryEffect(id: "meridiem", in: namespace)
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }
}
