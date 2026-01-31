//
//  Ext4FuseController.swift
//  DroboBridge
//
//  Handles mounting Linux filesystems (ext2/3/4) using ext4fuse
//
//  SAFETY: All mounts are read-only
//

import AppKit
import Foundation

// MARK: - FUSE Type Detection

enum FuseType: String, CaseIterable {
    case macfuse = "macFUSE"
    case fuseT = "FUSE-T"
    case none = "Not Installed"

    var description: String {
        switch self {
        case .macfuse:
            return "macFUSE (requires kernel extension)"
        case .fuseT:
            return "FUSE-T (userspace, no kernel extension)"
        case .none:
            return "No FUSE implementation installed"
        }
    }
}

// MARK: - Linux Filesystem Driver Type

enum LinuxFilesystemDriver: String, CaseIterable {
    case paragon = "Paragon extFS"
    case ext4fuse = "ext4fuse"
    case none = "Not Installed"

    var description: String {
        switch self {
        case .paragon:
            return "Paragon extFS (native read-write support)"
        case .ext4fuse:
            return "ext4fuse (read-only via FUSE)"
        case .none:
            return "No Linux filesystem driver installed"
        }
    }

    var supportsReadWrite: Bool {
        self == .paragon
    }
}

// MARK: - Ext4Fuse Controller

