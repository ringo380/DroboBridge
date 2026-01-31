//
//  DroboStorageCoordinator.swift
//  DroboBridge
//
//  Central state coordinator for the application
//

import Foundation
import Combine
import AppKit

// MARK: - Drobo Storage Coordinator

/// Central coordinator managing all state and services
@MainActor
final class DroboStorageCoordinator: ObservableObject {

    // MARK: - Published State

    // Connection state
    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published private(set) var correlatedDevices: [CorrelatedStorageDevice] = []
    @Published var selectedDevice: CorrelatedStorageDevice?

    // Diagnostics state
    @Published private(set) var diagnosticsData: DiagnosticsData?
    @Published private(set) var isRunningDiagnostics: Bool = false

    // Mount state
    @Published private(set) var mountAttempts: [MountAttempt] = []
    @Published private(set) var ext4FuseAvailable: Bool = false
    @Published private(set) var fuseType: FuseType = .none
    @Published private(set) var paragonAvailable: Bool = false
    @Published private(set) var linuxFilesystemDriver: LinuxFilesystemDriver = .none
    @Published var showFuseInstallPrompt: Bool = false
    @Published var preferReadWriteMount: Bool = false  // User preference for mount mode

    // Warnings
    @Published private(set) var activeWarnings: [DroboWarning] = []

    // UI State
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    @Published var showExportDialog: Bool = false
    @Published var showAllUSBDevices: Bool = false

    // MARK: - Services

    private let deviceWatcher = DroboDeviceWatcher()
    private let diskCorrelator = DiskCorrelator()
    private let mountController = MountController()
    private let diagnosticsService = DiskDiagnosticsService()
    private let exporter = DiagnosticsExporter()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupBindings()

