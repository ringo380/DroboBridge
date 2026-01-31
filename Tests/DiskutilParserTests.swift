//
//  DiskutilParserTests.swift
//  DroboBridgeTests
//
//  Unit tests for diskutil output parsing
//

import XCTest
@testable import DroboBridge

final class DiskutilParserTests: XCTestCase {

    // MARK: - BSD Name Validation

    func testValidBSDNames() {
        let validNames = [
            "disk0",
            "disk1",
            "disk10",
            "disk99",
            "disk0s1",
            "disk0s2",
            "disk10s1",
            "disk4s1",
            "disk14s1",
            "disk0s1s1"  // Nested (e.g., APFS)
        ]

        for name in validNames {
            XCTAssertTrue(
                isValidBSDName(name),
                "Should be valid: \(name)"
            )
        }
    }

    func testInvalidBSDNames() {
        let invalidNames = [
            "",
            "disk",
            "disk-1",
            "disk0s",
            "Disk0",
            "/dev/disk0",
            "disk0 ",
            " disk0",
            "disk0; rm -rf /",
            "disk0 && echo pwned",
            "../disk0",
            "disk0\n"
        ]

        for name in invalidNames {
            XCTAssertFalse(
                isValidBSDName(name),
                "Should be invalid: '\(name)'"
            )
        }
    }

    // MARK: - Partition Type Parsing

    func testPartitionTypeParsing() {
        let testCases: [(String?, PartitionType)] = [
            ("Apple_APFS", .apfsContainer),
            ("Apple_HFS", .hfsPlus),
            ("Apple_HFSX", .hfsPlus),
            ("Microsoft Basic Data", .msDosData),
            ("Linux", .linuxNative),
            ("Linux Swap", .linuxSwap),
            ("EFI", .efiSystem),
            ("Apple_Boot", .appleBoot),
            (nil, .unknown("nil")),
            ("SomeUnknownType", .unknown("SomeUnknownType"))
        ]

        for (input, expected) in testCases {
            let result = PartitionType(from: input)
            XCTAssertEqual(result.displayName, expected.displayName, "Parsing '\(input ?? "nil")'")
        }
    }

    // MARK: - Bus Protocol Parsing

    func testBusProtocolParsing() {
        let testCases: [(String?, BusProtocol)] = [
            ("USB", .usb),
            ("usb", .usb),
            ("Thunderbolt", .thunderbolt),
            ("SATA", .sata),
            ("NVMe", .nvme),
            ("Apple Fabric", .appleFabric),
            ("FireWire", .firewire),
            (nil, .unknown),
            ("Unknown Protocol", .unknown)
        ]

        for (input, expected) in testCases {
            let result = BusProtocol(from: input)
            XCTAssertEqual(result, expected, "Parsing '\(input ?? "nil")'")
        }
    }

    // MARK: - Storage Visibility State

    func testStorageVisibilityStateOrdering() {
        XCTAssertLessThan(StorageVisibilityState.usbOnly, .blockDeviceOnly)
        XCTAssertLessThan(StorageVisibilityState.blockDeviceOnly, .volumesUnmounted)
        XCTAssertLessThan(StorageVisibilityState.volumesUnmounted, .mounted)
    }

    func testStorageVisibilityStateDetermination() {
        // USB Only
        let usbOnlyState = CorrelatedStorageDevice.determineState(
            blockDevices: [],
            volumes: []
        )
        XCTAssertEqual(usbOnlyState, .usbOnly)

        // Block Device Only
        let blockDeviceOnlyState = CorrelatedStorageDevice.determineState(
            blockDevices: [BlockDevice(bsdName: "disk4")],
            volumes: []
        )
        XCTAssertEqual(blockDeviceOnlyState, .blockDeviceOnly)

        // Volumes Unmounted
        let volumesUnmountedState = CorrelatedStorageDevice.determineState(
            blockDevices: [BlockDevice(bsdName: "disk4")],
            volumes: [VolumeInfo(bsdName: "disk4s1", isMounted: false)]
        )
        XCTAssertEqual(volumesUnmountedState, .volumesUnmounted)

        // Mounted
        let mountedState = CorrelatedStorageDevice.determineState(
            blockDevices: [BlockDevice(bsdName: "disk4")],
            volumes: [VolumeInfo(bsdName: "disk4s1", isMounted: true)]
        )
        XCTAssertEqual(mountedState, .mounted)
    }

    // MARK: - Filesystem Detection

    func testFilesystemSupportDetection() {
        let supportedFilesystems = [
            Filesystem(type: "apfs", name: "APFS", userVisibleName: nil),
            Filesystem(type: "hfs", name: "HFS+", userVisibleName: nil),
            Filesystem(type: "msdos", name: "MS-DOS (FAT)", userVisibleName: nil),
            Filesystem(type: "exfat", name: "ExFAT", userVisibleName: nil)
        ]

        for fs in supportedFilesystems {
            XCTAssertTrue(fs.isSupported, "\(fs.type ?? "nil") should be supported")
        }

        let unsupportedFilesystems = [
            Filesystem(type: "ext4", name: nil, userVisibleName: nil),
            Filesystem(type: "ntfs", name: nil, userVisibleName: nil),
            Filesystem(type: nil, name: nil, userVisibleName: nil)
        ]

        for fs in unsupportedFilesystems {
            XCTAssertFalse(fs.isSupported, "\(fs.type ?? "nil") should not be supported")
        }
    }

    func testLinuxFilesystemDetection() {
        let linuxFilesystems = [
            Filesystem(type: "ext2", name: nil, userVisibleName: nil),
            Filesystem(type: "ext3", name: nil, userVisibleName: nil),
            Filesystem(type: "ext4", name: nil, userVisibleName: nil),
            Filesystem(type: "xfs", name: nil, userVisibleName: nil),
            Filesystem(type: "btrfs", name: nil, userVisibleName: nil)
        ]

        for fs in linuxFilesystems {
            XCTAssertTrue(fs.isLinuxFilesystem, "\(fs.type ?? "nil") should be Linux filesystem")
        }

        let nonLinuxFilesystems = [
            Filesystem(type: "apfs", name: nil, userVisibleName: nil),
            Filesystem(type: "hfs", name: nil, userVisibleName: nil),
            Filesystem(type: "ntfs", name: nil, userVisibleName: nil)
        ]

        for fs in nonLinuxFilesystems {
            XCTAssertFalse(fs.isLinuxFilesystem, "\(fs.type ?? "nil") should not be Linux filesystem")
        }
    }

    // MARK: - Drobo Identification

    func testDroboVendorIDDetection() {
        XCTAssertTrue(DroboIdentifier.isDroboDevice(vendorID: 0x19B9))
        XCTAssertTrue(DroboIdentifier.isDroboDevice(vendorID: 0x4641))
        XCTAssertFalse(DroboIdentifier.isDroboDevice(vendorID: 0x1234))
        XCTAssertFalse(DroboIdentifier.isDroboDevice(vendorID: 0x05AC)) // Apple
    }

    // MARK: - Helper

    private func isValidBSDName(_ name: String) -> Bool {
        let pattern = #"^disk\d+(?:s\d+)*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
