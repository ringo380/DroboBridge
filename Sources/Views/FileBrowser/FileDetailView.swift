//
//  FileDetailView.swift
//  DroboBridge
//
//  Detail view for selected files in the file browser
//

import SwiftUI
import QuickLookUI

// MARK: - File Detail View

struct FileDetailView: View {
    let item: FileItem
    @ObservedObject var state: FileBrowserState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Icon and name
                VStack(spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 64))
                        .foregroundColor(iconColor)

                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    // Read-only badge if applicable
                    if !item.isWritable {
                        Label("Read Only", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top)

                Divider()

                // File information
                GroupBox("Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        FileDetailRow(label: "Kind", value: item.isDirectory ? "Folder" : item.fileExtension.uppercased())

                        if !item.isDirectory {
                            FileDetailRow(label: "Size", value: item.formattedSize)
                        }

                        if let modified = item.formattedModificationDate {
                            FileDetailRow(label: "Modified", value: modified)
                        }

                        if let created = item.creationDate {
                            FileDetailRow(label: "Created", value: formatDate(created))
                        }

                        FileDetailRow(label: "Path", value: item.url.path)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }

                // Actions
                GroupBox("Actions") {
                    VStack(spacing: 8) {
                        // Open / Quick Look
                        Button {
                            if item.isDirectory {
                                state.navigateTo(item.url)
                            } else {
                                state.quickLook(item)
                            }
                        } label: {
                            Label(item.isDirectory ? "Open Folder" : "Quick Look", systemImage: item.isDirectory ? "folder" : "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        // Reveal in Finder
                        Button {
                            state.revealInFinder(item)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder.badge.gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        // Write operations (only if volume is read-write)
                        if state.selectedVolume?.isReadWrite == true {
                            Divider()

                            Button {
                                state.selectedItem = item
                                state.showRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                state.deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
                                Text("Volume is mounted read-only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding()
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
            return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

struct FileDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}

#Preview {
    FileDetailView(
        item: FileItem(
            url: URL(fileURLWithPath: "/Volumes/Drobo/Photos/vacation.jpg"),
            attributes: [
                .size: UInt64(5_000_000),
                .modificationDate: Date(),
                .creationDate: Date().addingTimeInterval(-86400 * 30)
            ]
        ),
        state: FileBrowserState()
    )
    .frame(width: 280, height: 500)
}
