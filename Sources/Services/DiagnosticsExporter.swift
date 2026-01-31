//
//  DiagnosticsExporter.swift
//  DroboBridge
//
//  Creates diagnostic export bundles (ZIP files)
//

import Foundation
import ZIPFoundation

// MARK: - Diagnostics Exporter

/// Creates timestamped ZIP bundles of diagnostic data
actor DiagnosticsExporter {

    // MARK: - Export Bundle Structure

    struct ExportBundle {
        let manifest: ExportManifest
        let diagnosticsData: DiagnosticsData?
        let rawDiskutilList: String?
        let rawDiskutilInfo: [String: String]
        let logs: [LogEntry]
    }

    struct ExportManifest: Codable {
        let bundleVersion: String
        let appVersion: String
        let appBuild: String
        let exportTimestamp: Date
        let macOSVersion: String
        let macOSBuild: String
        let hardwareModel: String
        let droboModel: String?
        let droboSerial: String?
        let exportReason: String

        static func create(
            droboModel: String? = nil,
            droboSerial: String? = nil,
            exportReason: String = "user_initiated"
        ) -> ExportManifest {
            let processInfo = ProcessInfo.processInfo
            let osVersion = processInfo.operatingSystemVersion

            return ExportManifest(
                bundleVersion: "1.0",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
                exportTimestamp: Date(),
                macOSVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
                macOSBuild: getMacOSBuild(),
                hardwareModel: getHardwareModel(),
                droboModel: droboModel,
                droboSerial: droboSerial,
                exportReason: exportReason
            )
        }
    }

    // MARK: - Export

    /// Export diagnostic data to a ZIP file
    func export(bundle: ExportBundle, to directory: URL) async throws -> URL {
        // Create temp directory for bundle contents
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroboBridge_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Write all components
        try await writeManifest(bundle.manifest, to: tempDir)
        try await writeDeviceInfo(bundle.diagnosticsData?.device, to: tempDir)
        try await writeDiskutilOutputs(bundle, to: tempDir)
        try await writeDiagnostics(bundle.diagnosticsData, to: tempDir)
        try await writeLogs(bundle.logs, to: tempDir)
        try await writeSystemInfo(to: tempDir)

        // Create ZIP filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: bundle.manifest.exportTimestamp)
        let zipFilename = "DroboBridge_Diagnostics_\(timestamp).zip"
        let zipURL = directory.appendingPathComponent(zipFilename)

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        // Create ZIP archive
        try FileManager.default.zipItem(at: tempDir, to: zipURL)

        SafetyGuard.auditLog("Diagnostics exported to: \(zipURL.path)")

        return zipURL
    }

    // MARK: - Write Components

    private func writeManifest(_ manifest: ExportManifest, to directory: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(manifest)
        let url = directory.appendingPathComponent("manifest.json")
        try data.write(to: url)
    }

    private func writeDeviceInfo(_ device: CorrelatedStorageDevice?, to directory: URL) async throws {
        let deviceDir = directory.appendingPathComponent("device")
        try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)

        if let device = device {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let jsonData = try encoder.encode(device)
            try jsonData.write(to: deviceDir.appendingPathComponent("device_info.json"))

            // Write USB device details
            let usbData = try encoder.encode(device.usbDevice)
            try usbData.write(to: deviceDir.appendingPathComponent("usb_device.json"))

            // Write block devices
            let blockData = try encoder.encode(device.blockDevices)
            try blockData.write(to: deviceDir.appendingPathComponent("block_devices.json"))

            // Write volumes
            let volumeData = try encoder.encode(device.volumes)
            try volumeData.write(to: deviceDir.appendingPathComponent("volumes.json"))
        } else {
            let placeholder = "No device connected during export"
            try placeholder.write(to: deviceDir.appendingPathComponent("no_device.txt"), atomically: true, encoding: .utf8)
        }
    }

    private func writeDiskutilOutputs(_ bundle: ExportBundle, to directory: URL) async throws {
        let disksDir = directory.appendingPathComponent("disks")
        try FileManager.default.createDirectory(at: disksDir, withIntermediateDirectories: true)

        // Write raw diskutil list
        if let rawList = bundle.rawDiskutilList {
            try rawList.write(to: disksDir.appendingPathComponent("diskutil_list.txt"), atomically: true, encoding: .utf8)
        }

        // Write raw diskutil info for each disk
        for (bsdName, info) in bundle.rawDiskutilInfo {
            let sanitizedName = bsdName.replacingOccurrences(of: "/", with: "_")
            try info.write(to: disksDir.appendingPathComponent("diskutil_info_\(sanitizedName).txt"), atomically: true, encoding: .utf8)
        }

        // Write parsed diskutil list if available
        if let parsed = bundle.diagnosticsData?.diskutilList {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(parsed)
            try data.write(to: disksDir.appendingPathComponent("diskutil_list_parsed.json"))
        }
    }

    private func writeDiagnostics(_ diagnostics: DiagnosticsData?, to directory: URL) async throws {
        let diagDir = directory.appendingPathComponent("diagnostics")
        try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)

        if let diagnostics = diagnostics {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            // Write issues
            let issuesData = try encoder.encode(diagnostics.issues)
            try issuesData.write(to: diagDir.appendingPathComponent("issues.json"))

            // Write full diagnostics
            let fullData = try encoder.encode(diagnostics)
            try fullData.write(to: diagDir.appendingPathComponent("full_diagnostics.json"))
        }
    }

    private func writeLogs(_ logs: [LogEntry], to directory: URL) async throws {
        let logsDir = directory.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Write as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(logs)
        try jsonData.write(to: logsDir.appendingPathComponent("system_logs.json"))

        // Write as human-readable text
        var textContent = "System Logs Export\n"
        textContent += "==================\n\n"
        for log in logs {
            textContent += "[\(log.timestamp)] \(log.subsystem ?? "unknown"): \(log.message)\n"
        }
        try textContent.write(to: logsDir.appendingPathComponent("system_logs.txt"), atomically: true, encoding: .utf8)
    }

    private func writeSystemInfo(to directory: URL) async throws {
        let systemDir = directory.appendingPathComponent("system")
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)

        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion

        let systemInfo: [String: Any] = [
            "macOSVersion": "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            "macOSBuild": DiagnosticsExporter.getMacOSBuild(),
            "hardwareModel": DiagnosticsExporter.getHardwareModel(),
            "hostname": processInfo.hostName,
            "processorCount": processInfo.processorCount,
            "physicalMemory": processInfo.physicalMemory,
            "systemUptime": processInfo.systemUptime,
            "exportTimestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let data = try JSONSerialization.data(withJSONObject: systemInfo, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: systemDir.appendingPathComponent("system_info.json"))
    }

    // MARK: - Helpers

    private static func getMacOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var version = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &version, &size, nil, 0)
        return String(cString: version)
    }

    private static func getHardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
