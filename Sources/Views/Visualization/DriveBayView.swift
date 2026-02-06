//
//  DriveBayView.swift
//  DroboBridge
//
//  Visual representation of Drobo drive bays
//

import SwiftUI

// MARK: - Drive Bay Status

enum DriveBayStatus {
    case empty
    case present
    case warning
    case failed
    case rebuilding

    var color: Color {
        switch self {
        case .empty: return Color(nsColor: .separatorColor)
        case .present: return .green
        case .warning: return .yellow
        case .failed: return .red
        case .rebuilding: return .blue
        }
    }

    var systemImage: String {
        switch self {
        case .empty: return "rectangle.dashed"
        case .present: return "internaldrive.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .rebuilding: return "arrow.triangle.2.circlepath"
        }
    }

    var displayName: String {
        switch self {
        case .empty: return "Empty"
        case .present: return "OK"
        case .warning: return "Warning"
        case .failed: return "Failed"
        case .rebuilding: return "Rebuilding"
        }
    }
}

// MARK: - Drive Bay Model

struct DriveBay: Identifiable {
    let id: Int
    let status: DriveBayStatus
    let capacity: UInt64?
    let label: String?

    init(id: Int, status: DriveBayStatus = .empty, capacity: UInt64? = nil, label: String? = nil) {
        self.id = id
        self.status = status
        self.capacity = capacity
        self.label = label
    }

    var formattedCapacity: String? {
        guard let capacity = capacity else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file)
    }
}

// MARK: - Drive Bay View

struct DriveBayView: View {
    let device: CorrelatedStorageDevice
    let bayCount: Int

    init(device: CorrelatedStorageDevice, bayCount: Int = 5) {
        self.device = device
        self.bayCount = bayCount
    }

    private var driveBays: [DriveBay] {
        // For now, we simulate drive bays based on block devices
        // In Phase 4, this will be populated from actual Drobo protocol data
        var bays: [DriveBay] = []

        // Create bays with inferred status
        for i in 0..<bayCount {
            if i < device.partitionBlockDevices.count {
                let blockDevice = device.partitionBlockDevices[i]
                bays.append(DriveBay(
                    id: i,
                    status: .present,
                    capacity: blockDevice.size,
                    label: blockDevice.bsdName
                ))
            } else if device.visibilityState == .mounted || device.visibilityState == .volumesUnmounted {
                // Device is connected and working, remaining bays are empty
                bays.append(DriveBay(id: i, status: .empty))
            } else {
                // Unknown state
                bays.append(DriveBay(id: i, status: .empty))
            }
        }

        return bays
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                HStack {
                    Text("Drive Bays")
                        .font(.headline)
                    Spacer()
                    Text("\(driveBays.filter { $0.status != .empty }.count)/\(bayCount) occupied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Drive bay visualization
                HStack(spacing: 8) {
                    ForEach(driveBays) { bay in
                        DriveBaySlot(bay: bay)
                    }
                }

                // Legend
                DriveBayLegend()
            }
            .padding()
        } label: {
            Label("Drive Bays", systemImage: "internaldrive")
        }
    }
}

// MARK: - Drive Bay Slot

struct DriveBaySlot: View {
    let bay: DriveBay
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 4) {
            // Bay visual
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(bay.status.color.opacity(bay.status == .empty ? 0.1 : 0.2))
                    .frame(width: 60, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(bay.status.color.opacity(bay.status == .empty ? 0.5 : 1.0), lineWidth: 2)
                    )

                VStack(spacing: 8) {
                    Image(systemName: bay.status.systemImage)
                        .font(.title2)
                        .foregroundColor(bay.status.color)
                        .rotationEffect(bay.status == .rebuilding && isAnimating ? .degrees(360) : .degrees(0))
                        .animation(
                            bay.status == .rebuilding ? .linear(duration: 2).repeatForever(autoreverses: false) : .default,
                            value: isAnimating
                        )

                    if let capacity = bay.formattedCapacity {
                        Text(capacity)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Bay label
            Text("Bay \(bay.id + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if bay.status == .rebuilding {
                isAnimating = true
            }
        }
    }
}

// MARK: - Drive Bay Legend

struct DriveBayLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendBadge(status: .present, label: "OK")
            LegendBadge(status: .empty, label: "Empty")
            LegendBadge(status: .warning, label: "Warning")
            LegendBadge(status: .failed, label: "Failed")
            Spacer()
        }
    }
}

struct LegendBadge: View {
    let status: DriveBayStatus
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DriveBayView(device: CorrelatedStorageDevice(
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
            BlockDevice(bsdName: "disk4", size: 2_200_000_000_000, isWhole: true),
            BlockDevice(bsdName: "disk4s1", size: 1_100_000_000_000, isWhole: false),
            BlockDevice(bsdName: "disk4s2", size: 1_100_000_000_000, isWhole: false)
        ],
        visibilityState: .mounted
    ), bayCount: 5)
    .padding()
    .frame(width: 400)
}
