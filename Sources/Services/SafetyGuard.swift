//
//  SafetyGuard.swift
//  DroboBridge
//
//  Safety validation to prevent destructive operations
//
//  CRITICAL: This module enforces the safety principle that DroboBridge
//  NEVER formats, erases, or initializes disks. All operations must be
//  read-only by default.
//

import Foundation

// MARK: - Safety Guard

/// Enforces safety restrictions on disk operations
enum SafetyGuard {

    // MARK: - Forbidden Commands

    /// Commands that are NEVER allowed - these modify disk structure
    static let forbiddenCommands: Set<String> = [
        "eraseDisk",        // Formats entire disk
        "eraseVolume",      // Formats volume
        "partitionDisk",    // Repartitions disk
        "addPartition",     // Modifies partition table
        "deletePartition",  // Removes partition
        "mergePartitions",  // Merges partitions
        "splitPartition",   // Splits partition
        "resizeVolume",     // Resizes volume
        "secureErase",      // Secure erase
        "zeroDisk",         // Writes zeros
        "randomDisk",       // Writes random data
        "enableJournal",    // Modifies filesystem
        "disableJournal",   // Modifies filesystem
        "repairVolume",     // May modify data (user should use Disk Utility directly)
        "apfs",             // APFS container manipulation
        "coreStorage",      // CoreStorage manipulation
        "rename",           // Volume rename (could be enabled if needed)
    ]

    // MARK: - Allowed Commands

    /// Commands that are safe (read-only or user-controlled)
    static let allowedCommands: Set<String> = [
        "list",             // List disks
        "info",             // Get disk info
        "verifyDisk",       // Verify (read-only)
        "verifyVolume",     // Verify (read-only)
        "mount",            // Mount (with safety checks)
        "mountDisk",        // Mount all volumes
        "unmount",          // Unmount
        "unmountDisk",      // Unmount all
        "eject",            // Eject
        "activity",         // Monitor activity
        "listFilesystems",  // List filesystem types
    ]

    // MARK: - Validation

    /// Validate that a diskutil command is safe to execute
    /// - Parameter args: Command arguments (first element is the subcommand)
    /// - Throws: SafetyError if command is forbidden or unknown
    static func validateDiskutilCommand(_ args: [String]) throws {
        guard let command = args.first else {
            throw SafetyError.noCommand
        }

        if forbiddenCommands.contains(command) {
            throw SafetyError.forbiddenCommand(command)
        }

        if !allowedCommands.contains(command) {
            throw SafetyError.unknownCommand(command)
        }
    }

    /// Check if a diskutil command is safe without throwing
    static func isCommandSafe(_ args: [String]) -> Bool {
        do {
            try validateDiskutilCommand(args)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Mount Safety

    /// Default mount options - always prefer read-only
    static let defaultMountReadOnly = true

    /// Validate mount operation safety
    static func validateMountOperation(readOnly: Bool, userConfirmed: Bool) throws {
        // Read-write mounts require explicit user confirmation
        if !readOnly && !userConfirmed {
            throw SafetyError.readWriteNotConfirmed
        }
    }

    // MARK: - Write Operation Safety

    /// Validate that a write operation is allowed on the given volume
    /// - Parameters:
    ///   - volume: The volume to check
    ///   - operation: Description of the operation for logging
    /// - Throws: SafetyError if write operations are not permitted
    static func validateWriteOperation(volume: VolumeInfo, operation: String) throws {
        guard volume.isMounted else {
            throw SafetyError.writeNotPermitted(reason: "Volume is not mounted")
        }
        guard volume.isReadWrite else {
            throw SafetyError.writeNotPermitted(reason: "Volume is mounted read-only")
        }
        auditLog("Write operation '\(operation)' permitted on \(volume.bsdName)")
    }

    /// Check if write operations are allowed on a volume without throwing
    static func canWrite(to volume: VolumeInfo) -> Bool {
        return volume.isMounted && volume.isReadWrite
    }

    // MARK: - Safety Messages

    /// Warning message for "Initialize Disk" dialog
    static let initializeDiskWarning = """
        WARNING: Do Not Initialize

        If macOS is showing an "Initialize Disk" dialog, click "Ignore" or "Eject".

        Clicking "Initialize" will PERMANENTLY ERASE all data on your Drobo.

        This warning appears because macOS does not recognize the filesystem.
        This is normal for drives formatted with Linux filesystems (ext4) or
        certain configurations.
        """

    /// Safety banner text for the app
    static let safetyBanner = """
        DroboBridge protects your data. It will NEVER:
        • Format or erase your disk
        • Modify the partition table
        • Initialize or reinitialize the device

        Mount operations default to read-only mode.
        Read-write mounting is available with Paragon extFS.
        """

    // MARK: - Safety Audit

    /// Log a safety-relevant operation for audit purposes
    static func auditLog(_ message: String, level: AuditLevel = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let prefix = "[\(timestamp)] [SAFETY-\(level.rawValue.uppercased())]"
        print("\(prefix) \(message)")

        // In a production app, this would write to a secure audit log
    }

    enum AuditLevel: String {
        case info
        case warning
        case blocked
    }
}

// MARK: - Safe Diskutil Runner

/// A wrapper that ensures only safe diskutil commands can be executed
actor SafeDiskutilRunner {

    /// Run a diskutil command safely
    /// - Parameters:
    ///   - arguments: Command arguments
    ///   - timeout: Command timeout in seconds
    /// - Returns: Command output data
    /// - Throws: SafetyError if command is forbidden, or other errors
    func run(arguments: [String], timeout: TimeInterval = 30) async throws -> Data {
        // Validate command safety FIRST
        try SafetyGuard.validateDiskutilCommand(arguments)

        // Log the operation
        SafetyGuard.auditLog("Executing: diskutil \(arguments.joined(separator: " "))")

        // Execute the command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DiagnosticsError.diskutilFailed(exitCode: Int(process.terminationStatus))
        }

        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    /// Run diskutil list safely
    func list(external: Bool = false) async throws -> Data {
        var args = ["list", "-plist"]
        if external {
            args.append("external")
        }
        return try await run(arguments: args)
    }

    /// Run diskutil info safely
    func info(bsdName: String) async throws -> Data {
        // Validate BSD name to prevent injection
        guard isValidBSDName(bsdName) else {
            throw DiagnosticsError.invalidBSDName(bsdName)
        }
        return try await run(arguments: ["info", "-plist", bsdName])
    }

    /// Validate BSD device name format
    private func isValidBSDName(_ name: String) -> Bool {
        // Strict validation: only allow disk[0-9]+[s0-9]*
        let pattern = #"^disk\d+(?:s\d+)*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
