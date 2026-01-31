//
//  CapacityBreakdownView.swift
//  DroboBridge
//
//  Pie/donut chart visualization for storage capacity
//

import SwiftUI

// MARK: - Capacity Breakdown View

struct CapacityBreakdownView: View {
    let device: CorrelatedStorageDevice

    private var segments: [CapacitySegment] {
        var result: [CapacitySegment] = []

        // Add volumes as segments
        for (index, volume) in device.volumes.enumerated() {
            let usedSpace: UInt64
            if let free = volume.freeSpace {
                usedSpace = volume.size > free ? volume.size - free : 0
            } else {
                usedSpace = volume.isMounted ? volume.size / 2 : 0 // Estimate if not mounted
            }

            if usedSpace > 0 {
                result.append(CapacitySegment(
                    id: "used-\(volume.bsdName)",
                    label: "\(volume.displayName) (Used)",
                    value: usedSpace,
                    color: segmentColor(for: index, isUsed: true)
                ))
            }

            if let free = volume.freeSpace, free > 0 {
                result.append(CapacitySegment(
                    id: "free-\(volume.bsdName)",
                    label: "\(volume.displayName) (Free)",
                    value: free,
                    color: segmentColor(for: index, isUsed: false)
                ))
            }
        }

        return result
    }

    private func segmentColor(for index: Int, isUsed: Bool) -> Color {
        let baseColors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let baseColor = baseColors[index % baseColors.count]
        return isUsed ? baseColor : baseColor.opacity(0.3)
    }

    var body: some View {
        GroupBox {
            HStack(spacing: 24) {
                // Pie chart
                DonutChart(segments: segments)
                    .frame(width: 150, height: 150)

                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(segments) { segment in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 12, height: 12)

                            Text(segment.label)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text(segment.formattedValue)
                                .font(.caption.bold())
                        }
                    }

                    if segments.isEmpty {
                        Text("No storage data available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        } label: {
            Label("Capacity Breakdown", systemImage: "chart.pie.fill")
        }
    }
}

// MARK: - Capacity Segment

struct CapacitySegment: Identifiable {
    let id: String
    let label: String
    let value: UInt64
    let color: Color

    var formattedValue: String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

// MARK: - Donut Chart

struct DonutChart: View {
    let segments: [CapacitySegment]

    private var total: Double {
        Double(segments.reduce(0) { $0 + $1.value })
    }

    private var angles: [(segment: CapacitySegment, startAngle: Double, endAngle: Double)] {
        var result: [(CapacitySegment, Double, Double)] = []
        var currentAngle: Double = -90 // Start from top

        for segment in segments {
            let proportion = total > 0 ? Double(segment.value) / total : 0
            let sweepAngle = proportion * 360
            result.append((segment, currentAngle, currentAngle + sweepAngle))
            currentAngle += sweepAngle
        }

        return result
    }

    var body: some View {
        ZStack {
            // Draw segments
            ForEach(angles, id: \.segment.id) { item in
                DonutSegment(
                    startAngle: .degrees(item.startAngle),
                    endAngle: .degrees(item.endAngle)
                )
                .fill(item.segment.color)
            }

            // Center cutout
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 70, height: 70)

            // Center label
            VStack(spacing: 2) {
                Text(formatTotal())
                    .font(.caption.bold())
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTotal() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }
}

// MARK: - Donut Segment Shape

struct DonutSegment: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.6

        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // Line to inner arc
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()

        return path
    }
}

#Preview {
    CapacityBreakdownView(device: CorrelatedStorageDevice(
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
            BlockDevice(bsdName: "disk4", size: 4_000_000_000_000, isWhole: true)
        ],
        volumes: [
            VolumeInfo(
                bsdName: "disk4s1",
                volumeName: "Drobo Main",
                mountPoint: URL(fileURLWithPath: "/Volumes/Drobo"),
                isMounted: true,
                filesystemType: "ext4",
                size: 2_200_000_000_000,
                freeSpace: 800_000_000_000,
                isReadWrite: true
            ),
            VolumeInfo(
                bsdName: "disk4s2",
                volumeName: "Drobo Backup",
                mountPoint: URL(fileURLWithPath: "/Volumes/Backup"),
                isMounted: true,
                filesystemType: "msdos",
                size: 1_800_000_000_000,
                freeSpace: 1_200_000_000_000,
                isReadWrite: false
            )
        ],
        visibilityState: .mounted
    ))
    .padding()
    .frame(width: 500)
}
