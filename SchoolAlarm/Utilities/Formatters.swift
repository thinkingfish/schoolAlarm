import Foundation

/// Cached DateFormatters to avoid repeated allocations
/// DateFormatter is expensive to create - reuse instances instead
enum Formatters {
    // MARK: - Time Formatters

    /// Format: "7:00 AM" (h:mm a)
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Format: "7:00" (h:mm)
    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    /// Format: "AM" or "PM" (a)
    static let period: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f
    }()

    // MARK: - Date Formatters

    /// Format: "January 2026" (MMMM yyyy)
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Format: "Mon, Jan 15" (EEE, MMM d)
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// Format: "Jan 15" (MMM d)
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Format: "15" (d) - day number only
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// Format: "Monday, Jan 15" (EEEE, MMM d)
    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Format: "Monday, Jan 15, 2026" (EEEE, MMM d, yyyy)
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f
    }()

    /// Format: "Monday" (EEEE)
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// Format: "Mon" (EEE)
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    // MARK: - Combined Formatters

    /// Short date + time: "1/15/26, 7:00 AM"
    static let dateTimeShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
