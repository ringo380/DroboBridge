//
//  MountTab.swift
//  DroboBridge
//
//  Mount tab for volume management
//

import SwiftUI

struct MountTab: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @State private var selectedVolume: VolumeInfo?

    var body: some View {
        HSplitView {
            // Left: Volumes list
            VolumesListView(
                device: coordinator.selectedDevice,
                selection: $selectedVolume
            )
            .frame(minWidth: 250, maxWidth: 350)

            // Right: Details and actions
            VStack(spacing: 0) {
                if let volume = selectedVolume {
                    VolumeDetailView(volume: volume)
                } else {
                    EmptyVolumeSelectionView()
                }

                Divider()

                // Mount attempt log
                MountAttemptLogView(attempts: coordinator.mountAttempts)
                    .frame(minHeight: 150, maxHeight: 200)
            }
        }
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Mount mode toggle (only shown when Paragon is available)
                if coordinator.canMountReadWrite {
                    MountModeToggle(preferReadWrite: $coordinator.preferReadWriteMount)
                }

                Button {
                    Task {
                        await coordinator.mountAllVolumes()
                    }
                } label: {
                    Label("Mount All", systemImage: "externaldrive.badge.plus")
                }
                .disabled(coordinator.selectedDevice?.unmountedVolumes.isEmpty ?? true)

                Button {
                    Task {
                        await coordinator.unmountAllVolumes()
                    }
                } label: {
                    Label("Unmount All", systemImage: "externaldrive.badge.minus")
                }
                .disabled(coordinator.selectedDevice?.mountedVolumes.isEmpty ?? true)
            }
        }
        .sheet(isPresented: $coordinator.showFuseInstallPrompt) {
            FuseInstallationSheet()
                .environmentObject(coordinator)
        }
    }
}

// MARK: - Mount Mode Toggle

struct MountModeToggle: View {
    @Binding var preferReadWrite: Bool

    var body: some View {
        Menu {
            Button {
                preferReadWrite = false
            } label: {
                Label("Read-Only (Safe)", systemImage: preferReadWrite ? "" : "checkmark")
            }

            Button {
                preferReadWrite = true
            } label: {
                Label("Read-Write", systemImage: preferReadWrite ? "checkmark" : "")
            }
        } label: {
            Label(
                preferReadWrite ? "Read-Write" : "Read-Only",
                systemImage: preferReadWrite ? "pencil.circle.fill" : "lock.circle.fill"
            )
        }
        .help(preferReadWrite ? "Volumes will be mounted with write access" : "Volumes will be mounted read-only (safer)")
    }
}

// MARK: - FUSE Installation Sheet

