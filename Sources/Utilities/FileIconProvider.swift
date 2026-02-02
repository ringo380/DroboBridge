//
//  FileIconProvider.swift
//  DroboBridge
//
//  Provides file type icons using NSWorkspace with caching for performance
//

import SwiftUI
import AppKit

/// Provides file icons using LaunchServices/NSWorkspace with intelligent caching
@MainActor
final class FileIconProvider: ObservableObject {
    static let shared = FileIconProvider()

    /// Cache for file icons, keyed by file path
    private var iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500  // Limit cache size
        return cache
    }()

    /// Cache for extension-based icons (used as fallback)
    private var extensionCache: [String: NSImage] = [:]

    private init() {}

    /// Get the icon for a file at the given URL
    /// - Parameter url: The file URL
    /// - Returns: The file's icon as an NSImage
    func icon(for url: URL) -> NSImage {
        let path = url.path as NSString

        // Check cache first
        if let cached = iconCache.object(forKey: path) {
            return cached
        }

        // Get the actual icon from NSWorkspace
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)  // Standardize size

        // Cache the result
        iconCache.setObject(icon, forKey: path)

        return icon
    }

    /// Get a generic icon for files with the given extension
    /// - Parameter extension: The file extension (e.g., "pdf", "mp3")
    /// - Returns: An icon representing files of this type
    func icon(forExtension ext: String) -> NSImage {
        let lowercaseExt = ext.lowercased()

        // Check extension cache
        if let cached = extensionCache[lowercaseExt] {
            return cached
        }

        // Create a temporary file URL with this extension to get the generic icon
        let tempURL = URL(fileURLWithPath: "/tmp/dummy.\(lowercaseExt)")
        let icon = NSWorkspace.shared.icon(forFile: tempURL.path)
        icon.size = NSSize(width: 32, height: 32)

        // Cache the result
        extensionCache[lowercaseExt] = icon

        return icon
    }

    /// Clear all cached icons
    func clearCache() {
        iconCache.removeAllObjects()
        extensionCache.removeAll()
    }
}

// MARK: - File Icon View

/// A SwiftUI view that displays a file's icon
struct FileIconView: View {
    let url: URL
    let size: CGFloat

    @StateObject private var iconProvider = FileIconProvider.shared

    var body: some View {
        Image(nsImage: iconProvider.icon(for: url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    init(url: URL, size: CGFloat = 20) {
        self.url = url
        self.size = size
    }
}

#Preview {
    VStack(spacing: 10) {
        FileIconView(url: URL(fileURLWithPath: "/Applications/Safari.app"), size: 32)
        FileIconView(url: URL(fileURLWithPath: "/Users"), size: 32)
        FileIconView(url: URL(fileURLWithPath: "/tmp/test.pdf"), size: 32)
    }
    .padding()
}
