//
//  FileBrowserTab.swift
//  DroboBridge
//
//  File browser tab for viewing and managing Drobo files
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookUI

// MARK: - File Browser Tab

struct FileBrowserTab: View {
    @EnvironmentObject var coordinator: DroboStorageCoordinator
    @StateObject private var browserState = FileBrowserState()
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        HSplitView {
            // Left: Volume/folder sidebar
            FileBrowserSidebar(
                volumes: coordinator.selectedDevice?.mountedVolumes ?? [],
                selectedVolume: $browserState.selectedVolume,
                currentPath: $browserState.currentPath
            )
            .frame(minWidth: 200, maxWidth: 300)

            // Right: File list and detail
            VStack(spacing: 0) {
                // Toolbar
                FileBrowserToolbar(state: browserState, searchFieldFocused: $searchFieldFocused)

                Divider()

                // Main content
                if browserState.selectedVolume != nil {
                    HSplitView {
                        // File list
                        FileListView(state: browserState)
                            .frame(minWidth: 400)

                        // Detail panel
                        if let selectedItem = browserState.selectedItem {
                            FileDetailView(item: selectedItem, state: browserState)
                                .frame(minWidth: 250, maxWidth: 350)
                        }
                    }
                } else {
                    NoVolumeSelectedView()
                }
            }
        }
        .navigationTitle("File Browser")
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(state: browserState))
        .sheet(isPresented: $browserState.showNewFolderSheet) {
            NewFolderSheet(state: browserState)
        }
        .sheet(isPresented: $browserState.showRenameSheet) {
            RenameSheet(state: browserState)
        }
        .alert("Delete File", isPresented: $browserState.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await browserState.confirmDelete()
                }
            }
        } message: {
            if let item = browserState.itemToDelete {
                Text("Are you sure you want to delete \"\(item.name)\"? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $browserState.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(browserState.errorMessage ?? "An error occurred")
        }
        // Hidden buttons for keyboard shortcuts
        .background(
            VStack(spacing: 0) {
                // ⌘F - Focus search field
                Button("") { searchFieldFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)

                // ⌘N - New folder
                Button("") { browserState.showNewFolderSheet = true }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(browserState.selectedVolume?.isReadWrite != true)
                    .opacity(0)
                    .frame(width: 0, height: 0)

                // ⌘⌫ - Delete with confirmation
                Button("") {
                    if let item = browserState.selectedItem {
                        browserState.deleteItem(item)
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(browserState.selectedItem == nil || browserState.selectedVolume?.isReadWrite != true)
                .opacity(0)
                .frame(width: 0, height: 0)
            }
        )
    }
}

// MARK: - File Browser State

@MainActor
class FileBrowserState: ObservableObject {
    @Published var selectedVolume: VolumeInfo?
    @Published var currentPath: URL?
    @Published var items: [FileItem] = []
    @Published var selectedItem: FileItem?
    @Published var isLoading = false
    @Published var searchQuery = ""
    @Published var showHiddenFiles = false
    @Published var sortOrder: FileSortOrder = .name

    // Sheet states
    @Published var showNewFolderSheet = false
    @Published var showRenameSheet = false
    @Published var showDeleteConfirmation = false
    @Published var itemToDelete: FileItem?

    // Error handling
    @Published var showError = false
    @Published var errorMessage: String?

    // Navigation history
    @Published var navigationHistory: [URL] = []
    @Published var historyIndex = -1

    private let fileOps = FileOperationsService()

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    var canGoUp: Bool {
        guard let path = currentPath, let volume = selectedVolume, let mountPoint = volume.mountPoint else {
            return false
        }
        return path != mountPoint
    }

    var filteredItems: [FileItem] {
        var result = items

        // Filter hidden files
        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }

        // Filter by search
        if !searchQuery.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }

        // Sort
        result.sort { first, second in
            // Directories always first
            if first.isDirectory != second.isDirectory {
                return first.isDirectory
            }

            switch sortOrder {
            case .name:
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            case .size:
                return first.size > second.size
            case .date:
                return (first.modificationDate ?? .distantPast) > (second.modificationDate ?? .distantPast)
            case .kind:
                return first.fileExtension < second.fileExtension
            }
        }

        return result
    }

    // MARK: - Navigation

    func navigateTo(_ url: URL) {
        Task {
            await loadDirectory(url)
        }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let url = navigationHistory[historyIndex]
        Task {
            await loadDirectory(url, addToHistory: false)
        }
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let url = navigationHistory[historyIndex]
        Task {
            await loadDirectory(url, addToHistory: false)
        }
    }

    func goUp() {
        guard canGoUp, let path = currentPath else { return }
        navigateTo(path.deletingLastPathComponent())
    }

    func refresh() {
        guard let path = currentPath else { return }
        Task {
            await loadDirectory(path, addToHistory: false)
        }
    }

    // MARK: - Load Directory

    func loadDirectory(_ url: URL, addToHistory: Bool = true) async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await fileOps.listDirectory(at: url)
            currentPath = url
            selectedItem = nil

            if addToHistory {
                // Truncate forward history and add new URL
                if historyIndex < navigationHistory.count - 1 {
                    navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
                }
                navigationHistory.append(url)
                historyIndex = navigationHistory.count - 1
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - File Operations

    func deleteItem(_ item: FileItem) {
        itemToDelete = item
        showDeleteConfirmation = true
    }

    func confirmDelete() async {
        guard let item = itemToDelete, let volume = selectedVolume else { return }

        do {
            _ = try await fileOps.deleteItem(at: item.url, volume: volume)
            refresh()
        } catch {
            handleError(error)
        }

        itemToDelete = nil
    }

    func renameItem(_ item: FileItem, to newName: String) async {
        guard let volume = selectedVolume else { return }

        do {
            _ = try await fileOps.renameItem(at: item.url, to: newName, volume: volume)
            refresh()
        } catch {
            handleError(error)
        }
    }

    func createFolder(name: String) async {
        guard let path = currentPath, let volume = selectedVolume else { return }

        do {
            _ = try await fileOps.createFolder(at: path, name: name, volume: volume)
            refresh()
        } catch {
            handleError(error)
        }
    }

    func copyFile(from sourceURL: URL) async {
        guard let path = currentPath, let volume = selectedVolume else { return }

        do {
            _ = try await fileOps.copyItem(from: sourceURL, to: path, volume: volume)
            refresh()
        } catch {
            handleError(error)
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        SafetyGuard.auditLog("File operation error: \(error.localizedDescription)", level: .warning)
    }

    // MARK: - Quick Look

    func quickLook(_ item: FileItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
    }
}

// MARK: - File Sort Order

enum FileSortOrder: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case date = "Date"
    case kind = "Kind"
}

// MARK: - File Browser Sidebar

struct FileBrowserSidebar: View {
    let volumes: [VolumeInfo]
    @Binding var selectedVolume: VolumeInfo?
    @Binding var currentPath: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Volumes")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Volume list
            if volumes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Mounted Volumes")
                        .font(.headline)
                    Text("Mount a volume to browse files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(volumes, selection: $selectedVolume) { volume in
                    VolumeSidebarRow(volume: volume, isSelected: selectedVolume?.id == volume.id)
                        .tag(volume)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedVolume) { newVolume in
                    if let volume = newVolume, let mountPoint = volume.mountPoint {
                        currentPath = mountPoint
                    }
                }
            }
        }
    }
}