struct FuseInstallationSheet: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Linux Filesystem Detected")
                    .font(.title2.bold())

                Text("Your Drobo uses a Linux filesystem (ext3/ext4) which macOS cannot mount natively.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            Divider()

            // Current status
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Linux Filesystem Support")
                            .font(.headline)

                        // Paragon status (preferred)
                        HStack {
                            Image(systemName: coordinator.paragonAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(coordinator.paragonAvailable ? .green : .red)
                            Text(coordinator.paragonAvailable ? "Paragon extFS installed (Read-Write)" : "Paragon extFS not installed")
                        }

                        // FUSE/ext4fuse status (fallback)
                        HStack {
                            Image(systemName: coordinator.fuseType != .none ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(coordinator.fuseType != .none ? .green : .red)
                            Text(coordinator.fuseType.description)
                        }

                        HStack {
                            Image(systemName: coordinator.ext4FuseAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(coordinator.ext4FuseAvailable ? .green : .red)
                            Text(coordinator.ext4FuseAvailable ? "ext4fuse installed (Read-Only)" : "ext4fuse not installed")
                        }

                        // Best available driver summary
                        Divider()
                        HStack {
                            Image(systemName: coordinator.linuxFilesystemDriver != .none ? "externaldrive.fill" : "externaldrive.trianglebadge.exclamationmark")
                                .foregroundColor(coordinator.linuxFilesystemDriver != .none ? .blue : .orange)
                            Text("Active: \(coordinator.linuxFilesystemDriver.description)")
                                .fontWeight(.medium)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Installation options
            GroupBox("Installation Options") {
                VStack(alignment: .leading, spacing: 16) {
                    // Option 1: Homebrew
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "terminal")
                                .foregroundColor(.blue)
                            Text("Option 1: Homebrew (Free, Read-Only)")
                                .fontWeight(.medium)
                        }

                        Text("Install macFUSE and ext4fuse via Homebrew. Requires kernel extension approval on Apple Silicon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            coordinator.openTerminalWithHomebrewCommand()
                        } label: {
                            Label("Open Terminal with Command", systemImage: "terminal.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Option 2: Paragon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(.green)
                            Text("Option 2: Paragon extFS ($39, Read-Write)")
                                .fontWeight(.medium)
                        }

                        Text("Commercial solution with full read-write support. No kernel extension required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            coordinator.openInBrowser(coordinator.paragonExtFSURL)
                        } label: {
                            Label("Visit Paragon Website", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // More Info
                    Button {
                        coordinator.openInBrowser(coordinator.ext4FuseGuideURL)
                    } label: {
                        Label("View Detailed Guide", systemImage: "book")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 8)
            }

            Spacer()

            // Dismiss button
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 500, height: 550)
    }
}

// MARK: - Volumes List View

struct VolumesListView: View {
    let device: CorrelatedStorageDevice?
    @Binding var selection: VolumeInfo?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Volumes")
                    .font(.headline)
                Spacer()
                if let device = device {
                    Text("\(device.volumes.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding()

            Divider()

            // List
            if let device = device, !device.volumes.isEmpty {
                List(device.volumes, selection: $selection) { volume in
                    VolumeRow(volume: volume)
                        .tag(volume)
                }
                .listStyle(.inset)
            } else if device != nil {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Volumes")
                        .font(.title2.bold())
                    Text("No volumes detected on this device.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Device")
                        .font(.title2.bold())
                    Text("Connect a Drobo device to see volumes.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Volume Row

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        HStack {
            // Icon (color indicates mount mode)
            Image(systemName: volume.isMounted ? "externaldrive.fill" : "externaldrive")
                .foregroundColor(volume.isMounted ? (volume.isReadWrite ? .blue : .green) : .secondary)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(volume.displayName)
                        .fontWeight(.medium)

                    // Read-write indicator
                    if volume.isMounted {
                        Text(volume.isReadWrite ? "R/W" : "R/O")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(volume.isReadWrite ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(volume.isReadWrite ? .blue : .green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 8) {
                    Text(volume.bsdName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let fsType = volume.filesystemType {
                        Text(fsType)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            // Status badge
            if volume.isMounted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(volume.isReadWrite ? .blue : .green)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Volume Detail View

struct VolumeDetailView: View {
    let volume: VolumeInfo
    @EnvironmentObject var coordinator: DroboStorageCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: volume.isMounted ? "externaldrive.fill" : "externaldrive")
                        .font(.largeTitle)
                        .foregroundColor(volume.isMounted ? (volume.isReadWrite ? .blue : .green) : .secondary)

                    VStack(alignment: .leading) {
                        HStack(spacing: 8) {
                            Text(volume.displayName)
                                .font(.title2.bold())

                            // Read-write badge
                            if volume.isMounted {
                                Text(volume.isReadWrite ? "R/W" : "R/O")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(volume.isReadWrite ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                                    .foregroundColor(volume.isReadWrite ? .blue : .green)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Text(volume.bsdName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mount/Unmount buttons
                    if volume.isMounted {
                        Button {
                            Task {
                                await coordinator.unmountVolume(volume)
                            }
                        } label: {
                            Label("Unmount", systemImage: "eject")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        // Show mount options based on available drivers
                        HStack(spacing: 8) {
                            if coordinator.canMountReadWrite {
                                Button {
                                    Task {
                                        await coordinator.mountVolume(volume, readOnly: false)
                                    }
                                } label: {
                                    Label("Mount R/W", systemImage: "pencil.circle")
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                Task {
                                    await coordinator.mountVolume(volume, readOnly: true)
                                }
                            } label: {
                                Label(coordinator.canMountReadWrite ? "Mount R/O" : "Mount (Read-Only)", systemImage: "lock.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()

                Divider()

                // Details
                GroupBox("Volume Information") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Device Path")
                                .foregroundStyle(.secondary)
                            Text(volume.devicePath)
                                .textSelection(.enabled)
                        }

                        if let fsType = volume.filesystemType {
                            GridRow {
                                Text("Filesystem")
                                    .foregroundStyle(.secondary)
                                Text(fsType)
                            }
                        }

                        GridRow {
                            Text("Size")
                                .foregroundStyle(.secondary)
                            Text(volume.formattedSize)
                        }

                        if let freeSpace = volume.formattedFreeSpace {
                            GridRow {
                                Text("Free Space")
                                    .foregroundStyle(.secondary)
                                Text(freeSpace)
                            }
                        }

                        if let uuid = volume.volumeUUID {
                            GridRow {
                                Text("UUID")
                                    .foregroundStyle(.secondary)
                                Text(uuid)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        GridRow {
                            Text("Status")
                                .foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: volume.isMounted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(volume.isMounted ? .green : .secondary)
                                Text(volume.isMounted ? "Mounted" : "Unmounted")
                            }
                        }

                        if let mountPoint = volume.mountPoint {
                            GridRow {
                                Text("Mount Point")
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(mountPoint.path)
                                        .textSelection(.enabled)

                                    Button {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPoint.path)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)

                // Capacity bar (if mounted)
                if volume.isMounted, let percentage = volume.usedPercentage {
                    GroupBox("Storage Usage") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: percentage, total: 100)
                                .tint(percentage > 90 ? .red : percentage > 75 ? .orange : .blue)

                            HStack {
                                Text("\(Int(percentage))% used")
                                Spacer()
                                if let free = volume.formattedFreeSpace {
                                    Text("\(free) available")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Empty Selection View

struct EmptyVolumeSelectionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a Volume")
                .font(.title2.bold())
            Text("Select a volume from the list to view details and mount options.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mount Attempt Log View

struct MountAttemptLogView: View {
    let attempts: [MountAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mount Log")
                    .font(.headline)
                Spacer()
                if !attempts.isEmpty {
                    Text("\(attempts.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if attempts.isEmpty {
                Text("No mount operations recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(attempts) { attempt in
                    MountAttemptRow(attempt: attempt)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct MountAttemptRow: View {
    let attempt: MountAttempt

    var body: some View {
        HStack {
            Image(systemName: attempt.result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(attempt.result.isSuccess ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(attempt.action.rawValue)
                        .fontWeight(.medium)

                    Text(attempt.volumeName ?? attempt.bsdName)
                        .foregroundStyle(.secondary)

                    if attempt.readOnly {
                        Text("(RO)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)

                Text(attempt.result.displayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(attempt.formattedTimestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    MountTab()
        .environmentObject(DroboStorageCoordinator())
        .frame(width: 900, height: 600)
}
