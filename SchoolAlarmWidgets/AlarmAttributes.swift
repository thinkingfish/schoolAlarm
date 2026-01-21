import AlarmKit
import ActivityKit

/// Content state for alarm Live Activity
struct SchoolAlarmContentState: AlarmMetadata {
    // No custom state needed - system handles countdown display
}

/// Type alias for our alarm attributes
typealias SchoolAlarmAttributes = AlarmAttributes<SchoolAlarmContentState>
