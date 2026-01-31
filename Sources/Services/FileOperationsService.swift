//
//  FileOperationsService.swift
//  DroboBridge
//
//  Safe file operations with confirmation and logging
//

import Foundation

// MARK: - File Item Model

struct FileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let isReadable: Bool
    let isWritable: Bool

    var formattedSize: String {
        if isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedModificationDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var systemImage: String {
        if isDirectory {
            return "folder.fill"
        }

        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp":
            return "photo"
        case "mov", "mp4", "m4v", "avi", "mkv":
            return "film"
        case "mp3", "m4a", "wav", "aiff", "flac":
            return "music.note"
        case "pdf":
            return "doc.fill"
        case "txt", "md", "rtf":
            return "doc.text"
        case "zip", "tar", "gz", "rar", "7z":
            return "doc.zipper"
        case "dmg", "iso":
            return "externaldrive"
        case "app":
            return "app.gift"
        default:
            return "doc"
        }
    }

    init(url: URL, attributes: [FileAttributeKey: Any]?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = (attributes?[.type] as? FileAttributeType) == .typeDirectory
        self.size = (attributes?[.size] as? UInt64) ?? 0
        self.modificationDate = attributes?[.modificationDate] as? Date
        self.creationDate = attributes?[.creationDate] as? Date
        self.isHidden = url.lastPathComponent.hasPrefix(".")
        self.isReadable = FileManager.default.isReadableFile(atPath: url.path)
        self.isWritable = FileManager.default.isWritableFile(atPath: url.path)
    }
}

// MARK: - File Operation Type

enum FileOperationType {
    case copy
    case move
    case delete
    case rename
    case createFolder

    var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        case .delete: return "Delete"
        case .rename: return "Rename"
        case .createFolder: return "Create Folder"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "folder.badge.plus"
        case .delete: return "trash"
        case .rename: return "pencil"
        case .createFolder: return "folder.badge.plus"
        }
    }

    var isDestructive: Bool {
        self == .delete
    }
}

// MARK: - File Operation Result

enum FileOperationResult {
    case success(message: String)
    case failure(error: Error)
    case cancelled

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - File Operations Service

actor FileOperationsService {

    // MARK: - List Directory

    func listDirectory(at url: URL) async throws -> [FileItem] {
        let fileManager = FileManager.default

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw FileOperationError.notReadable(url.path)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .isDirectoryKey,
                .isHiddenKey
            ],
            options: []
        )

        var items: [FileItem] = []

        for itemURL in contents {
            let attributes = try? fileManager.attributesOfItem(atPath: itemURL.path)
            items.append(FileItem(url: itemURL, attributes: attributes))
        }