        // Add the "Initialize Disk" warning by default
        activeWarnings.append(.initializeDiskWarning)
    }

    // MARK: - Setup

    private func setupBindings() {
        // React to device additions
        deviceWatcher.deviceAddedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                Task { @MainActor in
                    await self?.handleDeviceAdded(device)
                }
            }
            .store(in: &cancellables)

        // React to device removals
        deviceWatcher.deviceRemovedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                Task { @MainActor in
                    self?.handleDeviceRemoved(device)
                }
            }
            .store(in: &cancellables)

        // Sync mount attempts from controller
        mountController.$mountAttempts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] attempts in
                self?.mountAttempts = attempts
            }
            .store(in: &cancellables)

        // Sync ext4fuse availability from controller
        mountController.$ext4FuseAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                self?.ext4FuseAvailable = available
            }
            .store(in: &cancellables)

        mountController.$fuseType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] type in
                self?.fuseType = type
            }
            .store(in: &cancellables)

        mountController.$paragonAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                self?.paragonAvailable = available
            }
            .store(in: &cancellables)

        mountController.$linuxFilesystemDriver
            .receive(on: DispatchQueue.main)
            .sink { [weak self] driver in
                self?.linuxFilesystemDriver = driver
            }
            .store(in: &cancellables)

        // Sync correlated devices
        diskCorrelator.$correlatedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.correlatedDevices = devices
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API - Lifecycle

    /// Start monitoring for devices
    func startMonitoring() async {
        connectionStatus = .searching

        do {
            try deviceWatcher.startMonitoring()
            try diskCorrelator.startMonitoring()
            try mountController.initialize()

            // Initial scan
            await refreshDevices()
        } catch {
            handleError(error)
            connectionStatus = .error(error.localizedDescription)
        }
    }

    /// Stop monitoring for devices
    func stopMonitoring() {
        deviceWatcher.stopMonitoring()
        diskCorrelator.stopMonitoring()
    }

    // MARK: - Public API - Device Operations

    /// Refresh all devices
    func refreshDevices() async {
        connectionStatus = .searching

        let devices = showAllUSBDevices ? deviceWatcher.allUSBDevices : deviceWatcher.droboDevices

        for device in devices {
            _ = await diskCorrelator.correlateDevice(device)
        }

        updateConnectionStatus()

        // Auto-select first device if none selected
        if selectedDevice == nil, let first = correlatedDevices.first {
            selectedDevice = first
        }
    }

    /// Correlate a specific USB device
    func correlateDevice(_ device: USBDevice) async {
        let correlated = await diskCorrelator.correlateDevice(device)

        // Select it if it's the first Drobo
        if device.isDrobo && selectedDevice == nil {
            selectedDevice = correlated
        }
    }

    // MARK: - Public API - Mount Operations

    /// Mount all volumes on a device
    func mountAllVolumes() async {
        guard let device = selectedDevice else { return }

        let readOnly = !preferReadWriteMount || !canMountReadWrite
        for volume in device.unmountedVolumes {
            do {
                try await mountController.mount(
                    bsdName: volume.bsdName,
                    volumeName: volume.volumeName,
                    readOnly: readOnly,
                    userConfirmed: preferReadWriteMount
                )
            } catch {
                handleError(error)
            }
        }

        // Refresh correlation
        await refreshSelectedDevice()
    }

    /// Unmount all volumes on a device
    func unmountAllVolumes() async {
        guard let device = selectedDevice else { return }

        for volume in device.mountedVolumes {
            do {
                try await mountController.unmount(bsdName: volume.bsdName, volumeName: volume.volumeName)
            } catch {
                handleError(error)
            }
        }

        // Refresh correlation
        await refreshSelectedDevice()
    }

    /// Mount a specific volume
    func mountVolume(_ volume: VolumeInfo, readOnly: Bool? = nil) async {
        let shouldBeReadOnly = readOnly ?? !preferReadWriteMount || !canMountReadWrite
        do {
            try await mountController.mount(
                bsdName: volume.bsdName,
                volumeName: volume.volumeName,
                readOnly: shouldBeReadOnly,
                userConfirmed: !shouldBeReadOnly
            )
            await refreshSelectedDevice()
        } catch {
            handleError(error)
        }
    }

    /// Check if read-write mounting is available (Paragon installed)
    var canMountReadWrite: Bool {
        paragonAvailable
    }

    /// Unmount a specific volume
    func unmountVolume(_ volume: VolumeInfo) async {
        do {
            try await mountController.unmount(bsdName: volume.bsdName, volumeName: volume.volumeName)
            await refreshSelectedDevice()
        } catch {
            handleError(error)
        }
    }

    // MARK: - Public API - Diagnostics

    /// Run diagnostics on the selected device
    func runDiagnostics() async {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        SafetyGuard.auditLog("Running diagnostics")

        var issues: [DiagnosticIssue] = []
        var diskutilList: DiskutilListOutput?
        var diskutilInfo: [String: DiskutilInfoOutput] = [:]
        var systemLogs: [LogEntry] = []
        var rawListOutput: String?
        var rawInfoOutputs: [String: String] = [:]

        // Collect diskutil list
        do {
            diskutilList = try await diagnosticsService.listAllDisks()
            rawListOutput = try await diagnosticsService.getRawDiskutilList()
        } catch {
            issues.append(DiagnosticIssue(
                severity: .warning,
                category: .configuration,
                title: "Failed to list disks",
                description: error.localizedDescription,
                recommendation: "Check system permissions"
            ))
        }

        // Collect info for each disk
        if let device = selectedDevice {
            for blockDevice in device.blockDevices {
                do {
                    let info = try await diagnosticsService.getDiskInfo(bsdName: blockDevice.bsdName)
                    diskutilInfo[blockDevice.bsdName] = info

                    let rawInfo = try await diagnosticsService.getRawDiskutilInfo(bsdName: blockDevice.bsdName)
                    rawInfoOutputs[blockDevice.bsdName] = rawInfo
                } catch {
                    // Ignore individual disk errors
                }
            }

            // Run diagnostic analysis
            let deviceIssues = await diagnosticsService.diagnose(device: device)
            issues.append(contentsOf: deviceIssues)
        }

        // Collect logs
        do {
            systemLogs = try await diagnosticsService.getAllRelevantLogs(lastMinutes: 10)
        } catch {
            // Ignore log collection errors
        }

        // Create diagnostics data
        diagnosticsData = DiagnosticsData(
            timestamp: Date(),
            device: selectedDevice,
            diskutilList: diskutilList,
            diskutilInfo: diskutilInfo,
            systemLogs: systemLogs,
            issues: issues,
            rawDiskutilListOutput: rawListOutput,
            rawDiskutilInfoOutputs: rawInfoOutputs
        )

        // Update warnings based on issues
        updateWarningsFromDiagnostics()

        SafetyGuard.auditLog("Diagnostics complete: \(issues.count) issues found")
    }

    /// Export diagnostics to a file
    func exportDiagnostics(to url: URL) async throws -> URL {
        let bundle = DiagnosticsExporter.ExportBundle(
            manifest: .create(
                droboModel: selectedDevice?.displayName,
                droboSerial: selectedDevice?.usbDevice.serialNumber,
                exportReason: "user_initiated"
            ),
            diagnosticsData: diagnosticsData,
            rawDiskutilList: diagnosticsData?.rawDiskutilListOutput,
            rawDiskutilInfo: diagnosticsData?.rawDiskutilInfoOutputs ?? [:],
            logs: diagnosticsData?.systemLogs ?? []
        )

        return try await exporter.export(bundle: bundle, to: url)
    }

    // MARK: - Public API - Warnings

    /// Dismiss a warning
    func dismissWarning(_ warning: DroboWarning) {
        if let index = activeWarnings.firstIndex(where: { $0.id == warning.id }) {
            activeWarnings[index].isDismissed = true
        }
    }

    // MARK: - Private Methods

    private func handleDeviceAdded(_ device: USBDevice) async {
        // Only auto-correlate Drobo devices or if showing all
        if device.isDrobo || showAllUSBDevices {
            await correlateDevice(device)
        }
    }

    private func handleDeviceRemoved(_ device: USBDevice) {
        diskCorrelator.removeCorrelation(for: device)

        // Clear selection if removed device was selected
        if selectedDevice?.usbDevice.registryEntryID == device.registryEntryID {
            selectedDevice = correlatedDevices.first
        }

        updateConnectionStatus()
    }

    private func refreshSelectedDevice() async {
        guard let device = selectedDevice else { return }
        selectedDevice = await diskCorrelator.refreshCorrelation(for: device.usbDevice)
    }

    private func updateConnectionStatus() {
        let droboCount = correlatedDevices.filter { $0.usbDevice.isDrobo }.count

        if droboCount > 0 {
            connectionStatus = .connected(deviceCount: droboCount)
        } else if showAllUSBDevices && !correlatedDevices.isEmpty {
            connectionStatus = .connected(deviceCount: correlatedDevices.count)
        } else {
            connectionStatus = .disconnected
        }
    }

    private func updateWarningsFromDiagnostics() {
        guard let data = diagnosticsData else { return }

        // Add warnings for critical issues
        for issue in data.issues where issue.severity >= .error {
            // Check if warning already exists
            let exists = activeWarnings.contains { $0.title == issue.title }
            if !exists {
                activeWarnings.append(DroboWarning(
                    severity: issue.severity,
                    title: issue.title,
                    message: issue.description,
                    actionLabel: nil,
                    actionIdentifier: nil
                ))
            }
        }
    }

    private func handleError(_ error: Error) {
        // Check if this is an ext4fuse-related error
        if let mountError = error as? MountError {
            switch mountError {
            case .ext4FuseNotInstalled:
                showFuseInstallPrompt = true
                return
            default:
                break
            }
        }

        errorMessage = error.localizedDescription
        showError = true
        SafetyGuard.auditLog("Error: \(error.localizedDescription)", level: .warning)
    }

    // MARK: - ext4fuse Installation Helpers

    /// Get ext4fuse installation instructions
    var ext4FuseInstallInstructions: String {
        Ext4FuseController.installationInstructions
    }

    /// Get Homebrew installation command
    var homebrewInstallCommand: String {
        Ext4FuseController.homebrewCommand
    }

    /// Get Paragon extFS URL
    var paragonExtFSURL: URL {
        Ext4FuseController.paragonURL
    }

    /// Get Jeff Geerling's guide URL
    var ext4FuseGuideURL: URL {
        Ext4FuseController.guideURL
    }

    /// Open Terminal with Homebrew installation command
    func openTerminalWithHomebrewCommand() {
        let script = """
        tell application "Terminal"
            activate
            do script "\(homebrewInstallCommand)"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                SafetyGuard.auditLog("AppleScript error: \(error)", level: .warning)
            }
        }
    }

    /// Open URL in default browser
    func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
