import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit

/// Minimal Live Activity for AlarmKit
/// Uses EmptyView to let system provide default alarm UI
struct SchoolAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchoolAlarmAttributes.self) { context in
            // Lock Screen presentation - system provides default
            EmptyView()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}