        // Sort: directories first, then by name
        items.sort { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory
            }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }

        return items
    }

    // MARK: - Search

    func search(query: String, in directory: URL, recursive: Bool = true) async throws -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []

        let lowercasedQuery = query.lowercased()

        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            if itemURL.lastPathComponent.lowercased().contains(lowercasedQuery) {
                let attributes = try? fileManager.attributesOfItem(atPath: itemURL.path)
                results.append(FileItem(url: itemURL, attributes: attributes))
            }

            // Limit results
            if results.count >= 500 {
                break
            }
        }

        return results
    }

    // MARK: - Copy Operation

    func copyItem(from source: URL, to destination: URL, volume: VolumeInfo) async throws -> FileOperationResult {
        // Validate write permission
        try SafetyGuard.validateWriteOperation(volume: volume, operation: "copy \(source.lastPathComponent)")

        let fileManager = FileManager.default

        // Check source exists
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileOperationError.sourceNotFound(source.path)
        }

        // Determine destination path
        var targetURL = destination
        if fileManager.fileExists(atPath: destination.path) {
            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            if (attributes?[.type] as? FileAttributeType) == .typeDirectory {
                targetURL = destination.appendingPathComponent(source.lastPathComponent)
            }
        }

        // Check if target already exists
        if fileManager.fileExists(atPath: targetURL.path) {
            throw FileOperationError.destinationExists(targetURL.path)
        }

        SafetyGuard.auditLog("Copying \(source.path) to \(targetURL.path)")

        try fileManager.copyItem(at: source, to: targetURL)

        return .success(message: "Copied \(source.lastPathComponent) successfully")
    }

    // MARK: - Move Operation

    func moveItem(from source: URL, to destination: URL, volume: VolumeInfo) async throws -> FileOperationResult {
        // Validate write permission
        try SafetyGuard.validateWriteOperation(volume: volume, operation: "move \(source.lastPathComponent)")

        let fileManager = FileManager.default

        // Check source exists
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileOperationError.sourceNotFound(source.path)
        }

        // Determine destination path
        var targetURL = destination
        if fileManager.fileExists(atPath: destination.path) {
            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            if (attributes?[.type] as? FileAttributeType) == .typeDirectory {
                targetURL = destination.appendingPathComponent(source.lastPathComponent)
            }
        }

        // Check if target already exists
        if fileManager.fileExists(atPath: targetURL.path) {
            throw FileOperationError.destinationExists(targetURL.path)
        }

        SafetyGuard.auditLog("Moving \(source.path) to \(targetURL.path)")

        try fileManager.moveItem(at: source, to: targetURL)

        return .success(message: "Moved \(source.lastPathComponent) successfully")
    }

    // MARK: - Delete Operation

    func deleteItem(at url: URL, volume: VolumeInfo, moveToTrash: Bool = true) async throws -> FileOperationResult {
        // Validate write permission
        try SafetyGuard.validateWriteOperation(volume: volume, operation: "delete \(url.lastPathComponent)")

        let fileManager = FileManager.default

        // Check file exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceNotFound(url.path)
        }

        SafetyGuard.auditLog("Deleting \(url.path) (moveToTrash: \(moveToTrash))", level: .warning)

        if moveToTrash {
            // Try to move to trash (may not work on external volumes)
            do {
                var trashedURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
                return .success(message: "Moved \(url.lastPathComponent) to Trash")
            } catch {
                // Fall back to permanent delete
                SafetyGuard.auditLog("Trash failed, falling back to permanent delete: \(error.localizedDescription)")
            }
        }

        // Permanent delete
        try fileManager.removeItem(at: url)
        return .success(message: "Deleted \(url.lastPathComponent) permanently")
    }

    // MARK: - Rename Operation

    func renameItem(at url: URL, to newName: String, volume: VolumeInfo) async throws -> FileOperationResult {
        // Validate write permission
        try SafetyGuard.validateWriteOperation(volume: volume, operation: "rename \(url.lastPathComponent)")

        let fileManager = FileManager.default

        // Check file exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceNotFound(url.path)
        }

        // Build new URL
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        // Check if new name already exists
        if fileManager.fileExists(atPath: newURL.path) {
            throw FileOperationError.destinationExists(newURL.path)
        }

        // Validate new name
        guard !newName.isEmpty, !newName.contains("/") else {
            throw FileOperationError.invalidName(newName)
        }

        SafetyGuard.auditLog("Renaming \(url.lastPathComponent) to \(newName)")

        try fileManager.moveItem(at: url, to: newURL)

        return .success(message: "Renamed to \(newName)")
    }

    // MARK: - Create Folder Operation

    func createFolder(at parentURL: URL, name: String, volume: VolumeInfo) async throws -> FileOperationResult {
        // Validate write permission
        try SafetyGuard.validateWriteOperation(volume: volume, operation: "create folder \(name)")

        let fileManager = FileManager.default

        let newFolderURL = parentURL.appendingPathComponent(name)

        // Check if folder already exists
        if fileManager.fileExists(atPath: newFolderURL.path) {
            throw FileOperationError.destinationExists(newFolderURL.path)
        }

        // Validate name
        guard !name.isEmpty, !name.contains("/") else {
            throw FileOperationError.invalidName(name)
        }

        SafetyGuard.auditLog("Creating folder \(newFolderURL.path)")

        try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)

        return .success(message: "Created folder \(name)")
    }

    // MARK: - Get File Info

    func getFileInfo(at url: URL) async throws -> FileItem {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceNotFound(url.path)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return FileItem(url: url, attributes: attributes)
    }
}

// MARK: - File Operation Error

enum FileOperationError: LocalizedError {
    case notReadable(String)
    case notWritable(String)
    case sourceNotFound(String)
    case destinationExists(String)
    case invalidName(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReadable(let path):
            return "Cannot read: \(path)"
        case .notWritable(let path):
            return "Cannot write: \(path)"
        case .sourceNotFound(let path):
            return "File not found: \(path)"
        case .destinationExists(let path):
            return "Destination already exists: \(path)"
        case .invalidName(let name):
            return "Invalid name: \(name)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        }
    }
}
