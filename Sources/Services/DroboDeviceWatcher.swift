//
//  DroboDeviceWatcher.swift
//  DroboBridge
//
//  IOKit USB device monitoring for Drobo detection
//

import Foundation
import IOKit
import IOKit.usb
import Combine

// MARK: - Device Watcher Protocol

protocol USBDeviceWatcherDelegate: AnyObject {
    func deviceWatcher(_ watcher: DroboDeviceWatcher, didAdd device: USBDevice)
    func deviceWatcher(_ watcher: DroboDeviceWatcher, didRemove device: USBDevice)
    func deviceWatcher(_ watcher: DroboDeviceWatcher, didEncounterError error: DroboDeviceError)
}

// MARK: - Drobo Device Watcher

/// Monitors USB device connect/disconnect events using IOKit
@MainActor
final class DroboDeviceWatcher: ObservableObject {

    // MARK: - Published State

    @Published private(set) var allUSBDevices: [USBDevice] = []
    @Published private(set) var droboDevices: [USBDevice] = []
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var lastError: DroboDeviceError?

    // MARK: - Combine Publishers

    /// Publisher for device addition events
    let deviceAddedPublisher = PassthroughSubject<USBDevice, Never>()

    /// Publisher for device removal events
    let deviceRemovedPublisher = PassthroughSubject<USBDevice, Never>()

    // MARK: - Private Properties

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var deviceMap: [UInt64: USBDevice] = [:] // registryEntryID -> USBDevice
    private let notificationQueue = DispatchQueue(
        label: "com.drobobridge.usb.notifications",
        qos: .userInitiated
    )

    weak var delegate: USBDeviceWatcherDelegate?

    // MARK: - Initialization

    init() {}

    deinit {
        // Note: stopMonitoring() cannot be called from deinit in an actor
        // The caller should ensure stopMonitoring() is called before releasing
    }

    // MARK: - Public API

    /// Start monitoring for USB device events
    func startMonitoring() throws {
        guard !isMonitoring else { return }

        // Create notification port
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw DroboDeviceError.notificationPortCreationFailed
        }
        notificationPort = port

        // Set dispatch queue for notifications
        IONotificationPortSetDispatchQueue(port, notificationQueue)

        // Create matching dictionary for USB devices
        // Use IOUSBHostDevice for macOS 10.11+ (modern USB stack)
        guard let matchingDict = IOServiceMatching("IOUSBHostDevice") else {
            throw DroboDeviceError.matchingDictionaryCreationFailed
        }

        // We need two copies of the matching dictionary
        let addedMatchingDict = matchingDict as NSDictionary
        guard let removedMatchingDict = addedMatchingDict.mutableCopy() as? NSMutableDictionary else {
            throw DroboDeviceError.matchingDictionaryCreationFailed
        }

        // Callback context - we use a weak reference wrapper
        let contextWrapper = WatcherContextWrapper(watcher: self)
        let contextPtr = Unmanaged.passRetained(contextWrapper).toOpaque()

