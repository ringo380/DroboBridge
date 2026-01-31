//
//  SafetyGuardTests.swift
//  DroboBridgeTests
//
//  Unit tests for SafetyGuard command validation
//

import XCTest
@testable import DroboBridge

final class SafetyGuardTests: XCTestCase {

    // MARK: - Allowed Commands

    func testAllowedCommands() {
        let allowedCommands = [
            ["list"],
            ["list", "-plist"],
            ["list", "external"],
            ["info", "disk4"],
            ["info", "-plist", "disk4s1"],
            ["verifyDisk", "disk4"],
            ["verifyVolume", "disk4s1"],
            ["mount", "disk4s1"],
            ["mountDisk", "disk4"],
            ["unmount", "disk4s1"],
            ["unmountDisk", "disk4"],
            ["eject", "disk4"],
            ["activity"],
            ["listFilesystems"]
        ]

        for args in allowedCommands {
            XCTAssertNoThrow(
                try SafetyGuard.validateDiskutilCommand(args),
                "Command should be allowed: \(args.joined(separator: " "))"
            )
        }
    }

    // MARK: - Forbidden Commands

    func testForbiddenCommands() {
        let forbiddenCommands = [
            ["eraseDisk"],
            ["eraseDisk", "JHFS+", "NewDisk", "disk4"],
            ["eraseVolume"],
            ["eraseVolume", "JHFS+", "NewVolume", "disk4s1"],
            ["partitionDisk"],
            ["partitionDisk", "disk4", "2", "GPT", "JHFS+", "First", "50%", "JHFS+", "Second", "50%"],
            ["addPartition"],
            ["deletePartition"],
            ["mergePartitions"],
            ["splitPartition"],
            ["resizeVolume"],
            ["secureErase"],
            ["zeroDisk"],
            ["randomDisk"],
            ["apfs"],
            ["apfs", "create", "disk4s1"],
            ["coreStorage"],
            ["rename"]
        ]

        for args in forbiddenCommands {
            XCTAssertThrowsError(
                try SafetyGuard.validateDiskutilCommand(args),
                "Command should be forbidden: \(args.joined(separator: " "))"
            ) { error in
                guard let safetyError = error as? SafetyError else {
                    XCTFail("Expected SafetyError")
                    return
                }

                if case .forbiddenCommand = safetyError {
                    // Expected
                } else {
                    XCTFail("Expected forbiddenCommand error")
                }
            }
        }
    }

    // MARK: - Unknown Commands

    func testUnknownCommands() {
        let unknownCommands = [
            ["foo"],
            ["bar", "disk4"],
            ["execute", "something"],
            ["format"],
            ["destroy"]
        ]

        for args in unknownCommands {
            XCTAssertThrowsError(
                try SafetyGuard.validateDiskutilCommand(args),
                "Command should be unknown: \(args.joined(separator: " "))"
            ) { error in
                guard let safetyError = error as? SafetyError else {
                    XCTFail("Expected SafetyError")
                    return
                }

                if case .unknownCommand = safetyError {
                    // Expected
                } else {
                    XCTFail("Expected unknownCommand error")
                }
            }
        }
    }

    // MARK: - Empty Command

    func testEmptyCommand() {
        XCTAssertThrowsError(
            try SafetyGuard.validateDiskutilCommand([])
        ) { error in
            guard let safetyError = error as? SafetyError else {
                XCTFail("Expected SafetyError")
                return
            }

            if case .noCommand = safetyError {
                // Expected
            } else {
                XCTFail("Expected noCommand error")
            }
        }
    }

    // MARK: - isCommandSafe Helper

    func testIsCommandSafe() {
        XCTAssertTrue(SafetyGuard.isCommandSafe(["list"]))
        XCTAssertTrue(SafetyGuard.isCommandSafe(["info", "disk4"]))
        XCTAssertFalse(SafetyGuard.isCommandSafe(["eraseDisk"]))
        XCTAssertFalse(SafetyGuard.isCommandSafe(["unknown"]))
        XCTAssertFalse(SafetyGuard.isCommandSafe([]))
    }

    // MARK: - Mount Validation

    func testMountValidationReadOnly() {
        XCTAssertNoThrow(
            try SafetyGuard.validateMountOperation(readOnly: true, userConfirmed: false),
            "Read-only mount should not require confirmation"
        )
    }

    func testMountValidationReadWriteConfirmed() {
        XCTAssertNoThrow(
            try SafetyGuard.validateMountOperation(readOnly: false, userConfirmed: true),
            "Read-write mount with confirmation should succeed"
        )
    }

    func testMountValidationReadWriteNotConfirmed() {
        XCTAssertThrowsError(
            try SafetyGuard.validateMountOperation(readOnly: false, userConfirmed: false),
            "Read-write mount without confirmation should fail"
        ) { error in
            guard let safetyError = error as? SafetyError else {
                XCTFail("Expected SafetyError")
                return
            }

            if case .readWriteNotConfirmed = safetyError {
                // Expected
            } else {
                XCTFail("Expected readWriteNotConfirmed error")
            }
        }
    }
}
