//
//  BlockDevice.swift
//  DroboBridge
//
//  BSD block device model
//

import Foundation

// MARK: - Block Device Model

/// Represents a BSD block device (e.g., /dev/disk4)
struct BlockDevice: Identifiable, Hashable, Codable {
    let id: String // BSD name, e.g., "disk4"
    let bsdName: String
    let mediaPath: String // IOKit media path
    let size: UInt64
    let isWhole: Bool // true if whole disk, false if partition
    let isWritable: Bool
    let mediaType: String? // e.g., "Generic"
    let busName: String? // e.g., "USB"

    var devicePath: String {
        "/dev/\(bsdName)"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    init(
        bsdName: String,
        mediaPath: String = "",
        size: UInt64 = 0,
        isWhole: Bool = true,
        isWritable: Bool = true,
        mediaType: String? = nil,
        busName: String? = nil
    ) {
        self.id = bsdName
        self.bsdName = bsdName
        self.mediaPath = mediaPath
        self.size = size
        self.isWhole = isWhole
        self.isWritable = isWritable
        self.mediaType = mediaType
        self.busName = busName
    }
}

// MARK: - Physical Disk Model (from diskutil)

/// Represents a physical disk from diskutil output
struct PhysicalDisk: Identifiable, Hashable, Codable {
    let id: String // BSD name (e.g., "disk14")
    let deviceNode: String // /dev/disk14
    let busProtocol: BusProtocol
    let size: UInt64
    let mediaName: String
    let vendorName: String?
    let modelName: String?
    let isInternal: Bool
    let isEjectable: Bool
    let isRemovable: Bool
    let partitionScheme: PartitionScheme
    var partitions: [Partition]
    let smartStatus: SMARTStatus

    var isDrobo: Bool {
        // Drobo devices typically identify as "Drobo" in vendor or model
        let droboIdentifiers = ["Drobo", "DROBO", "Data Robotics"]
        return droboIdentifiers.contains {
            vendorName?.contains($0) == true || modelName?.contains($0) == true
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    init(
        id: String,
        deviceNode: String,
        busProtocol: BusProtocol,
        size: UInt64,
        mediaName: String,
        vendorName: String?,
        modelName: String?,
        isInternal: Bool,
        isEjectable: Bool,
        isRemovable: Bool,
        partitionScheme: PartitionScheme,
        partitions: [Partition],
        smartStatus: SMARTStatus
    ) {
        self.id = id
        self.deviceNode = deviceNode
        self.busProtocol = busProtocol
        self.size = size
        self.mediaName = mediaName
        self.vendorName = vendorName
        self.modelName = modelName
        self.isInternal = isInternal
        self.isEjectable = isEjectable
        self.isRemovable = isRemovable
        self.partitionScheme = partitionScheme
        self.partitions = partitions
        self.smartStatus = smartStatus
    }
}

// MARK: - Bus Protocol

enum BusProtocol: String, CaseIterable, Codable {
    case usb = "USB"
    case thunderbolt = "Thunderbolt"
    case sata = "SATA"
    case nvme = "NVMe"
    case appleFabric = "Apple Fabric"
    case firewire = "FireWire"
    case unknown = "Unknown"

    init(from string: String?) {
        guard let string = string else { self = .unknown; return }
        self = BusProtocol.allCases.first {
            $0.rawValue.lowercased() == string.lowercased()
        } ?? .unknown
    }
}

// MARK: - Partition Scheme

enum PartitionScheme: String, Codable {
    case guid = "GUID_partition_scheme"
    case mbr = "FDisk_partition_scheme"
    case applePartitionMap = "Apple_partition_scheme"
    case unknown = "Unknown"

    init(from content: String?) {
        switch content {
        case "GUID_partition_scheme": self = .guid
        case "FDisk_partition_scheme": self = .mbr
        case "Apple_partition_scheme": self = .applePartitionMap
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .guid: return "GPT (GUID Partition Table)"
        case .mbr: return "MBR (Master Boot Record)"
        case .applePartitionMap: return "Apple Partition Map"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - SMART Status

enum SMARTStatus: String, Codable {
    case verified = "Verified"
    case failing = "Failing"
    case notSupported = "Not Supported"
    case unknown = "Unknown"

    init(from string: String?) {
        guard let string = string else { self = .unknown; return }
        switch string {
        case "Verified": self = .verified
        case "Failing": self = .failing
        case "Not Supported": self = .notSupported
        default: self = .unknown
        }
    }
}
