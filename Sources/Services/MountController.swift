//
//  MountController.swift
//  DroboBridge
//
//  DiskArbitration-based mount/unmount operations
//
//  SAFETY: All mounts default to read-only mode
//

import Foundation
import DiskArbitration

// MARK: - Mount Controller

/// Handles mount and unmount operations via DiskArbitration
@MainActor
final class MountController: ObservableObject {

    // MARK: - Published State

    @Published private(set) var mountStates: [String: MountState] = [:] // Keyed by BSD name
    @Published private(set) var mountAttempts: [MountAttempt] = []
    @Published private(set) var ext4FuseAvailable: Bool = false
    @Published private(set) var fuseType: FuseType = .none
    @Published private(set) var paragonAvailable: Bool = false
    @Published private(set) var linuxFilesystemDriver: LinuxFilesystemDriver = .none

    // MARK: - Private Properties

    private var session: DASession?
    private let queue = DispatchQueue(label: "com.drobobridge.mount", qos: .userInitiated)
    private let ext4FuseController = Ext4FuseController()

    // MARK: - Initialization

    init() {}

    func initialize() throws {
        guard session == nil else { return }

        guard let newSession = DASessionCreate(kCFAllocatorDefault) else {
            throw MountError.sessionCreationFailed
        }
        session = newSession
        DASessionSetDispatchQueue(newSession, queue)

        // Check ext4fuse availability in background
        Task {
            await checkExt4FuseAvailability()
        }
    }

    /// Check availability of Linux filesystem drivers
    private func checkExt4FuseAvailability() async {
        ext4FuseAvailable = await ext4FuseController.isExt4FuseAvailable()
        fuseType = await ext4FuseController.detectFuseType()
        paragonAvailable = await ext4FuseController.isParagonAvailable()
        linuxFilesystemDriver = await ext4FuseController.detectLinuxFilesystemDriver()
        SafetyGuard.auditLog("Linux FS driver: \(linuxFilesystemDriver.rawValue), Paragon: \(paragonAvailable), ext4fuse: \(ext4FuseAvailable), FUSE: \(fuseType.rawValue)")
    }

    deinit {
        if let session = session {
            DASessionSetDispatchQueue(session, nil)
        }
    }

    // MARK: - Mount Operations

    /// Mount a volume READ-ONLY (default safe mode)
    func mountReadOnly(bsdName: String, volumeName: String? = nil) async throws {
        try await mount(bsdName: bsdName, volumeName: volumeName, readOnly: true)
    }