/// Handles mounting ext2/3/4 filesystems using ext4fuse
actor Ext4FuseController {

    // MARK: - Properties

    private let mountPointPrefix = "DroboBridge_"
    private var activeMounts: [String: URL] = [:] // bsdName -> mountPoint

    // MARK: - Detection

    /// Check if Paragon extFS is installed (enables native read-write ext3/ext4 support)
    func isParagonAvailable() async -> Bool {
        let paragonPath = "/Library/Filesystems/ufsd_ExtFS.fs"
        return FileManager.default.fileExists(atPath: paragonPath)
    }

    /// Detect the best available Linux filesystem driver
    func detectLinuxFilesystemDriver() async -> LinuxFilesystemDriver {
        if await isParagonAvailable() {
            return .paragon
        }
        if await isExt4FuseAvailable() {
            return .ext4fuse
        }
        return .none
    }

    /// Check if ext4fuse binary is available
    func isExt4FuseAvailable() async -> Bool {
        let paths = [
            "/opt/homebrew/bin/ext4fuse",
            "/usr/local/bin/ext4fuse",
            "/usr/bin/ext4fuse"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        return false
    }

    /// Get the path to ext4fuse binary
    func ext4FusePath() async -> String? {
        let paths = [
            "/opt/homebrew/bin/ext4fuse",
            "/usr/local/bin/ext4fuse",
            "/usr/bin/ext4fuse"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Check if FUSE-T is installed
    func isFuseTAvailable() async -> Bool {
        let fuseTPath = "/Library/Application Support/fuse-t"
        return FileManager.default.fileExists(atPath: fuseTPath)
    }

    /// Check if macFUSE is installed
    func isMacFuseAvailable() async -> Bool {
        let macFusePaths = [
            "/Library/Filesystems/macfuse.fs",
            "/Library/Filesystems/osxfuse.fs"
        ]

        for path in macFusePaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    /// Detect which FUSE implementation is available
    func detectFuseType() async -> FuseType {
        if await isFuseTAvailable() {
            return .fuseT
        }
        if await isMacFuseAvailable() {
            return .macfuse
        }
        return .none
    }

    // MARK: - Filesystem Detection

    /// Check if a partition is likely a Linux filesystem based on diskutil info
    func isLinuxFilesystem(bsdName: String) async -> Bool {
        do {
            let partitionType = try await getPartitionType(bsdName: bsdName)
            let linuxIndicators = ["linux", "ext2", "ext3", "ext4", "xfs", "btrfs", "0x83"]
            return linuxIndicators.contains { partitionType.lowercased().contains($0) }
        } catch {
            return false
        }
    }

    /// Get partition type/content from diskutil
    private func getPartitionType(bsdName: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", bsdName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return "unknown"
        }

        // Check Content field (partition type)
        if let content = plist["Content"] as? String {
            return content
        }

        // Check FilesystemType field
        if let fsType = plist["FilesystemType"] as? String {
            return fsType
        }

        return "unknown"
    }

    // MARK: - Privileged Execution

    /// Result of a privileged command execution
    private struct PrivilegedResult {
        let success: Bool
        let output: String
        let errorMessage: String
    }

    /// Run a shell command with administrator privileges using AppleScript
    /// - Parameter command: The shell command to execute
    /// - Returns: Result containing success status, output, and error message
    /// - Throws: MountError.userCancelledAuthentication if user cancels the auth dialog
    @MainActor
    private func runWithAdminPrivileges(command: String) async throws -> PrivilegedResult {
        // Escape backslashes and double quotes for AppleScript double-quoted string
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        do shell script "\(escapedCommand)" with administrator privileges
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return PrivilegedResult(success: false, output: "", errorMessage: "Failed to create AppleScript")
        }

        let result = appleScript.executeAndReturnError(&error)

        if let error = error {
            // Error code -128 means user cancelled the authentication dialog
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -128 {
                throw MountError.userCancelledAuthentication
            }

            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            return PrivilegedResult(success: false, output: "", errorMessage: errorMessage)
        }

        let output = result.stringValue ?? ""
        return PrivilegedResult(success: true, output: output, errorMessage: "")
    }

    // MARK: - Mount Operations

    /// Mount an ext2/3/4 filesystem using ext4fuse (read-only)
    func mount(bsdName: String, volumeName: String?) async throws -> URL {
        // Check if ext4fuse is available
        guard let ext4fusePath = await ext4FusePath() else {
            throw MountError.ext4FuseNotInstalled
        }

        // Check if FUSE is available
        let fuseType = await detectFuseType()
        guard fuseType != .none else {
            throw MountError.ext4FuseNotInstalled
        }

        // Create mount point path
        let safeName = (volumeName ?? bsdName)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let mountPointName = "\(mountPointPrefix)\(safeName)"
        let mountPoint = URL(fileURLWithPath: "/Volumes/\(mountPointName)")

        // Build device path
        let devicePath = "/dev/\(bsdName)"

        // Build privileged command:
        // 1. Create mount point directory
        // 2. Run ext4fuse with read-only and allow_other options
        let command = "mkdir -p '\(mountPoint.path)' && '\(ext4fusePath)' '\(devicePath)' '\(mountPoint.path)' -o allow_other,ro"

        // Run with admin privileges (will prompt for password)
        let result = try await runWithAdminPrivileges(command: command)

        if !result.success {
            // Clean up mount point on failure (may also need privileges, but try anyway)
            try? FileManager.default.removeItem(at: mountPoint)
            throw MountError.ext4FuseMountFailed(result.errorMessage)
        }

        // Record active mount
        activeMounts[bsdName] = mountPoint

        return mountPoint
    }

    /// Unmount a FUSE-mounted volume
    func unmount(bsdName: String) async throws {
        guard let mountPoint = activeMounts[bsdName] else {
            // Try to find it by checking /Volumes
            throw MountError.diskNotFound(bsdName: bsdName)
        }

        try await unmount(mountPoint: mountPoint)
        activeMounts.removeValue(forKey: bsdName)
    }

    /// Unmount a FUSE-mounted volume by mount point
    func unmount(mountPoint: URL) async throws {
        // Build privileged command:
        // 1. Unmount the volume
        // 2. Remove the mount point directory
        let command = "umount '\(mountPoint.path)' && rmdir '\(mountPoint.path)'"

        // Run with admin privileges (will prompt for password)
        let result = try await runWithAdminPrivileges(command: command)

        if !result.success {
            throw MountError.ext4FuseUnmountFailed(result.errorMessage)
        }

        // Remove from active mounts
        for (key, value) in activeMounts where value == mountPoint {
            activeMounts.removeValue(forKey: key)
        }
    }

    /// Check if a volume is mounted via FUSE (by this controller)
    func isFuseMounted(bsdName: String) -> Bool {
        return activeMounts[bsdName] != nil
    }

    /// Get mount point for a FUSE-mounted volume
    func getMountPoint(bsdName: String) -> URL? {
        return activeMounts[bsdName]
    }

    // MARK: - Installation Guidance

    /// Get instructions for installing ext4fuse
    static var installationInstructions: String {
        """
        To mount ext3/ext4 filesystems on macOS, you need to install ext4fuse.

        Option 1: Homebrew (Free, Read-Only)
        1. Install Homebrew if needed: https://brew.sh
        2. Run: brew install macfuse
        3. Run: brew install gromgit/fuse/ext4fuse-mac
        4. Restart your Mac
        5. On Apple Silicon: Allow kernel extension in System Settings → Privacy & Security

        Option 2: FUSE-T (Free, No Kernel Extension)
        1. Install Homebrew if needed: https://brew.sh
        2. Run: brew install macos-fuse-t/homebrew-cask/fuse-t
        3. Build ext4fuse from: https://github.com/macos-fuse-t/ext4fuse

        Option 3: Paragon extFS ($39, Read-Write)
        Download from: https://www.paragon-software.com/home/extfs-mac/

        For detailed instructions, see:
        https://www.jeffgeerling.com/blog/2024/mounting-ext4-linux-usb-drive-on-macos-2024/
        """
    }

    /// Homebrew installation command
    static var homebrewCommand: String {
        "brew install macfuse && brew install gromgit/fuse/ext4fuse-mac"
    }

    /// Paragon extFS URL
    static var paragonURL: URL {
        URL(string: "https://www.paragon-software.com/home/extfs-mac/")!
    }

    /// Jeff Geerling's guide URL
    static var guideURL: URL {
        URL(string: "https://www.jeffgeerling.com/blog/2024/mounting-ext4-linux-usb-drive-on-macos-2024/")!
    }
}
