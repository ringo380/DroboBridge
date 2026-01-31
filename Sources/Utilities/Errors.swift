//
//  Errors.swift
//  DroboBridge
//
//  Error types for DroboBridge operations
//

import Foundation

// MARK: - Device Errors

enum DroboDeviceError: LocalizedError {
    case notificationPortCreationFailed
    case matchingDictionaryCreationFailed
    case notificationRegistrationFailed(kern_return_t)
    case serviceMatchingFailed(kern_return_t)
    case devicePropertyAccessFailed
    case registryTraversalFailed(kern_return_t)
    case diskArbitrationSessionFailed
    case mountOperationFailed(String)
    case unmountOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notificationPortCreationFailed:
            return "Failed to create IOKit notification port"
        case .matchingDictionaryCreationFailed:
            return "Failed to create IOKit matching dictionary"
        case .notificationRegistrationFailed(let code):
            return "Failed to register for IOKit notifications (code: \(code))"
        case .serviceMatchingFailed(let code):
            return "Failed to match IOKit services (code: \(code))"
        case .devicePropertyAccessFailed:
            return "Failed to access device properties"
        case .registryTraversalFailed(let code):
            return "Failed to traverse IOKit registry (code: \(code))"
        case .diskArbitrationSessionFailed:
            return "Failed to create DiskArbitration session"
        case .mountOperationFailed(let reason):
            return "Mount operation failed: \(reason)"
        case .unmountOperationFailed(let reason):
            return "Unmount operation failed: \(reason)"
        }
    }
}

// MARK: - Diagnostics Errors

enum DiagnosticsError: LocalizedError {
    case invalidBSDName(String)
    case diskutilFailed(exitCode: Int)
    case parseError(String)
    case logCollectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidBSDName(let name):
            return "Invalid BSD device name: \(name)"
        case .diskutilFailed(let code):
            return "diskutil command failed with exit code \(code)"
        case .parseError(let message):
            return "Failed to parse output: \(message)"
        case .logCollectionFailed:
            return "Failed to collect system logs"
        }
    }
}

// MARK: - Safety Errors

enum SafetyError: LocalizedError {
    case noCommand
    case forbiddenCommand(String)
    case unknownCommand(String)
    case readWriteNotConfirmed
    case writeNotPermitted(reason: String)

    var errorDescription: String? {
        switch self {
        case .noCommand:
            return "No command specified"
        case .forbiddenCommand(let cmd):
            return "SAFETY: Command '\(cmd)' is forbidden. DroboBridge never modifies disk structure."
        case .unknownCommand(let cmd):
            return "SAFETY: Unknown command '\(cmd)' is not allowed."
        case .readWriteNotConfirmed:
            return "Read-write access was not confirmed by user"
        case .writeNotPermitted(let reason):
            return "SAFETY: Write operation not permitted - \(reason)"
        }
    }
}

// MARK: - Mount Errors

enum MountError: LocalizedError {
    case sessionCreationFailed
    case diskNotFound(bsdName: String)
    case alreadyMounted
    case exclusiveAccess
    case notPermitted
    case notPrivileged
    case unsupportedFilesystem(String?)
    case mountFailed(Int32, String?)
    case unmountFailed(Int32, String?)
    case timeout
    // ext4fuse specific errors
    case ext4FuseNotInstalled
    case ext4FuseMountFailed(String)
    case ext4FuseUnmountFailed(String)
    case linuxFilesystemRequiresFuse(String)
    case mountPointCreationFailed(String)
    case userCancelledAuthentication

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create DiskArbitration session"
        case .diskNotFound(let name):
            return "Disk not found: \(name)"
        case .alreadyMounted:
            return "Volume is already mounted"
        case .exclusiveAccess:
            return "Another application has exclusive access to this disk"
        case .notPermitted:
            return "Mount operation not permitted"
        case .notPrivileged:
            return "Insufficient privileges to mount"
        case .unsupportedFilesystem(let fs):
            return "Unsupported filesystem: \(fs ?? "unknown")"
        case .mountFailed(let code, let message):
            return "Mount failed (\(code)): \(message ?? "Unknown error")"
        case .unmountFailed(let code, let message):
            return "Unmount failed (\(code)): \(message ?? "Unknown error")"
        case .timeout:
            return "Operation timed out"
        case .ext4FuseNotInstalled:
            return "ext4fuse is not installed. Install it to mount Linux filesystems."
        case .ext4FuseMountFailed(let message):
            return "ext4fuse mount failed: \(message)"
        case .ext4FuseUnmountFailed(let message):
            return "ext4fuse unmount failed: \(message)"
        case .linuxFilesystemRequiresFuse(let fsType):
            return "Linux filesystem (\(fsType)) requires ext4fuse to mount on macOS"
        case .mountPointCreationFailed(let path):
            return "Failed to create mount point: \(path)"
        case .userCancelledAuthentication:
            return "Authentication was cancelled by user"
        }
    }

    /// Whether this error indicates a Linux filesystem that could be mounted with ext4fuse
    var requiresExt4Fuse: Bool {
        switch self {
        case .unsupportedFilesystem, .linuxFilesystemRequiresFuse:
            return true
        default:
            return false
        }
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case directoryCreationFailed
    case fileWriteFailed(String)
    case zipCreationFailed
    case noDataToExport

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Failed to create export directory"
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)"
        case .zipCreationFailed:
            return "Failed to create ZIP archive"
        case .noDataToExport:
            return "No diagnostic data available to export"
        }
    }
}
