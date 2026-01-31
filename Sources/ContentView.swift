//
//  ContentView.swift
//  DroboBridge
//
//  Main content view with tab navigation
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @State private var selectedTab: AppTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewTab()
                .tabItem {
                    Label("Overview", systemImage: "house")
                }
                .tag(AppTab.overview)

            MountTab()
                .tabItem {
                    Label("Volumes", systemImage: "externaldrive")
                }
                .tag(AppTab.mount)

            FileBrowserTab()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(AppTab.files)

            DiagnosticsTab()
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                .tag(AppTab.diagnostics)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await coordinator.startMonitoring()
        }
        .alert("Error", isPresented: $coordinator.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(coordinator.errorMessage ?? "An unknown error occurred")
        }
    }
}

enum AppTab: Hashable {
    case overview
    case mount
    case files
    case diagnostics
}

#Preview {
    ContentView()
        .environmentObject(DroboStorageCoordinator())
}
