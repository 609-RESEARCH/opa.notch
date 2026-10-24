//
//  ReminderParser.swift
//  opa.notch
//

import Foundation

/// Pulls a natural-language date out of a quick-add line using NSDataDetector,
/// so "Send deck to Lea tomorrow 9am" becomes "Send deck to Lea", due tomorrow 09:00.
enum ReminderParser {
    struct Result: Equatable {
        var title: String
        var due: Date?
        var hasTime: Bool
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let danglingWords: Set<String> = ["at", "on", "by", "due", "for", "@", "-", "–"]

    static func parse(_ text: String, now: Date = .now) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)

        guard let match = detector?.firstMatch(in: trimmed, range: fullRange),
              let date = match.date,
              let range = Range(match.range, in: trimmed)
        else {
            return Result(title: trimmed, due: nil, hasTime: false)
        }

        let phrase = trimmed[range].lowercased()
        let hasTime = mentionsTime(phrase)

        var title = trimmed
        title.removeSubrange(range)
        title = tidy(title)

        // A phrase that is the whole text ("tomorrow") isn't a title; keep it as written.
        guard !title.isEmpty else {
            return Result(title: trimmed, due: nil, hasTime: false)
        }

        // "Pay rent friday" detected as last Friday is never what someone means.
        let due = (!hasTime && date < Calendar.current.startOfDay(for: now))
            ? Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
            : date

        return Result(title: title, due: due, hasTime: hasTime)
    }

    private static func mentionsTime(_ phrase: String) -> Bool {
        if phrase.contains(":") || phrase.contains("noon") || phrase.contains("midnight") { return true }
        if phrase.range(of: #"\d\s*(am|pm|h)\b"#, options: .regularExpression) != nil { return true }
        if phrase.contains("morning") || phrase.contains("afternoon") || phrase.contains("evening") || phrase.contains("tonight") { return true }
        return false
    }

    private static func tidy(_ text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, danglingWords.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, danglingWords.contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
    }
}