    /// Mount a volume (CAUTION: read-write requires confirmation)
    func mount(bsdName: String, volumeName: String? = nil, readOnly: Bool = true, userConfirmed: Bool = false) async throws {
        // Safety check for read-write mounts
        try SafetyGuard.validateMountOperation(readOnly: readOnly, userConfirmed: userConfirmed || readOnly)

        SafetyGuard.auditLog("Mount requested: \(bsdName), readOnly: \(readOnly)")

        guard let session = session else {
            throw MountError.sessionCreationFailed
        }

        // Create disk reference
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "Disk not found"), readOnly: readOnly)
            throw MountError.diskNotFound(bsdName: bsdName)
        }

        // Check if already mounted
        if let description = DADiskCopyDescription(disk) as? [String: Any],
           description[kDADiskDescriptionVolumePathKey as String] != nil {
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "Already mounted"), readOnly: readOnly)
            throw MountError.alreadyMounted
        }

        // Update state
        updateState(for: bsdName, state: .mounting)

        // Perform mount with continuation - try DiskArbitration first, then FUSE fallback
        do {
            let mountPoint = try await performMount(disk: disk, readOnly: readOnly)

            updateState(for: bsdName, state: .mounted(path: mountPoint ?? URL(fileURLWithPath: "/Volumes/Unknown"), readOnly: readOnly))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .success(mountPoint: mountPoint?.path), readOnly: readOnly)

            SafetyGuard.auditLog("Mount successful: \(bsdName) at \(mountPoint?.path ?? "unknown")")
        } catch let mountError as MountError where mountError.requiresExt4Fuse {
            // DiskArbitration failed with unsupported filesystem - check for Linux FS drivers
            SafetyGuard.auditLog("DiskArbitration failed, checking Linux filesystem drivers for \(bsdName)")
            try await mountLinuxFilesystem(bsdName: bsdName, volumeName: volumeName, readOnly: readOnly)
        } catch {
            updateState(for: bsdName, state: .failed(error.localizedDescription))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: error.localizedDescription), readOnly: readOnly)
            throw error
        }
    }

    /// Mount a Linux filesystem using the best available driver (Paragon > ext4fuse)
    private func mountLinuxFilesystem(bsdName: String, volumeName: String?, readOnly: Bool) async throws {
        // Check if this is a Linux filesystem
        let isLinuxFS = await ext4FuseController.isLinuxFilesystem(bsdName: bsdName)

        if !isLinuxFS {
            // Not a Linux filesystem, re-throw the original error
            updateState(for: bsdName, state: .failed("Unsupported filesystem"))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "Unsupported filesystem"), readOnly: readOnly)
            throw MountError.unsupportedFilesystem(nil)
        }

        // Check which Linux filesystem driver is available
        let driver = await ext4FuseController.detectLinuxFilesystemDriver()

        switch driver {
        case .paragon:
            // Paragon extFS is installed - use native DiskArbitration mounting
            try await mountWithParagon(bsdName: bsdName, volumeName: volumeName, readOnly: readOnly)

        case .ext4fuse:
            // Fall back to ext4fuse (read-only)
            try await mountWithExt4Fuse(bsdName: bsdName, volumeName: volumeName)

        case .none:
            updateState(for: bsdName, state: .failed("No Linux filesystem driver"))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "Install Paragon extFS or ext4fuse to mount Linux filesystems"), readOnly: readOnly)
            throw MountError.ext4FuseNotInstalled
        }
    }

    /// Mount using Paragon extFS (native DiskArbitration - supports read-write)
    private func mountWithParagon(bsdName: String, volumeName: String?, readOnly: Bool) async throws {
        guard let session = session else {
            throw MountError.sessionCreationFailed
        }

        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            throw MountError.diskNotFound(bsdName: bsdName)
        }

        SafetyGuard.auditLog("Mounting \(bsdName) with Paragon extFS (readOnly: \(readOnly))")

        do {
            let mountPoint = try await performMount(disk: disk, readOnly: readOnly)

            updateState(for: bsdName, state: .mounted(path: mountPoint ?? URL(fileURLWithPath: "/Volumes/Unknown"), readOnly: readOnly))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .success(mountPoint: mountPoint?.path), readOnly: readOnly)

            SafetyGuard.auditLog("Paragon mount successful: \(bsdName) at \(mountPoint?.path ?? "unknown"), readOnly: \(readOnly)")
        } catch {
            updateState(for: bsdName, state: .failed(error.localizedDescription))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: error.localizedDescription), readOnly: readOnly)
            throw error
        }
    }

    /// Attempt to mount using ext4fuse (for Linux filesystems - always read-only)
    private func mountWithExt4Fuse(bsdName: String, volumeName: String?) async throws {
        // Check if ext4fuse is available
        guard await ext4FuseController.isExt4FuseAvailable() else {
            updateState(for: bsdName, state: .failed("ext4fuse not installed"))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "ext4fuse not installed - install it to mount Linux filesystems"), readOnly: true)
            throw MountError.ext4FuseNotInstalled
        }

        // Check if FUSE implementation is available
        let fuseType = await ext4FuseController.detectFuseType()
        guard fuseType != .none else {
            updateState(for: bsdName, state: .failed("FUSE not installed"))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: "macFUSE or FUSE-T not installed"), readOnly: true)
            throw MountError.ext4FuseNotInstalled
        }

        SafetyGuard.auditLog("Mounting \(bsdName) with ext4fuse (FUSE type: \(fuseType.rawValue))")

        do {
            let mountPoint = try await ext4FuseController.mount(bsdName: bsdName, volumeName: volumeName)

            updateState(for: bsdName, state: .mounted(path: mountPoint, readOnly: true)) // Always read-only for ext4fuse
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .success(mountPoint: mountPoint.path), readOnly: true)

            SafetyGuard.auditLog("ext4fuse mount successful: \(bsdName) at \(mountPoint.path)")
        } catch {
            updateState(for: bsdName, state: .failed(error.localizedDescription))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .mount, result: .failure(error: error.localizedDescription), readOnly: true)
            throw error
        }
    }

    /// Check if a volume is mounted via FUSE
    func isFuseMounted(bsdName: String) async -> Bool {
        return await ext4FuseController.isFuseMounted(bsdName: bsdName)
    }

    /// Unmount a volume
    func unmount(bsdName: String, volumeName: String? = nil, force: Bool = false) async throws {
        SafetyGuard.auditLog("Unmount requested: \(bsdName), force: \(force)")

        // Check if this is a FUSE-mounted volume
        if await ext4FuseController.isFuseMounted(bsdName: bsdName) {
            try await unmountFuseVolume(bsdName: bsdName, volumeName: volumeName)
            return
        }

        guard let session = session else {
            throw MountError.sessionCreationFailed
        }

        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .unmount, result: .failure(error: "Disk not found"), readOnly: true)
            throw MountError.diskNotFound(bsdName: bsdName)
        }

        updateState(for: bsdName, state: .unmounting)

        do {
            try await performUnmount(disk: disk, force: force)

            updateState(for: bsdName, state: .unmounted)
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .unmount, result: .success(mountPoint: nil), readOnly: true)

            SafetyGuard.auditLog("Unmount successful: \(bsdName)")
        } catch {
            // Reset state to mounted (since unmount failed)
            updateState(for: bsdName, state: .failed(error.localizedDescription))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .unmount, result: .failure(error: error.localizedDescription), readOnly: true)
            throw error
        }
    }

    /// Unmount a FUSE-mounted volume
    private func unmountFuseVolume(bsdName: String, volumeName: String?) async throws {
        SafetyGuard.auditLog("Unmounting FUSE volume: \(bsdName)")

        updateState(for: bsdName, state: .unmounting)

        do {
            try await ext4FuseController.unmount(bsdName: bsdName)

            updateState(for: bsdName, state: .unmounted)
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .unmount, result: .success(mountPoint: nil), readOnly: true)

            SafetyGuard.auditLog("FUSE unmount successful: \(bsdName)")
        } catch {
            updateState(for: bsdName, state: .failed(error.localizedDescription))
            recordMountAttempt(bsdName: bsdName, volumeName: volumeName, action: .unmount, result: .failure(error: error.localizedDescription), readOnly: true)
            throw error
        }
    }

    // MARK: - Private Methods

    private func performMount(disk: DADisk, readOnly: Bool) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            // Build mount options
            let options = DADiskMountOptions(kDADiskMountOptionDefault)

            // Create mount arguments for read-only if needed
            if readOnly {
                // DADiskMountWithArguments expects a NULL-terminated array of CFString
                let rdonly = "rdonly" as CFString
                var arguments: [Unmanaged<CFString>?] = [Unmanaged.passUnretained(rdonly), nil]

                arguments.withUnsafeMutableBufferPointer { buffer in
                    DADiskMountWithArguments(
                        disk,
                        nil, // Default mount point
                        options,
                        mountCallback,
                        Unmanaged.passRetained(MountContinuation(continuation: continuation)).toOpaque(),
                        buffer.baseAddress
                    )
                }
            } else {
                DADiskMount(
                    disk,
                    nil,
                    options,
                    mountCallback,
                    Unmanaged.passRetained(MountContinuation(continuation: continuation)).toOpaque()
                )
            }
        }
    }


    private func performUnmount(disk: DADisk, force: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = force ?
                DADiskUnmountOptions(kDADiskUnmountOptionForce) :
                DADiskUnmountOptions(kDADiskUnmountOptionDefault)

            DADiskUnmount(
                disk,
                options,
                { disk, dissenter, context in
                    guard let context = context else { return }
                    let unmountContext = Unmanaged<UnmountContinuation>.fromOpaque(context).takeRetainedValue()

                    if let dissenter = dissenter {
                        let status = DADissenterGetStatus(dissenter)
                        let statusString = DADissenterGetStatusString(dissenter) as String?
                        let error = translateDAError(status: status, statusString: statusString, isUnmount: true)
                        unmountContext.continuation.resume(throwing: error)
                    } else {
                        unmountContext.continuation.resume()
                    }
                },
                Unmanaged.passRetained(UnmountContinuation(continuation: continuation)).toOpaque()
            )
        }
    }

    // MARK: - State Management

    private func updateState(for bsdName: String, state: MountState) {
        mountStates[bsdName] = state
    }

    private func recordMountAttempt(bsdName: String, volumeName: String?, action: MountAction, result: MountAttemptResult, readOnly: Bool) {
        let attempt = MountAttempt(
            bsdName: bsdName,
            volumeName: volumeName,
            action: action,
            result: result,
            readOnly: readOnly
        )
        mountAttempts.insert(attempt, at: 0)

        // Keep only last 50 attempts
        if mountAttempts.count > 50 {
            mountAttempts = Array(mountAttempts.prefix(50))
        }
    }

}

