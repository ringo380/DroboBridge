//
//  DiskCorrelator.swift
//  DroboBridge
//
//  Correlates USB devices with block storage devices and volumes
//

import Foundation
import IOKit
import DiskArbitration
import Combine

// MARK: - Disk Correlator

/// Correlates USB devices with their associated storage devices and volumes
@MainActor
final class DiskCorrelator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var correlatedDevices: [CorrelatedStorageDevice] = []
    @Published private(set) var lastError: DroboDeviceError?

    // MARK: - Combine Publishers

    let stateChangedPublisher = PassthroughSubject<CorrelatedStorageDevice, Never>()

    // MARK: - Private Properties

    private var daSession: DASession?
    private let sessionQueue = DispatchQueue(
        label: "com.drobobridge.diskarbitration",
        qos: .userInitiated
    )

    // Map of USB device registry entry ID to correlated storage
    private var correlationMap: [UInt64: CorrelatedStorageDevice] = [:]

    // MARK: - Initialization

    init() {}

    deinit {
        // Cleanup is handled by stopMonitoring()
    }

    // MARK: - Public API

    /// Start monitoring disk events
    func startMonitoring() throws {
        guard daSession == nil else { return }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw DroboDeviceError.diskArbitrationSessionFailed
        }
        daSession = session

        // Schedule session with dispatch queue
        DASessionSetDispatchQueue(session, sessionQueue)

        // Register for disk events
        registerDiskCallbacks(session)
    }

    /// Stop monitoring disk events
    func stopMonitoring() {
        if let session = daSession {
            DASessionSetDispatchQueue(session, nil)
            daSession = nil
        }
    }

    /// Correlate a USB device with its storage devices
    func correlateDevice(_ usbDevice: USBDevice) async -> CorrelatedStorageDevice {
        // Find IOMedia children of this USB device
        let blockDevices = await findBlockDevicesForUSB(locationID: usbDevice.locationID)
        let volumes = await findVolumes(for: blockDevices)
        let state = CorrelatedStorageDevice.determineState(
            blockDevices: blockDevices,
            volumes: volumes
        )

        let correlated = CorrelatedStorageDevice(
            usbDevice: usbDevice,
            blockDevices: blockDevices,
            volumes: volumes,
            visibilityState: state
        )

        correlationMap[usbDevice.registryEntryID] = correlated
        updateCorrelatedDevices()

        return correlated
    }

    /// Force re-correlation for a specific USB device
    func refreshCorrelation(for usbDevice: USBDevice) async -> CorrelatedStorageDevice {
        return await correlateDevice(usbDevice)
    }

    /// Remove correlation for a USB device
    func removeCorrelation(for usbDevice: USBDevice) {
        correlationMap.removeValue(forKey: usbDevice.registryEntryID)
        updateCorrelatedDevices()
    }

    // MARK: - Block Device Discovery

    /// Find block devices that might be associated with a USB device
    private func findBlockDevicesForUSB(locationID: UInt32) async -> [BlockDevice] {
        var devices: [BlockDevice] = []

        // Query all external disks and filter by USB bus
        let diskutilRunner = SafeDiskutilRunner()

        do {
            let data = try await diskutilRunner.list(external: true)
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let wholeDisks = plist["WholeDisks"] as? [String] else {
                return devices
            }

            for diskName in wholeDisks {
                if let device = await getBlockDevice(bsdName: diskName) {
                    // Check if this is a USB device
                    if device.busName?.lowercased() == "usb" {
                        devices.append(device)

                        // Also get partitions
                        let partitions = await getPartitions(for: diskName)
                        devices.append(contentsOf: partitions)
                    }
                }
            }
        } catch {
            // Log but don't fail - return empty array
            SafetyGuard.auditLog("Failed to enumerate block devices: \(error)", level: .warning)
        }

        return devices.sorted { $0.bsdName < $1.bsdName }
    }

    /// Get block device info for a BSD name
    private func getBlockDevice(bsdName: String) async -> BlockDevice? {
        let diskutilRunner = SafeDiskutilRunner()

        do {
            let data = try await diskutilRunner.info(bsdName: bsdName)
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return nil
            }

            return BlockDevice(
                bsdName: bsdName,
                mediaPath: plist["DevicePath"] as? String ?? "",
                size: (plist["Size"] as? NSNumber)?.uint64Value ?? 0,
                isWhole: plist["WholeDisk"] as? Bool ?? true,
                isWritable: plist["Writable"] as? Bool ?? true,
                mediaType: plist["MediaType"] as? String,
                busName: plist["BusProtocol"] as? String
            )
        } catch {
            return nil
        }
    }

    /// Get partitions for a whole disk
    private func getPartitions(for wholeDisk: String) async -> [BlockDevice] {
        var partitions: [BlockDevice] = []
        let diskutilRunner = SafeDiskutilRunner()

        do {
            let data = try await diskutilRunner.list()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let allDisks = plist["AllDisks"] as? [String] else {
                return partitions
            }

            // Find partitions that belong to this whole disk
            for diskName in allDisks {
                if diskName.hasPrefix(wholeDisk) && diskName != wholeDisk {
                    if let device = await getBlockDevice(bsdName: diskName) {
                        partitions.append(device)
                    }
                }
            }
        } catch {
            // Ignore errors
        }

        return partitions
    }

    // MARK: - Volume Discovery

    /// Find volumes for given block devices using DiskArbitration
    private func findVolumes(for blockDevices: [BlockDevice]) async -> [VolumeInfo] {
        guard let session = daSession else { return [] }

        var volumes: [VolumeInfo] = []

        for blockDevice in blockDevices where !blockDevice.isWhole {
            if let disk = DADiskCreateFromBSDName(
                kCFAllocatorDefault,
                session,
                blockDevice.bsdName
            ) {
                if let volume = createVolumeInfo(from: disk, bsdName: blockDevice.bsdName) {
                    volumes.append(volume)
                }
            }
        }

        return volumes
    }

    private func createVolumeInfo(from disk: DADisk, bsdName: String) -> VolumeInfo? {
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
            return nil
        }

        let volumeName = description[kDADiskDescriptionVolumeNameKey as String] as? String
        let volumeUUID: String? = {
            guard let uuid = description[kDADiskDescriptionVolumeUUIDKey as String] else { return nil }
            let cfUUID = uuid as! CFUUID
            return CFUUIDCreateString(kCFAllocatorDefault, cfUUID) as String
        }()
        let mountPointURL = description[kDADiskDescriptionVolumePathKey as String] as? URL
        let isMounted = mountPointURL != nil
        let filesystemType = description[kDADiskDescriptionVolumeKindKey as String] as? String
        let size = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0

        // Get free space and writable status if mounted
        var freeSpace: UInt64? = nil
        var isReadWrite = false
        if let mountPoint = mountPointURL {
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: mountPoint.path) {
                if let free = attrs[.systemFreeSize] as? UInt64 {
                    freeSpace = free
                }
                // Check if volume is writable
                if FileManager.default.isWritableFile(atPath: mountPoint.path) {
                    isReadWrite = true
                }
            }
        }

        return VolumeInfo(
            bsdName: bsdName,
            volumeName: volumeName,
            volumeUUID: volumeUUID,
            mountPoint: mountPointURL,
            isMounted: isMounted,
            filesystemType: filesystemType,
            size: size,
            freeSpace: freeSpace,
            isReadWrite: isReadWrite
        )
    }

    // MARK: - DiskArbitration Callbacks

    private func registerDiskCallbacks(_ session: DASession) {
        // Watch for disk appeared events
        DARegisterDiskAppearedCallback(
            session,
            nil, // Match all disks
            { disk, context in
                // Disk appeared - trigger refresh
            },
            nil
        )

        // Watch for disk disappeared events
        DARegisterDiskDisappearedCallback(
            session,
            nil, // Match all disks
            { disk, context in
                // Disk disappeared - trigger refresh
            },
            nil
        )

        // Watch for description changed events (mount/unmount)
        DARegisterDiskDescriptionChangedCallback(
            session,
            nil, // Match all disks
            nil, // Watch all keys
            { disk, keys, context in
                // Description changed - trigger refresh
            },
            nil
        )
    }

    private func updateCorrelatedDevices() {
        correlatedDevices = Array(correlationMap.values)
            .sorted { $0.usbDevice.locationID < $1.usbDevice.locationID }
    }
}
