import Foundation

struct ICSParser {
    static func parse(_ icsString: String) -> [SchoolCalendarEvent] {
        var events: [SchoolCalendarEvent] = []
        let lines = icsString.components(separatedBy: .newlines)

        var currentEvent: [String: String] = [:]
        var inEvent = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine == "BEGIN:VEVENT" {
                inEvent = true
                currentEvent = [:]
            } else if trimmedLine == "END:VEVENT" {
                if let event = createEvent(from: currentEvent) {
                    events.append(event)
                }
                inEvent = false
            } else if inEvent {
                if let colonIndex = trimmedLine.firstIndex(of: ":") {
                    let key = String(trimmedLine[..<colonIndex])
                    let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])

                    // Handle keys with parameters (e.g., DTSTART;VALUE=DATE:20250901)
                    let baseKey = key.components(separatedBy: ";").first ?? key
                    currentEvent[baseKey] = value

                    // Also store the full key for date parsing
                    if key != baseKey {
                        currentEvent["\(baseKey)_PARAMS"] = key
                    }
                }
            }
        }

        return events
    }

    private static func createEvent(from dict: [String: String]) -> SchoolCalendarEvent? {
        guard let summary = dict["SUMMARY"],
              let dtstart = dict["DTSTART"] else {
            return nil
        }

        let uid = dict["UID"] ?? UUID().uuidString
        let dtend = dict["DTEND"] ?? dtstart

        let isAllDay = dict["DTSTART_PARAMS"]?.contains("VALUE=DATE") ?? (dtstart.count == 8)

        guard let startDate = parseDate(dtstart, isAllDay: isAllDay),
              let endDate = parseDate(dtend, isAllDay: isAllDay) else {
            return nil
        }

        // Clean up summary (remove escaped characters)
        let cleanSummary = summary
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: "\n")

        return SchoolCalendarEvent(
            id: uid,
            summary: cleanSummary,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private static func parseDate(_ dateString: String, isAllDay: Bool) -> Date? {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")

        if isAllDay || dateString.count == 8 {
            // Format: YYYYMMDD
            formatter.dateFormat = "yyyyMMdd"
        } else if dateString.contains("T") {
            if dateString.hasSuffix("Z") {
                // Format: YYYYMMDDTHHMMSSZ (UTC)
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                formatter.timeZone = TimeZone(identifier: "UTC")
            } else {
                // Format: YYYYMMDDTHHMMSS (local time)
                formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            }
        } else {
            formatter.dateFormat = "yyyyMMdd"
        }

        return formatter.date(from: dateString)
    }
}
