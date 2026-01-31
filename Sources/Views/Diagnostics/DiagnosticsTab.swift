//
//  DiagnosticsTab.swift
//  DroboBridge
//
//  Diagnostics tab showing raw and parsed diagnostic outputs
//

import SwiftUI

struct DiagnosticsTab: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @State private var selectedOutputType: DiagnosticOutputType = .issues
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            DiagnosticsToolbar(
                selectedType: $selectedOutputType,
                isRunning: coordinator.isRunningDiagnostics,
                onRunDiagnostics: {
                    Task {
                        await coordinator.runDiagnostics()
                    }
                },
                onExport: exportDiagnostics
            )

            Divider()

            // Content
            if let data = coordinator.diagnosticsData {
                Group {
                    switch selectedOutputType {
                    case .issues:
                        IssuesListView(issues: data.issues)
                    case .diskutil:
                        DiskutilOutputView(data: data)
                    case .logs:
                        LogsOutputView(logs: data.systemLogs)
                    case .raw:
                        RawOutputView(data: data)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyDiagnosticsView()
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.folder]
        panel.nameFieldStringValue = "DroboBridge_Diagnostics"
        panel.canCreateDirectories = true
        panel.title = "Export Diagnostics"
        panel.message = "Choose a location to save the diagnostics bundle"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                isExporting = true
                Task {
                    do {
                        let exportedURL = try await coordinator.exportDiagnostics(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                    } catch {
                        // Handle error
                    }
                    isExporting = false
                }
            }
        }
    }
}

enum DiagnosticOutputType: String, CaseIterable {
    case issues = "Issues"
    case diskutil = "Disk Info"
    case logs = "System Logs"
    case raw = "Raw Output"
}

// MARK: - Diagnostics Toolbar

struct DiagnosticsToolbar: View {
    @Binding var selectedType: DiagnosticOutputType
    let isRunning: Bool
    let onRunDiagnostics: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack {
            Picker("Output Type", selection: $selectedType) {
                ForEach(DiagnosticOutputType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            Button {
                onRunDiagnostics()
            } label: {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("Run Diagnostics", systemImage: "play.fill")
                }
            }
            .disabled(isRunning)

            Button {
                onExport()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .padding()
    }
}

// MARK: - Empty State

struct EmptyDiagnosticsView: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "stethoscope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Diagnostics")
                .font(.title2.bold())
            Text("Run diagnostics to collect information about your Drobo device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Run Diagnostics") {
                Task {
                    await coordinator.runDiagnostics()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Issues List View

struct IssuesListView: View {
    let issues: [DiagnosticIssue]

    var body: some View {
        if issues.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("No Issues Found")
                    .font(.title2.bold())
                Text("No problems were detected with your device.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(issues) { issue in
                IssueRow(issue: issue)
            }
        }
    }
}

struct IssueRow: View {
    let issue: DiagnosticIssue
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(issue.description)
                    .font(.callout)

                if !issue.recommendation.isEmpty {
                    Divider()
                    Text("Recommendation:")
                        .font(.caption.bold())
                    Text(issue.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let device = issue.affectedDevice {
                    HStack {
                        Text("Affected: \(device)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: issue.severity.systemImage)
                    .foregroundColor(issue.severity.color)

                Image(systemName: issue.category.systemImage)
                    .foregroundStyle(.secondary)

                Text(issue.title)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Diskutil Output View

struct DiskutilOutputView: View {
    let data: DiagnosticsData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let list = data.diskutilList {
                    GroupBox("Disks Overview") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Whole Disks: \(list.wholeDisks.joined(separator: ", "))")
                            Text("All Disks: \(list.allDisks.count) total")
                            Text("Volumes: \(list.volumesFromDisks.joined(separator: ", "))")
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                    }
                }

                ForEach(Array(data.diskutilInfo.keys.sorted()), id: \.self) { bsdName in
                    if let info = data.diskutilInfo[bsdName] {
                        DiskInfoCard(bsdName: bsdName, info: info)
                    }
                }
            }
            .padding()
        }
    }
}

struct DiskInfoCard: View {
    let bsdName: String
    let info: DiskutilInfoOutput

    var body: some View {
        GroupBox(bsdName) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Device").foregroundStyle(.secondary)
                    Text(info.deviceNode)
                }
                GridRow {
                    Text("Protocol").foregroundStyle(.secondary)
                    Text(info.busProtocol ?? "Unknown")
                }
                if let fsType = info.filesystemType {
                    GridRow {
                        Text("Filesystem").foregroundStyle(.secondary)
                        Text(fsType)
                    }
                }
                if let volumeName = info.volumeName {
                    GridRow {
                        Text("Volume Name").foregroundStyle(.secondary)
                        Text(volumeName)
                    }
                }
                if let mountPoint = info.mountPoint, !mountPoint.isEmpty {
                    GridRow {
                        Text("Mount Point").foregroundStyle(.secondary)
                        Text(mountPoint)
                    }
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))
                }
                GridRow {
                    Text("Mountable").foregroundStyle(.secondary)
                    Text(info.isMountable ? "Yes" : "No")
                }
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding()
        }
    }
}

// MARK: - Logs Output View

struct LogsOutputView: View {
    let logs: [LogEntry]

    var body: some View {
        if logs.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Logs")
                    .font(.title2.bold())
                Text("No relevant system logs were found.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let subsystem = log.subsystem {
                            Text(subsystem)
                                .font(.caption.bold())
                        }
                    }

                    Text(log.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Raw Output View

struct RawOutputView: View {
    let data: DiagnosticsData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let rawList = data.rawDiskutilListOutput {
                    GroupBox("diskutil list") {
                        Text(rawList)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }

                ForEach(Array(data.rawDiskutilInfoOutputs.keys.sorted()), id: \.self) { bsdName in
                    if let rawInfo = data.rawDiskutilInfoOutputs[bsdName] {
                        GroupBox("diskutil info \(bsdName)") {
                            Text(rawInfo)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    DiagnosticsTab()
        .environmentObject(DroboStorageCoordinator())
        .frame(width: 800, height: 600)
}
