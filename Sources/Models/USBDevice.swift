//
//  USBDevice.swift
//  DroboBridge
//
//  USB device model for IOKit device discovery
//

import Foundation
import IOKit
import IOKit.usb

// MARK: - USB Device Model

/// Represents a USB device discovered via IOKit
struct USBDevice: Identifiable, Hashable, Codable {
    let id: UUID

    // Core identification
    let registryEntryID: UInt64
    let vendorID: UInt16
    let productID: UInt16
    let serialNumber: String?
    let locationID: UInt32

    // Descriptive info
    let vendorName: String?
    let productName: String?
    let deviceClass: UInt8
    let deviceSubClass: UInt8
    let deviceProtocol: UInt8

    // Device speed
    let speed: USBDeviceSpeed

    // Computed properties
    var isDrobo: Bool {
        DroboIdentifier.isDroboDevice(vendorID: vendorID, productID: productID)
    }

    var displayName: String {
        productName ?? vendorName ?? "Unknown USB Device"
    }

    var vendorIDHex: String {
        String(format: "0x%04X", vendorID)
    }

    var productIDHex: String {
        String(format: "0x%04X", productID)
    }

    var locationIDHex: String {
        String(format: "0x%08X", locationID)
    }

    // Hashable conformance (exclude non-Hashable properties)
    func hash(into hasher: inout Hasher) {
        hasher.combine(registryEntryID)
    }

    static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
        lhs.registryEntryID == rhs.registryEntryID
    }

    // Initializer
    init(
        id: UUID = UUID(),
        registryEntryID: UInt64,
        vendorID: UInt16,
        productID: UInt16,
        serialNumber: String?,
        locationID: UInt32,
        vendorName: String?,
        productName: String?,
        deviceClass: UInt8,
        deviceSubClass: UInt8,
        deviceProtocol: UInt8,
        speed: USBDeviceSpeed
    ) {
        self.id = id
        self.registryEntryID = registryEntryID
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.locationID = locationID
        self.vendorName = vendorName
        self.productName = productName
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.speed = speed
    }
}

// MARK: - USB Device Speed

enum USBDeviceSpeed: String, CaseIterable, Codable {
    case low = "Low Speed (1.5 Mbps)"
    case full = "Full Speed (12 Mbps)"
    case high = "High Speed (480 Mbps)"
    case superSpeed = "SuperSpeed (5 Gbps)"
    case superSpeedPlus = "SuperSpeed+ (10+ Gbps)"
    case unknown = "Unknown"

    init(from speedValue: UInt8) {
        switch speedValue {
        case 0: self = .low
        case 1: self = .full
        case 2: self = .high
        case 3: self = .superSpeed
        case 4: self = .superSpeedPlus
        default: self = .unknown
        }
    }

    var shortName: String {
        switch self {
        case .low: return "USB 1.0"
        case .full: return "USB 1.1"
        case .high: return "USB 2.0"
        case .superSpeed: return "USB 3.0"
        case .superSpeedPlus: return "USB 3.1+"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Drobo Identification

/// Known Drobo vendor and product IDs
struct DroboIdentifier {
    // Primary vendor ID (confirmed from USB ID database)
    static let vendorID_Drobo: UInt16 = 0x19B9

    // Alternate vendor ID (to verify with actual hardware)
    static let vendorID_Alternate: UInt16 = 0x4641

    // Known product IDs
    static let productID_Elite: UInt16 = 0x8D20
    static let productID_DAS: UInt16 = 0x4D10

    static let knownVendorIDs: Set<UInt16> = [
        vendorID_Drobo,
        vendorID_Alternate
    ]

    /// Check if a device is likely a Drobo based on vendor/product IDs
    static func isDroboDevice(vendorID: UInt16, productID: UInt16? = nil) -> Bool {
        knownVendorIDs.contains(vendorID)
    }

    /// Get a display name for a known Drobo model
    static func modelName(vendorID: UInt16, productID: UInt16) -> String? {
        guard isDroboDevice(vendorID: vendorID) else { return nil }

        switch productID {
        case productID_Elite:
            return "Drobo Elite"
        case productID_DAS:
            return "Drobo DAS"
        default:
            return "Drobo Device"
        }
    }
}