// MARK: - Standalone Functions

/// Translate DiskArbitration error codes to MountError
private func translateDAError(status: DAReturn, statusString: String?, isUnmount: Bool = false) -> MountError {
    // DAReturn is Int32; use bitPattern to convert to UInt32 for comparison with hex constants
    let statusValue = UInt32(bitPattern: status)

    switch statusValue {
    case 0xF8DA0002: // kDAReturnBusy
        return isUnmount ? .unmountFailed(Int32(bitPattern: statusValue), "Disk is busy") : .alreadyMounted
    case 0xF8DA0004: // kDAReturnExclusiveAccess
        return .exclusiveAccess
    case 0xF8DA0008: // kDAReturnNotPermitted
        return .notPermitted
    case 0xF8DA0009: // kDAReturnNotPrivileged
        return .notPrivileged
    case 0xF8DA000C: // kDAReturnUnsupported
        return .unsupportedFilesystem(statusString)
    default:
        let errorCode = Int32(bitPattern: statusValue)
        if isUnmount {
            return .unmountFailed(errorCode, statusString)
        } else {
            return .mountFailed(errorCode, statusString)
        }
    }
}

/// File-level callback function for DADiskMount (cannot use closures that capture Self)
private func mountCallback(disk: DADisk?, dissenter: DADissenter?, context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    let mountContext = Unmanaged<MountContinuation>.fromOpaque(context).takeRetainedValue()

    if let dissenter = dissenter {
        let status = DADissenterGetStatus(dissenter)
        let statusString = DADissenterGetStatusString(dissenter) as String?
        let error = translateDAError(status: status, statusString: statusString)
        mountContext.continuation.resume(throwing: error)
    } else {
        // Get mount point from disk description
        var mountPoint: URL? = nil
        if let disk = disk,
           let description = DADiskCopyDescription(disk) as? [String: Any] {
            mountPoint = description[kDADiskDescriptionVolumePathKey as String] as? URL
        }
        mountContext.continuation.resume(returning: mountPoint)
    }
}

// MARK: - Continuation Wrappers

private final class MountContinuation {
    let continuation: CheckedContinuation<URL?, Error>

    init(continuation: CheckedContinuation<URL?, Error>) {
        self.continuation = continuation
    }
}

private final class UnmountContinuation {
    let continuation: CheckedContinuation<Void, Error>

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }
}
