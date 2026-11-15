import Foundation
import UIKit

enum SpatialPerformanceBudget {
    /// Targets, not measured device performance. Rendering quality is throttled
    /// before optional inference to preserve battery and interaction latency.
    static var targetFPS: Int {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 30 }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return min(UIScreen.main.maximumFramesPerSecond, 60)
        case .fair:
            return 30
        case .serious, .critical:
            return 20
        @unknown default:
            return 30
        }
    }

    static var allowOptionalInference: Bool {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair: return true
        case .serious, .critical: return false
        @unknown default: return false
        }
    }
}
