//
//  DroboBridgeApp.swift
//  DroboBridge
//
//  macOS app for diagnosing and mounting Drobo DAS devices
//

import SwiftUI

@main
struct DroboBridgeApp: App {
    @StateObject private var coordinator = DroboStorageCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Diagnostics") {
                Button("Run Diagnostics") {
                    Task {
                        await coordinator.runDiagnostics()
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Divider()

                Button("Export Diagnostics...") {
                    coordinator.showExportDialog = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandMenu("Devices") {
                Button("Refresh Devices") {
                    Task {
                        await coordinator.refreshDevices()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Mount All Volumes") {
                    Task {
                        await coordinator.mountAllVolumes()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Unmount All Volumes") {
                    Task {
                        await coordinator.unmountAllVolumes()
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}
