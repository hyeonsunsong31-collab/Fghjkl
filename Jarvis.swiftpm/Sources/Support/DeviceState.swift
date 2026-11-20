import Foundation
import UIKit

/// Reads the device "body" state that the hypothalamus regulates against.
@MainActor
enum DeviceState {
    static func body() -> BodyState {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel < 0 ? 1 : device.batteryLevel
        let charging = device.batteryState == .charging || device.batteryState == .full
        let thermal: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = 0
        case .fair: thermal = 1
        case .serious: thermal = 2
        case .critical: thermal = 3
        @unknown default: thermal = 1
        }
        return BodyState(batteryLevel: level, isCharging: charging, thermalState: thermal,
                         lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    static var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }
}
