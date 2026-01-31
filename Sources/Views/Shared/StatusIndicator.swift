//
//  StatusIndicator.swift
//  DroboBridge
//
//  Shared UI components
//

import SwiftUI

// MARK: - Status Indicator

struct StatusIndicator: View {
    let isActive: Bool
    var activeColor: Color = .green
    var inactiveColor: Color = .gray
    var size: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(isActive ? activeColor : inactiveColor)
            .frame(width: size, height: size)
            .overlay {
                if isActive && !reduceMotion {
                    Circle()
                        .stroke(activeColor.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(0.5)
                }
            }
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isActive)
    }
}

// MARK: - Capacity Bar

struct CapacityBar: View {
    let used: UInt64
    let total: UInt64
    var height: CGFloat = 8

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    private var barColor: Color {
        if percentage > 0.9 { return .red }
        if percentage > 0.75 { return .orange }
        return .blue
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.secondary.opacity(0.2))

                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(barColor)
                    .frame(width: geometry.size.width * percentage)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Storage usage: \(Int(percentage * 100)) percent")
    }
}

// MARK: - Initialize Disk Warning View

struct InitializeDiskWarningView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("WARNING: Do Not Initialize")
                .font(.title.bold())

            Text(SafetyGuard.initializeDiskWarning)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack {
                Button("I Understand") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: 500)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .font(.headline)
            }
            .padding(32)
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .font(.headline)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    var color: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

#Preview("Components") {
    VStack(spacing: 20) {
        HStack {
            StatusIndicator(isActive: true)
            StatusIndicator(isActive: false)
        }

        CapacityBar(used: 750, total: 1000)
            .frame(width: 200)

        Badge(text: "USB 3.0", color: .green)

        InfoRow(label: "Status", value: "Connected", valueColor: .green)
            .frame(width: 200)
    }
    .padding()
}
