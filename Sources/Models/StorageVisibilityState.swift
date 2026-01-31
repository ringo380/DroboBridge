//
//  StorageVisibilityState.swift
//  DroboBridge
//
//  Storage visibility state machine for diagnostic status
//

import Foundation
import SwiftUI

// MARK: - Storage Visibility State

/// Represents the visibility state of a USB storage device
enum StorageVisibilityState: Int, Comparable, CaseIterable, Codable {
    /// USB device detected but no block storage device visible
    case usbOnly = 0

    /// Block storage device visible but no partition/volume information
    case blockDeviceOnly = 1

    /// Volumes detected but not mounted
    case volumesUnmounted = 2

    /// At least one volume is mounted successfully
    case mounted = 3

    static func < (lhs: StorageVisibilityState, rhs: StorageVisibilityState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .usbOnly:
            return "USB Device Only"
        case .blockDeviceOnly:
            return "Block Device (No Volumes)"
        case .volumesUnmounted:
            return "Volumes Unmounted"
        case .mounted:
            return "Mounted"
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .usbOnly:
            return "USB device is detected but no storage driver has attached. " +
                   "This may indicate a driver issue, USB connection problem, or the Drobo is still initializing."
        case .blockDeviceOnly:
            return "Block storage device is visible but no partition table or volumes detected. " +
                   "The disk may need to be initialized, has a corrupted partition table, or uses an unsupported format."
        case .volumesUnmounted:
            return "Volumes are detected but not mounted. " +
                   "The filesystem may be unsupported (ext4, NTFS), corrupted, or manually unmounted."
        case .mounted:
            return "Device is fully operational with mounted volumes."
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .usbOnly: return .error
        case .blockDeviceOnly: return .warning
        case .volumesUnmounted: return .info
        case .mounted: return .success
        }
    }

    var systemImage: String {
        switch self {
        case .usbOnly: return "cable.connector.slash"
        case .blockDeviceOnly: return "externaldrive.badge.questionmark"
        case .volumesUnmounted: return "externaldrive.badge.xmark"
        case .mounted: return "externaldrive.fill.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .usbOnly: return .red
        case .blockDeviceOnly: return .orange
        case .volumesUnmounted: return .yellow
        case .mounted: return .green
        }
    }

    var possibleCauses: [String] {
        switch self {
        case .usbOnly:
            return [
                "Drobo firmware may be initializing",
                "Storage controller driver not loaded",
                "USB cable or port issue",
                "Drobo in standby mode",
                "Power supply issue"
            ]
        case .blockDeviceOnly:
            return [
                "Disk not initialized/formatted",
                "Partition table corrupted",
                "Drobo rebuilding or repairing",
                "Unsupported partition scheme"
            ]
        case .volumesUnmounted:
            return [
                "Volumes were manually unmounted",
                "Filesystem type not supported by macOS",
                "Filesystem needs repair",
                "Volume encryption locked"
            ]
        case .mounted:
            return []
        }
    }

    var suggestedActions: [String] {
        switch self {
        case .usbOnly:
            return [
                "Wait 30-60 seconds for Drobo to fully initialize",
                "Check Drobo status LEDs",
                "Try a different USB port or cable",
                "Power cycle the Drobo",
                "Check if Drobo Dashboard recognizes the device"
            ]
        case .blockDeviceOnly:
            return [
                "Check Drobo Dashboard for status",
                "Wait for any rebuild operations to complete",
                "Use Disk Utility to verify/repair disk",
                "Check system logs for disk errors"
            ]
        case .volumesUnmounted:
            return [
                "Click 'Mount' to attempt mounting",
                "Run First Aid in Disk Utility",
                "Check if volume is encrypted (FileVault)",
                "For Linux filesystems, install ext4fuse or Paragon extFS"
            ]
        case .mounted:
            return [
                "Device is healthy and operational"
            ]
        }
    }
}

// MARK: - Diagnostic Severity

enum DiagnosticSeverity: Int, Comparable, Codable {
    case success = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .warning: return .yellow
        case .error: return .orange
        case .critical: return .red
        }
    }
}
