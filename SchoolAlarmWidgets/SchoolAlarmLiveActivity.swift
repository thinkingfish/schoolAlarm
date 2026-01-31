import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit

// MARK: - Cached Formatters (avoid allocation during render)

private enum WidgetFormatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()
}

/// Alarm alert view shown on lock screen when alarm fires
struct AlarmAlertView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text("School Day Alarm")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(formattedTime())
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white)
            }
            .padding()
        }
    }

    private func formattedTime() -> String {
        WidgetFormatters.time.string(from: Date())
    }
}

/// Live Activity for AlarmKit alarm display
struct SchoolAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchoolAlarmAttributes.self) { context in
            // Lock Screen presentation - show alarm content
            AlarmAlertView()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formattedCompactTime())
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("School Day Alarm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text(formattedCompactTime())
                    .fontWeight(.semibold)
            } minimal: {
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    private func formattedCompactTime() -> String {
        WidgetFormatters.timeShort.string(from: Date())
    }
}
