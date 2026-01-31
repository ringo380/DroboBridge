//
//  DiagnosticModels.swift
//  DroboBridge
//
//  Models for diagnostic data and results
//

import Foundation

// MARK: - Diagnostic Data

/// Complete diagnostic data collected for a device
struct DiagnosticsData: Codable {
    let timestamp: Date
    let device: CorrelatedStorageDevice?
    let diskutilList: DiskutilListOutput?
    let diskutilInfo: [String: DiskutilInfoOutput] // Keyed by BSD name
    let systemLogs: [LogEntry]
    let issues: [DiagnosticIssue]

    var rawDiskutilListOutput: String?
    var rawDiskutilInfoOutputs: [String: String] // Keyed by BSD name

    init(
        timestamp: Date = Date(),
        device: CorrelatedStorageDevice? = nil,
        diskutilList: DiskutilListOutput? = nil,
        diskutilInfo: [String: DiskutilInfoOutput] = [:],
        systemLogs: [LogEntry] = [],
        issues: [DiagnosticIssue] = [],
        rawDiskutilListOutput: String? = nil,
        rawDiskutilInfoOutputs: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.device = device
        self.diskutilList = diskutilList
        self.diskutilInfo = diskutilInfo
        self.systemLogs = systemLogs
        self.issues = issues
        self.rawDiskutilListOutput = rawDiskutilListOutput
        self.rawDiskutilInfoOutputs = rawDiskutilInfoOutputs
    }

    var hasCriticalIssues: Bool {
        issues.contains { $0.severity == .critical }
    }

    var hasErrors: Bool {
        issues.contains { $0.severity >= .error }
    }

    var hasWarnings: Bool {
        issues.contains { $0.severity >= .warning }
    }

    var highestSeverity: DiagnosticSeverity {
        issues.map { $0.severity }.max() ?? .success
    }
}

// MARK: - Diagnostic Issue

/// A single diagnostic finding/issue
struct DiagnosticIssue: Identifiable, Codable {
    let id: UUID
    let severity: DiagnosticSeverity
    let category: IssueCategory
    let title: String
    let description: String
    let recommendation: String
    let affectedDevice: String? // BSD name or USB device identifier
    let timestamp: Date

    init(
        id: UUID = UUID(),
        severity: DiagnosticSeverity,
        category: IssueCategory,
        title: String,
        description: String,
        recommendation: String,
        affectedDevice: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.description = description
        self.recommendation = recommendation
        self.affectedDevice = affectedDevice
        self.timestamp = timestamp
    }
}

enum IssueCategory: String, Codable, CaseIterable {
    case filesystem = "Filesystem"
    case connection = "Connection"
    case hardware = "Hardware"
    case permissions = "Permissions"
    case configuration = "Configuration"

    var systemImage: String {
        switch self {
        case .filesystem: return "doc.badge.gearshape"
        case .connection: return "cable.connector"
        case .hardware: return "memorychip"
        case .permissions: return "lock.shield"
        case .configuration: return "gearshape.2"
        }
    }
}

// MARK: - Diagnostic Result

/// Result of a diagnostic run for a specific disk
struct DiagnosticResult: Codable {
    let disk: PhysicalDisk
    let issues: [DiagnosticIssue]
    let timestamp: Date

    var hasCriticalIssues: Bool {
        issues.contains { $0.severity == .critical }
    }
}

// MARK: - Diskutil Output Models

/// Parsed output from `diskutil list`
struct DiskutilListOutput: Codable {
    let allDisks: [String]
    let wholeDisks: [String]
    let volumesFromDisks: [String]
    let disksAndPartitions: [DiskEntry]
}

struct DiskEntry: Codable, Identifiable {
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    let content: String?
    let size: UInt64
    let partitions: [PartitionEntry]
}

struct PartitionEntry: Codable, Identifiable {
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    let content: String?
    let size: UInt64
    let volumeName: String?
}

/// Parsed output from `diskutil info`
struct DiskutilInfoOutput: Codable {
    let deviceIdentifier: String
    let deviceNode: String
    let busProtocol: String?
    let content: String?
    let filesystemType: String?
    let filesystemName: String?
    let volumeName: String?
    let volumeUUID: String?
    let mountPoint: String?
    let size: UInt64
    let isWholeDisk: Bool
    let isMountable: Bool
    let isWritable: Bool
    let isInternal: Bool
    let isEjectable: Bool
    let isRemovable: Bool
    let smartStatus: String?
    let mediaName: String?
    let vendorName: String?
    let modelName: String?
}

// MARK: - Log Entry

/// A system log entry
struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: String
    let processImagePath: String?
    let senderImagePath: String?
    let subsystem: String?
    let category: String?
    let eventMessage: String

    var message: String { eventMessage }

    var formattedTimestamp: String {
        // Parse and reformat the timestamp for display
        timestamp
    }

    init(
        id: UUID = UUID(),
        timestamp: String,
        processImagePath: String? = nil,
        senderImagePath: String? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        eventMessage: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.processImagePath = processImagePath
        self.senderImagePath = senderImagePath
        self.subsystem = subsystem
        self.category = category
        self.eventMessage = eventMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case processImagePath
        case senderImagePath
        case subsystem
        case category
        case eventMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.processImagePath = try container.decodeIfPresent(String.self, forKey: .processImagePath)
        self.senderImagePath = try container.decodeIfPresent(String.self, forKey: .senderImagePath)
        self.subsystem = try container.decodeIfPresent(String.self, forKey: .subsystem)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.eventMessage = try container.decode(String.self, forKey: .eventMessage)
    }
}

// MARK: - Mount Attempt

/// Record of a mount attempt
struct MountAttempt: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let bsdName: String
    let volumeName: String?
    let action: MountAction
    let result: MountAttemptResult
    let readOnly: Bool

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        bsdName: String,
        volumeName: String?,
        action: MountAction,
        result: MountAttemptResult,
        readOnly: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bsdName = bsdName
        self.volumeName = volumeName
        self.action = action
        self.result = result
        self.readOnly = readOnly
    }
}

enum MountAction: String, Codable {
    case mount = "Mount"
    case unmount = "Unmount"
}

enum MountAttemptResult: Codable, Equatable {
    case success(mountPoint: String?)
    case failure(error: String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var displayText: String {
        switch self {
        case .success(let mountPoint):
            if let path = mountPoint {
                return "Success: \(path)"
            }
            return "Success"
        case .failure(let error):
            return "Failed: \(error)"
        }
    }
}

// MARK: - Warning

/// A warning to display to the user
struct DroboWarning: Identifiable, Codable {
    let id: UUID
    let severity: DiagnosticSeverity
    let title: String
    let message: String
    let actionLabel: String?
    let actionIdentifier: String?
    let timestamp: Date
    var isDismissed: Bool

    init(
        id: UUID = UUID(),
        severity: DiagnosticSeverity,
        title: String,
        message: String,
        actionLabel: String? = nil,
        actionIdentifier: String? = nil,
        timestamp: Date = Date(),
        isDismissed: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.actionIdentifier = actionIdentifier
        self.timestamp = timestamp
        self.isDismissed = isDismissed
    }

    /// Create the "Initialize Disk" warning
    static var initializeDiskWarning: DroboWarning {
        DroboWarning(
            severity: .critical,
            title: "Do Not Initialize Disk",
            message: "If macOS shows an 'Initialize Disk' dialog, click 'Ignore' or 'Eject'. " +
                     "Clicking 'Initialize' will PERMANENTLY ERASE all data on your Drobo.",
            actionLabel: nil,
            actionIdentifier: nil
        )
    }
}
