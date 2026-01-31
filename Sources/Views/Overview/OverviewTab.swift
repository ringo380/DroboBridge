//
//  OverviewTab.swift
//  DroboBridge
//
//  Overview tab showing connection status and quick actions
//

import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Connection Status
                ConnectionStatusCard(
                    status: coordinator.connectionStatus,
                    device: coordinator.selectedDevice
                )

                // Safety Warning Banner
                if !coordinator.activeWarnings.isEmpty {
                    WarningsSection(warnings: coordinator.activeWarnings)
                }

                // Storage Visualization (if connected)
                if let device = coordinator.selectedDevice {
                    // Storage overview with capacity bars
                    StorageVisualizationView(device: device)

                    // Drive bay visualization
                    DriveBayView(device: device, bayCount: 5)

                    // Capacity pie chart (only if mounted volumes exist)
                    if !device.mountedVolumes.isEmpty {
                        CapacityBreakdownView(device: device)
                    }

                    // Device Details
                    DeviceDetailsSection(device: device)
                }

                // Quick Actions
                QuickActionsSection()

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await coordinator.refreshDevices()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    let status: ConnectionStatus
    let device: CorrelatedStorageDevice?

    var body: some View {
        GroupBox {
            HStack(spacing: 16) {
                // Status Icon
                Image(systemName: status.systemImage)
                    .font(.system(size: 48))
                    .foregroundColor(statusColor)
                    .opacity(status == .searching ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: status == .searching)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.displayName)
                        .font(.title2.bold())

                    if let device = device {
                        Text(device.displayName)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Label(device.usbDevice.speed.shortName, systemImage: "cable.connector")
                            if let serial = device.usbDevice.serialNumber {
                                Text("•")
                                Text("S/N: \(serial)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Visibility State Badge
                if let device = device {
                    VisibilityStateBadge(state: device.visibilityState)
                }
            }
            .padding()
        } label: {
            Label("Connection Status", systemImage: "cable.connector")
        }
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .searching: return .blue
        case .connected: return .green
        case .error: return .red
        }
    }
}

// MARK: - Visibility State Badge

struct VisibilityStateBadge: View {
    let state: StorageVisibilityState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.systemImage)
            Text(state.displayName)
        }
        .font(.caption.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color.opacity(0.2))
        .foregroundColor(state.color)
        .clipShape(Capsule())
    }
}

// MARK: - Device Details Section

struct DeviceDetailsSection: View {
    let device: CorrelatedStorageDevice

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // USB Details
                DetailRow(label: "Vendor ID", value: device.usbDevice.vendorIDHex)
                DetailRow(label: "Product ID", value: device.usbDevice.productIDHex)
                DetailRow(label: "Location ID", value: device.usbDevice.locationIDHex)

                Divider()

                // Storage Details
                if let blockDevice = device.primaryBlockDevice {
                    DetailRow(label: "Block Device", value: blockDevice.devicePath)
                    DetailRow(label: "Capacity", value: blockDevice.formattedSize)
                }

                DetailRow(label: "Volumes", value: "\(device.volumes.count) (\(device.mountedVolumes.count) mounted)")
            }
            .padding()
        } label: {
            Label("Device Details", systemImage: "info.circle")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

// MARK: - Warnings Section

struct WarningsSection: View {
    let warnings: [DroboWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings.filter { !$0.isDismissed }) { warning in
                WarningCard(warning: warning)
            }
        }
    }
}

struct WarningCard: View {
    let warning: DroboWarning
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: warning.severity.systemImage)
                        .foregroundColor(warning.severity.color)

                    Text(warning.title)
                        .font(.headline)

                    Spacer()

                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    Text(warning.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        if let actionLabel = warning.actionLabel {
                            Button(actionLabel) {
                                // Handle action
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Spacer()

                        Button("Dismiss") {
                            coordinator.dismissWarning(warning)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .backgroundStyle(warning.severity.color.opacity(0.1))
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ActionButton(
                        title: "Run Diagnostics",
                        systemImage: "stethoscope",
                        isLoading: coordinator.isRunningDiagnostics
                    ) {
                        Task {
                            await coordinator.runDiagnostics()
                        }
                    }

                    ActionButton(
                        title: "Refresh Devices",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task {
                            await coordinator.refreshDevices()
                        }
                    }
                }

                HStack(spacing: 12) {
                    ActionButton(
                        title: coordinator.canMountReadWrite ?
                            (coordinator.preferReadWriteMount ? "Mount All (R/W)" : "Mount All (R/O)") :
                            "Mount All (Read-Only)",
                        systemImage: "externaldrive.badge.plus",
                        disabled: coordinator.selectedDevice?.unmountedVolumes.isEmpty ?? true
                    ) {
                        Task {
                            await coordinator.mountAllVolumes()
                        }
                    }

                    ActionButton(
                        title: "Unmount All",
                        systemImage: "externaldrive.badge.minus",
                        disabled: coordinator.selectedDevice?.mountedVolumes.isEmpty ?? true
                    ) {
                        Task {
                            await coordinator.unmountAllVolumes()
                        }
                    }
                }

                // Mount mode indicator (if Paragon available)
                if coordinator.canMountReadWrite {
                    HStack {
                        Image(systemName: coordinator.preferReadWriteMount ? "pencil.circle.fill" : "lock.circle.fill")
                            .foregroundColor(coordinator.preferReadWriteMount ? .blue : .green)
                        Text(coordinator.preferReadWriteMount ? "Read-Write mode enabled" : "Read-Only mode (safe)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $coordinator.preferReadWriteMount)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        } label: {
            Label("Quick Actions", systemImage: "bolt.fill")
        }
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled || isLoading)
    }
}

#Preview {
    OverviewTab()
        .environmentObject(DroboStorageCoordinator())
        .frame(width: 600, height: 700)
}
