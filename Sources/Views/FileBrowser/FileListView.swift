//
//  FileListView.swift
//  DroboBridge
//
//  File list with columns for the file browser
//

import SwiftUI

// MARK: - File List View

struct FileListView: View {
    @ObservedObject var state: FileBrowserState

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.filteredItems.isEmpty {
                EmptyFolderView(hasSearchQuery: !state.searchQuery.isEmpty)
            } else {
                // File list
                List(state.filteredItems, id: \.id, selection: Binding(
                    get: { state.selectedItem?.id },
                    set: { newID in
                        state.selectedItem = state.filteredItems.first { $0.id == newID }
                    }
                )) { item in
                    FileRowView(item: item)
                        .tag(item.id)
                        .onTapGesture(count: 2) {
                            handlePrimaryAction(item)
                        }
                        .contextMenu {
                            FileContextMenu(item: item, state: state)
                        }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: state.currentPath) { newPath in
            if let path = newPath {
                Task {
                    await state.loadDirectory(path, addToHistory: false)
                }
            }
        }
        .onAppear {
            if let volume = state.selectedVolume, let mountPoint = volume.mountPoint, state.currentPath == nil {
                state.currentPath = mountPoint
                Task {
                    await state.loadDirectory(mountPoint)
                }
            }
        }
    }

    private func handlePrimaryAction(_ item: FileItem) {
        if item.isDirectory {
            state.navigateTo(item.url)
        } else {
            state.quickLook(item)
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.systemImage)
                .foregroundColor(iconColor)
                .frame(width: 20)

            // Name
            Text(item.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Lock indicator
            if !item.isWritable && !item.isDirectory {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Size
            Text(item.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Date
            Text(item.formattedModificationDate ?? "--")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        if item.isDirectory {
            return .blue
        }
        switch item.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic":
            return .purple
        case "mov", "mp4", "m4v":
            return .pink
        case "mp3", "m4a", "wav":
            return .red
        case "pdf":
            return .orange
        default:
            return .secondary
        }
    }
}

// MARK: - File Name Cell (for Table)

struct FileNameCell: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(item.name)
                .lineLimit(1)

            if !item.isWritable && !item.isDirectory {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var iconColor: Color {
        if item.isDirectory {
            return .blue
        }
        switch item.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic":
            return .purple
        case "mov", "mp4", "m4v":
            return .pink
        case "mp3", "m4a", "wav":
            return .red
        case "pdf":
            return .orange
        default:
            return .secondary
        }
    }
}

// MARK: - File Context Menu

struct FileContextMenu: View {
    let item: FileItem
    @ObservedObject var state: FileBrowserState

    var body: some View {
        Group {
            Button {
                if item.isDirectory {
                    state.navigateTo(item.url)
                } else {
                    state.quickLook(item)
                }
            } label: {
                Label(item.isDirectory ? "Open" : "Quick Look", systemImage: item.isDirectory ? "folder" : "eye")
            }

            Button {
                state.revealInFinder(item)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Divider()

            if state.selectedVolume?.isReadWrite == true {
                Button {
                    state.selectedItem = item
                    state.showRenameSheet = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    state.deleteItem(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Text("Read-only volume")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                copyPathToClipboard(item.url.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyPathToClipboard(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

// MARK: - Empty Folder View

struct EmptyFolderView: View {
    let hasSearchQuery: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasSearchQuery ? "magnifyingglass" : "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(hasSearchQuery ? "No Results" : "Empty Folder")
                .font(.headline)

            Text(hasSearchQuery ? "Try a different search term" : "This folder is empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FileListView(state: FileBrowserState())
        .frame(width: 600, height: 400)
}
