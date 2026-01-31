//
//  DiskDiagnostics.swift
//  DroboBridge
//
//  Diagnostics collection using diskutil and system logs
//

import Foundation

// MARK: - Disk Diagnostics Service

/// Collects diagnostic information from disks using diskutil and system logs
actor DiskDiagnosticsService {

    private let diskutilRunner = SafeDiskutilRunner()

    // MARK: - Diskutil Operations

    /// Get all disks
    func listAllDisks() async throws -> DiskutilListOutput {
        let data = try await diskutilRunner.list()
        return try parseDiskutilList(plistData: data)
    }

    /// Get external USB disks
    func listExternalDisks() async throws -> DiskutilListOutput {
        let data = try await diskutilRunner.list(external: true)
        return try parseDiskutilList(plistData: data)
    }

    /// Get info for a specific disk
    func getDiskInfo(bsdName: String) async throws -> DiskutilInfoOutput {
        let data = try await diskutilRunner.info(bsdName: bsdName)
        return try parseDiskutilInfo(plistData: data)
    }

    /// Get raw diskutil list output
    func getRawDiskutilList() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Get raw diskutil info output
    func getRawDiskutilInfo(bsdName: String) async throws -> String {
        // Validate BSD name
        guard isValidBSDName(bsdName) else {
            throw DiagnosticsError.invalidBSDName(bsdName)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", bsdName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Log Collection

    /// Get DiskArbitration related logs
    func getDiskArbitrationLogs(lastMinutes: Int = 30) async throws -> [LogEntry] {
        let predicate = "process == \"diskarbitrationd\" OR subsystem == \"com.apple.DiskArbitration\""
        return try await runLogShow(predicate: predicate, lastMinutes: lastMinutes)
    }

    /// Get USB-related kernel logs
    func getUSBKernelLogs(lastMinutes: Int = 30) async throws -> [LogEntry] {
        let predicate = "sender == \"kernel\" AND eventMessage CONTAINS \"USB\""
        return try await runLogShow(predicate: predicate, lastMinutes: lastMinutes)
    }

    /// Get mount-related error logs
    func getMountErrorLogs(lastMinutes: Int = 30) async throws -> [LogEntry] {
        let predicate = "eventMessage CONTAINS[c] \"mount\" AND (eventMessage CONTAINS[c] \"error\" OR eventMessage CONTAINS[c] \"fail\")"
        return try await runLogShow(predicate: predicate, lastMinutes: lastMinutes)
    }

    /// Get all relevant logs combined
    func getAllRelevantLogs(lastMinutes: Int = 10) async throws -> [LogEntry] {
        var allLogs: [LogEntry] = []

        // Collect logs from different sources
        if let daLogs = try? await getDiskArbitrationLogs(lastMinutes: lastMinutes) {
            allLogs.append(contentsOf: daLogs)
        }

        if let usbLogs = try? await getUSBKernelLogs(lastMinutes: lastMinutes) {
            allLogs.append(contentsOf: usbLogs)
        }

        if let mountLogs = try? await getMountErrorLogs(lastMinutes: lastMinutes) {
            allLogs.append(contentsOf: mountLogs)
        }

        // Sort by timestamp and deduplicate
        return Array(Set(allLogs.map { $0.id }))
            .compactMap { id in allLogs.first { $0.id == id } }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func runLogShow(predicate: String, lastMinutes: Int) async throws -> [LogEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", predicate,
            "--last", "\(lastMinutes)m",
            "--style", "ndjson",
            "--info"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parseLogEntries(ndjsonData: data)
    }

    // MARK: - Diagnosis Analysis

    /// Analyze a correlated device and identify issues
    func diagnose(device: CorrelatedStorageDevice) async -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check visibility state issues
        issues.append(contentsOf: diagnoseVisibilityState(device))

        // Check each volume for filesystem issues
        for volume in device.volumes {
            issues.append(contentsOf: diagnoseVolume(volume))
        }

        // Check for connection issues
        issues.append(contentsOf: await diagnoseConnection(device))

        return issues
    }

    private func diagnoseVisibilityState(_ device: CorrelatedStorageDevice) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        switch device.visibilityState {
        case .usbOnly:
            issues.append(DiagnosticIssue(
                severity: .error,
                category: .connection,
                title: "No Block Device Detected",
                description: device.visibilityState.diagnosticDescription,
                recommendation: device.visibilityState.suggestedActions.joined(separator: "\n"),
                affectedDevice: device.usbDevice.displayName
            ))

        case .blockDeviceOnly:
            issues.append(DiagnosticIssue(
                severity: .warning,
                category: .filesystem,
                title: "No Volumes Detected",
                description: device.visibilityState.diagnosticDescription,
                recommendation: device.visibilityState.suggestedActions.joined(separator: "\n"),
                affectedDevice: device.primaryBlockDevice?.bsdName
            ))

        case .volumesUnmounted:
            issues.append(DiagnosticIssue(
                severity: .info,
                category: .filesystem,
                title: "Volumes Not Mounted",
                description: device.visibilityState.diagnosticDescription,
                recommendation: device.visibilityState.suggestedActions.joined(separator: "\n"),
                affectedDevice: device.primaryBlockDevice?.bsdName
            ))

        case .mounted:
            // No issues for mounted state
            break
        }

        return issues
    }

    private func diagnoseVolume(_ volume: VolumeInfo) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check filesystem type
        if let fsType = volume.filesystemType?.lowercased() {
            // Check for Linux filesystems
            let linuxFilesystems = ["ext2", "ext3", "ext4", "xfs", "btrfs"]
            if linuxFilesystems.contains(where: { fsType.contains($0) }) {
                issues.append(DiagnosticIssue(
                    severity: .error,
                    category: .filesystem,
                    title: "Linux Filesystem Detected",
                    description: "This partition uses a Linux filesystem (\(fsType)) which macOS cannot read natively.",
                    recommendation: "Install ext4fuse (brew install ext4fuse) or Paragon extFS for Mac to access this partition.",
                    affectedDevice: volume.bsdName
                ))
            }

            // Check for NTFS
            if fsType == "ntfs" {
                issues.append(DiagnosticIssue(
                    severity: .warning,
                    category: .filesystem,
                    title: "NTFS Filesystem (Limited Support)",
                    description: "macOS can read NTFS volumes but cannot write to them natively.",
                    recommendation: "For write access, use 'Paragon NTFS for Mac' or 'Tuxera NTFS'. Data can still be read without additional software.",
                    affectedDevice: volume.bsdName
                ))
            }
        } else if !volume.isMounted {
            // No filesystem type detected and not mounted
            issues.append(DiagnosticIssue(
                severity: .warning,
                category: .filesystem,
                title: "Unrecognized Filesystem",
                description: "macOS does not recognize the filesystem on this partition.",
                recommendation: "The volume may use a filesystem that macOS doesn't support (ext4, NTFS, etc.) or the filesystem may be corrupted.",
                affectedDevice: volume.bsdName
            ))
        }

        return issues
    }

    private func diagnoseConnection(_ device: CorrelatedStorageDevice) async -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check recent USB logs for errors
        if let logs = try? await getUSBKernelLogs(lastMinutes: 5) {
            let errorLogs = logs.filter {
                $0.message.lowercased().contains("error") ||
                $0.message.lowercased().contains("failed")
            }

            if !errorLogs.isEmpty {
                issues.append(DiagnosticIssue(
                    severity: .warning,
                    category: .connection,
                    title: "USB Connection Issues Detected",
                    description: "Recent USB errors were found in system logs (\(errorLogs.count) errors).",
                    recommendation: "Try a different USB port or cable. Avoid USB hubs if possible. Ensure the Drobo has adequate power.",
                    affectedDevice: device.usbDevice.displayName
                ))
            }
        }

        // Check USB speed
        if device.usbDevice.speed == .full || device.usbDevice.speed == .low {
            issues.append(DiagnosticIssue(
                severity: .warning,
                category: .connection,
                title: "Slow USB Connection",
                description: "Device is connected at \(device.usbDevice.speed.shortName) speed, which is very slow for storage.",
                recommendation: "Try connecting to a USB 3.0 port for much better performance.",
                affectedDevice: device.usbDevice.displayName
            ))
        }

        return issues
    }

    // MARK: - Parsing

    private func parseDiskutilList(plistData: Data) throws -> DiskutilListOutput {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw DiagnosticsError.parseError("Invalid diskutil list plist structure")
        }

        let allDisks = plist["AllDisks"] as? [String] ?? []
        let wholeDisks = plist["WholeDisks"] as? [String] ?? []
        let volumesFromDisks = plist["VolumesFromDisks"] as? [String] ?? []

        var diskEntries: [DiskEntry] = []
        if let disksAndPartitions = plist["AllDisksAndPartitions"] as? [[String: Any]] {
            for diskDict in disksAndPartitions {
                guard let deviceId = diskDict["DeviceIdentifier"] as? String else { continue }

                var partitionEntries: [PartitionEntry] = []
                if let partitions = diskDict["Partitions"] as? [[String: Any]] {
                    for partDict in partitions {
                        guard let partId = partDict["DeviceIdentifier"] as? String else { continue }
                        partitionEntries.append(PartitionEntry(
                            deviceIdentifier: partId,
                            content: partDict["Content"] as? String,
                            size: (partDict["Size"] as? NSNumber)?.uint64Value ?? 0,
                            volumeName: partDict["VolumeName"] as? String
                        ))
                    }
                }

                diskEntries.append(DiskEntry(
                    deviceIdentifier: deviceId,
                    content: diskDict["Content"] as? String,
                    size: (diskDict["Size"] as? NSNumber)?.uint64Value ?? 0,
                    partitions: partitionEntries
                ))
            }
        }

        return DiskutilListOutput(
            allDisks: allDisks,
            wholeDisks: wholeDisks,
            volumesFromDisks: volumesFromDisks,
            disksAndPartitions: diskEntries
        )
    }

    private func parseDiskutilInfo(plistData: Data) throws -> DiskutilInfoOutput {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw DiagnosticsError.parseError("Invalid diskutil info plist structure")
        }

        guard let deviceId = plist["DeviceIdentifier"] as? String else {
            throw DiagnosticsError.parseError("Missing DeviceIdentifier")
        }

        return DiskutilInfoOutput(
            deviceIdentifier: deviceId,
            deviceNode: plist["DeviceNode"] as? String ?? "/dev/\(deviceId)",
            busProtocol: plist["BusProtocol"] as? String,
            content: plist["Content"] as? String,
            filesystemType: plist["FilesystemType"] as? String,
            filesystemName: plist["FilesystemName"] as? String,
            volumeName: plist["VolumeName"] as? String,
            volumeUUID: plist["VolumeUUID"] as? String,
            mountPoint: plist["MountPoint"] as? String,
            size: (plist["Size"] as? NSNumber)?.uint64Value ?? 0,
            isWholeDisk: plist["WholeDisk"] as? Bool ?? false,
            isMountable: plist["VolumeMountable"] as? Bool ?? false,
            isWritable: plist["Writable"] as? Bool ?? true,
            isInternal: plist["Internal"] as? Bool ?? false,
            isEjectable: plist["Ejectable"] as? Bool ?? true,
            isRemovable: plist["Removable"] as? Bool ?? true,
            smartStatus: plist["SMARTStatus"] as? String,
            mediaName: plist["MediaName"] as? String,
            vendorName: plist["DeviceVendor"] as? String,
            modelName: plist["DeviceModel"] as? String
        )
    }

    private func parseLogEntries(ndjsonData: Data) -> [LogEntry] {
        guard let string = String(data: ndjsonData, encoding: .utf8) else {
            return []
        }

        let lines = string.components(separatedBy: .newlines)
        var entries: [LogEntry] = []

        for line in lines where !line.isEmpty {
            if let lineData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let timestamp = json["timestamp"] as? String,
               let message = json["eventMessage"] as? String {
                entries.append(LogEntry(
                    timestamp: timestamp,
                    processImagePath: json["processImagePath"] as? String,
                    senderImagePath: json["senderImagePath"] as? String,
                    subsystem: json["subsystem"] as? String,
                    category: json["category"] as? String,
                    eventMessage: message
                ))
            }
        }

        return entries
    }

    private func isValidBSDName(_ name: String) -> Bool {
        let pattern = #"^disk\d+(?:s\d+)*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
