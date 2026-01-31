//
//  CorrelatedStorageDevice.swift
//  DroboBridge
//
//  Links USB devices to their storage devices and volumes
//

import Foundation

// MARK: - Correlated Storage Device

/// Correlates a USB device with its storage devices and volumes
struct CorrelatedStorageDevice: Identifiable, Codable {
    let id: UUID
    let usbDevice: USBDevice
    var blockDevices: [BlockDevice]
    var volumes: [VolumeInfo]
    var visibilityState: StorageVisibilityState

    /// Primary whole-disk block device (e.g., disk4, not disk4s1)
    var primaryBlockDevice: BlockDevice? {
        blockDevices.first { $0.isWhole }
    }

    /// All partition block devices
    var partitionBlockDevices: [BlockDevice] {
        blockDevices.filter { !$0.isWhole }
    }

    /// Mounted volumes only
    var mountedVolumes: [VolumeInfo] {
        volumes.filter { $0.isMounted }
    }

    /// Unmounted volumes only
    var unmountedVolumes: [VolumeInfo] {
        volumes.filter { !$0.isMounted }
    }

    /// Total storage capacity
    var totalCapacity: UInt64 {
        primaryBlockDevice?.size ?? blockDevices.first?.size ?? 0
    }

    /// Available free space (sum of mounted volumes)
    var totalFreeSpace: UInt64? {
        let spaces = mountedVolumes.compactMap { $0.freeSpace }
        return spaces.isEmpty ? nil : spaces.reduce(0, +)
    }

    /// Display name for the device
    var displayName: String {
        if usbDevice.isDrobo {
            if let modelName = DroboIdentifier.modelName(
                vendorID: usbDevice.vendorID,
                productID: usbDevice.productID
            ) {
                return modelName
            }
            return "Drobo"
        }
        return usbDevice.displayName
    }

    /// Whether any volumes can be mounted
    var hasMountableVolumes: Bool {
        !unmountedVolumes.isEmpty
    }

    /// Whether all volumes are mounted
    var allVolumesMounted: Bool {
        !volumes.isEmpty && unmountedVolumes.isEmpty
    }

    init(
        id: UUID = UUID(),
        usbDevice: USBDevice,
        blockDevices: [BlockDevice] = [],
        volumes: [VolumeInfo] = [],
        visibilityState: StorageVisibilityState = .usbOnly
    ) {
        self.id = id
        self.usbDevice = usbDevice
        self.blockDevices = blockDevices
        self.volumes = volumes
        self.visibilityState = visibilityState
    }

    /// Create a copy with updated volumes
    func withUpdatedVolumes(_ newVolumes: [VolumeInfo]) -> CorrelatedStorageDevice {
        var copy = self
        copy.volumes = newVolumes
        copy.visibilityState = Self.determineState(
            blockDevices: copy.blockDevices,
            volumes: newVolumes
        )
        return copy
    }

    /// Create a copy with updated block devices
    func withUpdatedBlockDevices(_ newBlockDevices: [BlockDevice]) -> CorrelatedStorageDevice {
        var copy = self
        copy.blockDevices = newBlockDevices
        copy.visibilityState = Self.determineState(
            blockDevices: newBlockDevices,
            volumes: copy.volumes
        )
        return copy
    }

    /// Determine visibility state from block devices and volumes
    static func determineState(
        blockDevices: [BlockDevice],
        volumes: [VolumeInfo]
    ) -> StorageVisibilityState {
        // State A: No block devices
        if blockDevices.isEmpty {
            return .usbOnly
        }

        // State B: Block devices visible, no volumes (partitions)
        if volumes.isEmpty {
            return .blockDeviceOnly
        }

        // State C: Volumes exist but none mounted
        let mountedCount = volumes.filter { $0.isMounted }.count
        if mountedCount == 0 {
            return .volumesUnmounted
        }

        // State D: At least one volume mounted
        return .mounted
    }
}

// MARK: - Connection Status

/// Overall connection status for the app
enum ConnectionStatus: Equatable {
    case disconnected
    case searching
    case connected(deviceCount: Int)
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected:
            return "No Drobo Connected"
        case .searching:
            return "Searching for Drobo..."
        case .connected(let count):
            return count == 1 ? "1 Drobo Connected" : "\(count) Drobos Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:
            return "cable.connector.slash"
        case .searching:
            return "arrow.clockwise"
        case .connected:
            return "cable.connector"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
