//
//  StorageVisualizationView.swift
//  DroboBridge
//
//  Main storage visualization component
//

import SwiftUI

// MARK: - Storage Visualization View

struct StorageVisualizationView: View {
    let device: CorrelatedStorageDevice

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Capacity overview
                CapacityOverview(device: device)

                Divider()

                // Volume breakdown
                if !device.volumes.isEmpty {
                    VolumeBreakdownView(volumes: device.volumes)
                }
            }
            .padding()
        } label: {
            Label("Storage Overview", systemImage: "chart.pie")
        }
    }
}

// MARK: - Capacity Overview

struct CapacityOverview: View {
    let device: CorrelatedStorageDevice

    private var totalCapacity: UInt64 {
        device.totalCapacity
    }

    private var usedSpace: UInt64 {
        if let free = device.totalFreeSpace {
            return totalCapacity > free ? totalCapacity - free : 0
        }
        // If no free space info available, estimate from mounted volumes
        let volumesSize = device.volumes.reduce(0) { $0 + $1.size }
        return volumesSize
    }

    private var freeSpace: UInt64 {
        device.totalFreeSpace ?? 0
    }

    private var usedPercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(totalCapacity) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title with total capacity
            HStack {
                Text("Total Capacity")
                    .font(.headline)
                Spacer()
                Text(formatBytes(totalCapacity))
                    .font(.title3.bold())
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))

                    // Used space
                    RoundedRectangle(cornerRadius: 8)
                        .fill(usedPercentageColor)
                        .frame(width: geometry.size.width * min(CGFloat(usedPercentage) / 100, 1.0))
                }
            }
            .frame(height: 24)

            // Legend
            HStack(spacing: 24) {
                LegendItem(color: usedPercentageColor, label: "Used", value: formatBytes(usedSpace))
                LegendItem(color: Color(nsColor: .tertiaryLabelColor), label: "Free", value: formatBytes(freeSpace))
                Spacer()
                Text("\(Int(usedPercentage))% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usedPercentageColor: Color {
        if usedPercentage >= 90 {
            return .red
        } else if usedPercentage >= 75 {
            return .orange
        }
        return .blue
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }
}

// MARK: - Volume Breakdown View

struct VolumeBreakdownView: View {
    let volumes: [VolumeInfo]

    private var sortedVolumes: [VolumeInfo] {
        volumes.sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volumes")
                .font(.headline)

            ForEach(sortedVolumes) { volume in
                VolumeBarView(volume: volume)
            }
        }
    }
}

// MARK: - Volume Bar View

struct VolumeBarView: View {
    let volume: VolumeInfo

    private var usedPercentage: Double {
        volume.usedPercentage ?? 0
    }

    private var statusColor: Color {
        if !volume.isMounted {
            return .gray
        }
        if usedPercentage >= 90 {
            return .red
        } else if usedPercentage >= 75 {
            return .orange
        }
        return volume.isReadWrite ? .blue : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Volume header
            HStack {
                Image(systemName: volume.isMounted ? "externaldrive.fill" : "externaldrive")
                    .foregroundColor(statusColor)

                Text(volume.displayName)
                    .fontWeight(.medium)

                if volume.isMounted {
                    Text(volume.isReadWrite ? "R/W" : "R/O")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(volume.isReadWrite ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(volume.isReadWrite ? .blue : .green)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if let fsType = volume.filesystemType {
                    Text(fsType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(volume.formattedSize)
                    .font(.caption.bold())
            }

            // Progress bar (only if mounted)
            if volume.isMounted, volume.usedPercentage != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor)
                            .frame(width: geometry.size.width * min(CGFloat(usedPercentage) / 100, 1.0))
                    }
                }
                .frame(height: 8)

                // Usage text
                HStack {
                    if let free = volume.formattedFreeSpace {
                        Text("\(free) available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(usedPercentage))% used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !volume.isMounted {
                Text("Not mounted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    StorageVisualizationView(device: CorrelatedStorageDevice(
        usbDevice: USBDevice(
            registryEntryID: 1,
            vendorID: 0x1B45,
            productID: 0x0001,
            serialNumber: "ABC123",
            locationID: 0x14100000,
            vendorName: "Data Robotics Inc.",
            productName: "Drobo",
            deviceClass: 0,
            deviceSubClass: 0,
            deviceProtocol: 0,
            speed: .high
        ),
        blockDevices: [
            BlockDevice(bsdName: "disk4", size: 2_200_000_000_000, isWhole: true)
        ],
        volumes: [
            VolumeInfo(
                bsdName: "disk4s1",
                volumeName: "Drobo",
                mountPoint: URL(fileURLWithPath: "/Volumes/Drobo"),
                isMounted: true,
                filesystemType: "ext4",
                size: 2_200_000_000_000,
                freeSpace: 800_000_000_000,
                isReadWrite: true
            )
        ],
        visibilityState: .mounted
    ))
    .padding()
    .frame(width: 500)
}
