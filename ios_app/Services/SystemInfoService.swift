// Services/SystemInfoService.swift
// Collects iPhone system specifications using native Apple APIs.

import UIKit
import Foundation

struct SystemSpec: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let category: String
}

final class SystemInfoService {

    static func collect() -> [SystemSpec] {
        var specs: [SystemSpec] = []

        // ── Device ───────────────────────────────────────────────────────────
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        specs += [
            SystemSpec(label: "Name",           value: device.name,               category: "Device"),
            SystemSpec(label: "Model",          value: device.model,              category: "Device"),
            SystemSpec(label: "Identifier",     value: machineIdentifier(),       category: "Device"),
            SystemSpec(label: "System",         value: device.systemName,         category: "Device"),
            SystemSpec(label: "System Version", value: device.systemVersion,      category: "Device"),
            SystemSpec(label: "Idiom",          value: idiomName(device.userInterfaceIdiom), category: "Device"),
        ]

        // ── Display ───────────────────────────────────────────────────────────
        let screen = UIScreen.main
        let bounds = screen.bounds
        let native = screen.nativeBounds
        specs += [
            SystemSpec(label: "Points",         value: "\(Int(bounds.width)) × \(Int(bounds.height)) pt",   category: "Display"),
            SystemSpec(label: "Native Pixels",  value: "\(Int(native.width)) × \(Int(native.height)) px",  category: "Display"),
            SystemSpec(label: "Scale",          value: "\(screen.scale)×",                                  category: "Display"),
            SystemSpec(label: "Brightness",     value: String(format: "%.0f%%", screen.brightness * 100),  category: "Display"),
        ]

        // ── Processor & Memory ────────────────────────────────────────────────
        let info = ProcessInfo.processInfo
        specs += [
            SystemSpec(label: "CPU Cores",      value: "\(info.processorCount) (\(info.activeProcessorCount) active)", category: "Processor & Memory"),
            SystemSpec(label: "Physical RAM",   value: formatBytes(Int64(info.physicalMemory)),   category: "Processor & Memory"),
            SystemSpec(label: "Thermal State",  value: thermalStateName(info.thermalState),       category: "Processor & Memory"),
            SystemSpec(label: "Low Power Mode", value: info.isLowPowerModeEnabled ? "On" : "Off", category: "Processor & Memory"),
        ]

        // ── Storage ───────────────────────────────────────────────────────────
        let (total, available) = diskSpace()
        let used = total > 0 ? total - available : 0
        specs += [
            SystemSpec(label: "Total Storage",  value: formatBytes(total),        category: "Storage"),
            SystemSpec(label: "Used Storage",   value: formatBytes(used),         category: "Storage"),
            SystemSpec(label: "Free Storage",   value: formatBytes(available),    category: "Storage"),
        ]

        // ── Battery ───────────────────────────────────────────────────────────
        let batteryLevel = device.batteryLevel
        let batteryStr = batteryLevel < 0 ? "Unknown" : String(format: "%.0f%%", batteryLevel * 100)
        specs += [
            SystemSpec(label: "Battery Level",  value: batteryStr,                            category: "Battery"),
            SystemSpec(label: "Battery State",  value: batteryStateName(device.batteryState), category: "Battery"),
        ]

        // ── Software ─────────────────────────────────────────────────────────
        specs += [
            SystemSpec(label: "OS Name",        value: info.operatingSystemVersionString,      category: "Software"),
            SystemSpec(label: "Hostname",       value: info.hostName,                          category: "Software"),
            SystemSpec(label: "Multitasking",   value: device.isMultitaskingSupported ? "Supported" : "Not supported", category: "Software"),
        ]

        return specs
    }

    // MARK: - Helpers

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { ptr in
            let bytes = ptr.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
    }

    private static func diskSpace() -> (total: Int64, available: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else {
            return (0, 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let avail = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (total, avail)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes) B"
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private static func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:    return "Unknown"
        case .unplugged:  return "Unplugged"
        case .charging:   return "Charging"
        case .full:       return "Full"
        @unknown default: return "Unknown"
        }
    }

    private static func idiomName(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone:   return "iPhone"
        case .pad:     return "iPad"
        case .mac:     return "Mac"
        case .tv:      return "Apple TV"
        case .vision:  return "Apple Vision"
        default:       return "Unknown"
        }
    }
}
