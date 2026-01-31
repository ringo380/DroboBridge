//
//  VolumeInfo.swift
//  DroboBridge
//
//  Volume and partition models
//

import Foundation

// MARK: - Volume Info Model

/// Represents a mounted or unmounted volume
struct VolumeInfo: Identifiable, Hashable, Codable {
    let id: String // BSD name of the partition
    let bsdName: String
    let volumeName: String?
    let volumeUUID: String?
    let mountPoint: URL?
    let isMounted: Bool
    let filesystemType: String?
    let size: UInt64
    let freeSpace: UInt64?
    let isReadWrite: Bool

    var displayName: String {
        volumeName ?? bsdName
    }

    var devicePath: String {
        "/dev/\(bsdName)"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedFreeSpace: String? {
        guard let free = freeSpace else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
    }

    var usedPercentage: Double? {
        guard let free = freeSpace, size > 0 else { return nil }
        let used = Double(size - free)
        return (used / Double(size)) * 100.0
    }

    /// Whether this volume supports write operations (false = read-only)
    var canWrite: Bool {
        isMounted && isReadWrite
    }

    init(
        bsdName: String,
        volumeName: String? = nil,
        volumeUUID: String? = nil,
        mountPoint: URL? = nil,
        isMounted: Bool = false,
        filesystemType: String? = nil,
        size: UInt64 = 0,
        freeSpace: UInt64? = nil,
        isReadWrite: Bool = false
    ) {
        self.id = bsdName
        self.bsdName = bsdName
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.mountPoint = mountPoint
        self.isMounted = isMounted
        self.filesystemType = filesystemType
        self.size = size
        self.freeSpace = freeSpace
        self.isReadWrite = isReadWrite
    }
}

// MARK: - Partition Model

/// Represents a partition from diskutil info
struct Partition: Identifiable, Hashable, Codable {
    let id: String // BSD name (e.g., "disk14s1")
    let deviceNode: String
    let size: UInt64
    let offset: UInt64?
    let partitionType: PartitionType
    let filesystem: Filesystem
    let volumeName: String?
    let volumeUUID: String?
    let mountPoint: URL?
    let isMountable: Bool
    let isWritable: Bool

    var displayName: String {
        volumeName ?? id
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    init(
        id: String,
        deviceNode: String,
        size: UInt64,
        offset: UInt64?,
        partitionType: PartitionType,
        filesystem: Filesystem,
        volumeName: String?,
        volumeUUID: String?,
        mountPoint: URL?,
        isMountable: Bool,
        isWritable: Bool
    ) {
        self.id = id
        self.deviceNode = deviceNode
        self.size = size
        self.offset = offset
        self.partitionType = partitionType
        self.filesystem = filesystem
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.mountPoint = mountPoint
        self.isMountable = isMountable
        self.isWritable = isWritable
    }
}

// MARK: - Partition Type

enum PartitionType: Codable, Equatable, Hashable {
    case apfs
    case apfsContainer
    case hfsPlus
    case msDosData // FAT32, ExFAT
    case ntfs
    case linuxNative // ext2/3/4
    case linuxSwap
    case microsoftReserved
    case efiSystem
    case appleBoot
    case unknown(String)

    init(from content: String?) {
        guard let content = content else { self = .unknown("nil"); return }
        switch content {
        case "Apple_APFS": self = .apfsContainer
        case "41504653-0000-11AA-AA11-00306543ECAC": self = .apfs // APFS volume GUID
        case "Apple_HFS", "Apple_HFSX": self = .hfsPlus
        case "Microsoft Basic Data": self = .msDosData
        case "Linux": self = .linuxNative
        case "Linux Swap": self = .linuxSwap
        case "Microsoft Reserved": self = .microsoftReserved
        case "EFI", "EFI System Partition": self = .efiSystem
        case "Apple_Boot": self = .appleBoot
        default: self = .unknown(content)
        }
    }

    var displayName: String {
        switch self {
        case .apfs: return "APFS"
        case .apfsContainer: return "APFS Container"
        case .hfsPlus: return "HFS+"
        case .msDosData: return "FAT/ExFAT/NTFS"
        case .ntfs: return "NTFS"
        case .linuxNative: return "Linux (ext2/3/4)"
        case .linuxSwap: return "Linux Swap"
        case .microsoftReserved: return "Microsoft Reserved"
        case .efiSystem: return "EFI System"
        case .appleBoot: return "Apple Boot"
        case .unknown(let raw): return "Unknown (\(raw))"
        }
    }

    var isMacOSNative: Bool {
        switch self {
        case .apfs, .apfsContainer, .hfsPlus:
            return true
        default:
            return false
        }
    }
}

// MARK: - Filesystem

struct Filesystem: Codable, Equatable, Hashable {
    let type: String? // e.g., "apfs", "hfs", "msdos"
    let name: String? // e.g., "APFS", "MS-DOS (FAT)"
    let userVisibleName: String?

    static let unsupported = Filesystem(type: nil, name: nil, userVisibleName: nil)

    var isSupported: Bool {
        guard let type = type else { return false }
        let supportedTypes = ["apfs", "hfs", "msdos", "exfat", "udf", "cd9660"]
        return supportedTypes.contains(type.lowercased())
    }

    var isNTFS: Bool {
        return type?.lowercased() == "ntfs"
    }

    var isLinuxFilesystem: Bool {
        let linuxTypes = ["ext2", "ext3", "ext4", "xfs", "btrfs", "reiserfs"]
        return linuxTypes.contains { type?.lowercased().contains($0) == true }
    }

    var displayName: String {
        userVisibleName ?? name ?? type ?? "Unknown"
    }

    init(type: String?, name: String?, userVisibleName: String?) {
        self.type = type
        self.name = name
        self.userVisibleName = userVisibleName
    }
}

// MARK: - Mount State

enum MountState: Equatable {
    case unmounted
    case mounting
    case mounted(path: URL, readOnly: Bool)
    case unmounting
    case failed(String)

    var displayName: String {
        switch self {
        case .unmounted:
            return "Unmounted"
        case .mounting:
            return "Mounting..."
        case .mounted(_, let readOnly):
            return readOnly ? "Mounted (Read-Only)" : "Mounted"
        case .unmounting:
            return "Unmounting..."
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    var isMounted: Bool {
        if case .mounted = self {
            return true
        }
        return false
    }
}
