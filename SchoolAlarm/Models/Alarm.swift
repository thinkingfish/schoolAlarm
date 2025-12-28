import Foundation

struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var time: Date
    var label: String
    var isEnabled: Bool
    var snoozeEnabled: Bool

    // Legacy property for backwards compatibility with saved data
    var sound: AlarmSound?

    var hour: Int {
        Calendar.current.component(.hour, from: time)
    }

    var minute: Int {
        Calendar.current.component(.minute, from: time)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: time)
    }

    var periodString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter.string(from: time)
    }

    static func defaultAlarm() -> Alarm {
        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        let time = Calendar.current.date(from: components) ?? Date()

        return Alarm(
            time: time,
            label: "School Day Alarm",
            isEnabled: true,
            snoozeEnabled: true
        )
    }

    // Available bundled alarm sounds
    enum BundledSound: String, Codable, CaseIterable {
        case funnyRing = "funny_ring"
        case clickRing = "click_ring"
        case kidShouting1 = "kid_shouting_1"
        case kidShouting2 = "kid_shouting_2"

        var displayName: String {
            switch self {
            case .funnyRing: return "Funny Ring"
            case .clickRing: return "Click Ring"
            case .kidShouting1: return "Kid Shouting 1"
            case .kidShouting2: return "Kid Shouting 2"
            }
        }
    }

    // The selected alarm sound (defaults to funny_ring)
    var bundledSound: BundledSound = .funnyRing

    var alarmSoundName: String {
        bundledSound.rawValue
    }
}

// Legacy enum kept for backwards compatibility with saved alarms
enum AlarmSound: String, Codable {
    case radar = "Radar"
    case beacon = "Beacon"
    case chimes = "Chimes"
    case circuit = "Circuit"
    case constellation = "Constellation"
    case cosmic = "Cosmic"
    case crystals = "Crystals"
    case hillside = "Hillside"
    case illuminate = "Illuminate"
    case nightOwl = "Night Owl"
    case opening = "Opening"
    case playtime = "Playtime"
    case presto = "Presto"
    case radiate = "Radiate"
    case ripples = "Ripples"
    case sencha = "Sencha"
    case signal = "Signal"
    case silk = "Silk"
    case slowRise = "Slow Rise"
    case stargaze = "Stargaze"
    case summit = "Summit"
    case twinkle = "Twinkle"
    case uplift = "Uplift"
    case waves = "Waves"
}

class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = []

    private let saveKey = "SavedAlarms"

    init() {
        loadAlarms()
    }

    func loadAlarms() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = decoded
        }
    }

    func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    func addAlarm(_ alarm: Alarm) {
        alarms.append(alarm)
        saveAlarms()
    }

    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()
        }
    }

    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()
        NotificationManager.shared.cancelNotifications(for: alarm)
    }

    func toggleAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].isEnabled.toggle()
            saveAlarms()
        }
    }
}
