import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit

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
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
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
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date())
    }
}