struct VolumeSidebarRow: View {
    let volume: VolumeInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .foregroundColor(volume.isReadWrite ? .blue : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.displayName)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: 4) {
                    Text(volume.isReadWrite ? "R/W" : "R/O")
                        .font(.caption2)
                        .foregroundColor(volume.isReadWrite ? .blue : .green)

                    if let free = volume.formattedFreeSpace {
                        Text("• \(free) free")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - File Browser Toolbar

struct FileBrowserToolbar: View {
    @ObservedObject var state: FileBrowserState
    @FocusState.Binding var searchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Navigation buttons
            HStack(spacing: 4) {
                Button {
                    state.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!state.canGoBack)
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    state.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!state.canGoForward)
                .keyboardShortcut("]", modifiers: .command)

                Button {
                    state.goUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!state.canGoUp)
                .keyboardShortcut(.upArrow, modifiers: .command)
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 20)

            // Current path
            if let path = state.currentPath {
                PathBreadcrumbs(path: path, volume: state.selectedVolume) { url in
                    state.navigateTo(url)
                }
            }

            Spacer()

            // Search field (⌘F to focus)
            TextField("Search", text: $state.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .focused($searchFieldFocused)

            // Actions
            Menu {
                Button {
                    state.showNewFolderSheet = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(state.selectedVolume?.isReadWrite != true)

                Divider()

                Toggle("Show Hidden Files", isOn: $state.showHiddenFiles)

                Divider()

                Menu("Sort By") {
                    ForEach(FileSortOrder.allCases, id: \.self) { order in
                        Button {
                            state.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if state.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)

            Button {
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Path Breadcrumbs

struct PathBreadcrumbs: View {
    let path: URL
    let volume: VolumeInfo?
    let onNavigate: (URL) -> Void

    private var components: [(name: String, url: URL)] {
        guard let mountPoint = volume?.mountPoint else { return [] }

        var result: [(String, URL)] = []
        var currentURL = path

        while currentURL.path.hasPrefix(mountPoint.path) {
            result.insert((currentURL.lastPathComponent, currentURL), at: 0)
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }

        // Replace first component with volume name
        if !result.isEmpty {
            result[0] = (volume?.displayName ?? "Volume", result[0].1)
        }

        return result
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button(component.name) {
                    onNavigate(component.url)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .lineLimit(1)
            }
        }
    }
}

// MARK: - No Volume Selected View

struct NoVolumeSelectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Volume Selected")
                .font(.title2.bold())

            Text("Select a mounted volume from the sidebar to browse files.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - New Folder Sheet

struct NewFolderSheet: View {
    @ObservedObject var state: FileBrowserState
    @State private var folderName = "untitled folder"
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Folder")
                .font(.headline)

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    Task {
                        await state.createFolder(name: folderName)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(folderName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    @ObservedObject var state: FileBrowserState
    @State private var newName = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename")
                .font(.headline)

            TextField("New Name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onAppear {
                    newName = state.selectedItem?.name ?? ""
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Rename") {
                    if let item = state.selectedItem {
                        Task {
                            await state.renameItem(item, to: newName)
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newName == state.selectedItem?.name)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - File Drop Delegate

struct FileDropDelegate: DropDelegate {
    @ObservedObject var state: FileBrowserState

    func performDrop(info: DropInfo) -> Bool {
        guard state.selectedVolume?.isReadWrite == true else { return false }

        let providers = info.itemProviders(for: [.fileURL])

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    await state.copyFile(from: url)
                }
            }
        }

        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        return state.selectedVolume?.isReadWrite == true && state.currentPath != nil
    }
}

#Preview {
    FileBrowserTab()
        .environmentObject(DroboStorageCoordinator())
        .frame(width: 1000, height: 700)
}