        // Register for device additions (kIOFirstMatchNotification)
        let addResult = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            addedMatchingDict as CFDictionary,
            { (refCon, iterator) in
                guard let refCon = refCon else { return }
                let wrapper = Unmanaged<WatcherContextWrapper>.fromOpaque(refCon).takeUnretainedValue()
                wrapper.handleDevicesAdded(iterator: iterator)
            },
            contextPtr,
            &addedIterator
        )

        guard addResult == KERN_SUCCESS else {
            Unmanaged<WatcherContextWrapper>.fromOpaque(contextPtr).release()
            throw DroboDeviceError.notificationRegistrationFailed(addResult)
        }

        // Register for device removals (kIOTerminatedNotification)
        let removeContextPtr = Unmanaged.passRetained(contextWrapper).toOpaque()
        let removeResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            removedMatchingDict as CFDictionary,
            { (refCon, iterator) in
                guard let refCon = refCon else { return }
                let wrapper = Unmanaged<WatcherContextWrapper>.fromOpaque(refCon).takeUnretainedValue()
                wrapper.handleDevicesRemoved(iterator: iterator)
            },
            removeContextPtr,
            &removedIterator
        )

        guard removeResult == KERN_SUCCESS else {
            Unmanaged<WatcherContextWrapper>.fromOpaque(contextPtr).release()
            throw DroboDeviceError.notificationRegistrationFailed(removeResult)
        }

        isMonitoring = true

        // Process already-connected devices
        processIterator(addedIterator, isAddition: true)

        // Arm the removal iterator (required to receive future notifications)
        processIterator(removedIterator, isAddition: false)
    }

    /// Stop monitoring for USB device events
    func stopMonitoring() {
        guard isMonitoring else { return }

        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }

        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }

        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }

        isMonitoring = false
    }

    /// Manually scan for all USB devices
    func scanAllDevices() throws -> [USBDevice] {
        var devices: [USBDevice] = []
        var iterator: io_iterator_t = 0

        guard let matchingDict = IOServiceMatching("IOUSBHostDevice") else {
            throw DroboDeviceError.matchingDictionaryCreationFailed
        }

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict,
            &iterator
        )

        guard result == KERN_SUCCESS else {
            throw DroboDeviceError.serviceMatchingFailed(result)
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let device = createUSBDevice(from: service) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return devices
    }

    // MARK: - Internal Methods (called from callbacks)

    func processIterator(_ iterator: io_iterator_t, isAddition: Bool) {
        var service = IOIteratorNext(iterator)

        while service != 0 {
            if isAddition {
                if let device = createUSBDevice(from: service) {
                    handleDeviceAdded(device)
                }
            } else {
                handleDeviceRemoved(service)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    // MARK: - Private Methods

    private func createUSBDevice(from service: io_service_t) -> USBDevice? {
        // Get registry entry ID for tracking
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
            return nil
        }

        // Get all properties
        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &propertiesRef,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // Extract USB properties
        // Try different property key formats
        let vendorID: UInt16? = (properties["idVendor"] as? NSNumber)?.uint16Value
            ?? (properties["USB Vendor ID"] as? NSNumber)?.uint16Value

        let productID: UInt16? = (properties["idProduct"] as? NSNumber)?.uint16Value
            ?? (properties["USB Product ID"] as? NSNumber)?.uint16Value

        guard let vendorID = vendorID, let productID = productID else {
            return nil
        }

        let serialNumber = properties["USB Serial Number"] as? String
            ?? properties["kUSBSerialNumberString"] as? String

        let locationID = (properties["locationID"] as? NSNumber)?.uint32Value ?? 0

        let vendorName = properties["USB Vendor Name"] as? String
        let productName = properties["USB Product Name"] as? String

        let deviceClass = (properties["bDeviceClass"] as? NSNumber)?.uint8Value ?? 0
        let deviceSubClass = (properties["bDeviceSubClass"] as? NSNumber)?.uint8Value ?? 0
        let deviceProtocol = (properties["bDeviceProtocol"] as? NSNumber)?.uint8Value ?? 0

        let speedValue = (properties["Device Speed"] as? NSNumber)?.uint8Value ?? 255

        return USBDevice(
            registryEntryID: entryID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            locationID: locationID,
            vendorName: vendorName,
            productName: productName,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            speed: USBDeviceSpeed(from: speedValue)
        )
    }

    private func handleDeviceAdded(_ device: USBDevice) {
        deviceMap[device.registryEntryID] = device
        updateDeviceLists()

        deviceAddedPublisher.send(device)
        delegate?.deviceWatcher(self, didAdd: device)

        // Log if it's a Drobo
        if device.isDrobo {
            SafetyGuard.auditLog("Drobo device connected: \(device.displayName) (VID: \(device.vendorIDHex), PID: \(device.productIDHex))")
        }
    }

    private func handleDeviceRemoved(_ service: io_service_t) {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
              let device = deviceMap[entryID] else {
            return
        }

        deviceMap.removeValue(forKey: entryID)
        updateDeviceLists()

        deviceRemovedPublisher.send(device)
        delegate?.deviceWatcher(self, didRemove: device)

        // Log if it was a Drobo
        if device.isDrobo {
            SafetyGuard.auditLog("Drobo device disconnected: \(device.displayName)")
        }
    }

    private func updateDeviceLists() {
        allUSBDevices = Array(deviceMap.values).sorted { $0.locationID < $1.locationID }
        droboDevices = allUSBDevices.filter { $0.isDrobo }
    }
}

// MARK: - Context Wrapper for Callbacks

/// Wrapper to allow calling back to the watcher from C callbacks
private final class WatcherContextWrapper {
    weak var watcher: DroboDeviceWatcher?

    init(watcher: DroboDeviceWatcher) {
        self.watcher = watcher
    }

    func handleDevicesAdded(iterator: io_iterator_t) {
        Task { @MainActor in
            watcher?.processIterator(iterator, isAddition: true)
        }
    }

    func handleDevicesRemoved(iterator: io_iterator_t) {
        Task { @MainActor in
            watcher?.processIterator(iterator, isAddition: false)
        }
    }
}
