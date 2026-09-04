import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WatchImageError: LocalizedError {
    case notAFile
    case tooLarge
    case tooManyPixels
    case unsupported
    case couldNotEncode
    case unsafeStorage

    var errorDescription: String? {
        switch self {
        case .notAFile: "The selected image is not a regular file."
        case .tooLarge: "The image is larger than 20 MB. Choose a smaller file."
        case .tooManyPixels: "The image exceeds the 50-megapixel safety limit."
        case .unsupported: "The image could not be read. Use PNG, JPEG, HEIC, or WebP."
        case .couldNotEncode: "A safe copy of the image could not be created."
        case .unsafeStorage: "The private image folder is unavailable or unsafe."
        }
    }
}

/// Imports photos into a private app directory. The first frame is decoded and re-encoded
/// as a bounded PNG, removing EXIF, GPS, and the original filename.
enum WatchImageStore {
    private static let maximumInputBytes = 20_000_000
    private static let maximumStoredBytes = 30_000_000
    private static let maximumPixels = 50_000_000
    private static let maximumDimension = 2_400

    static let directory = Persistence.directory.appendingPathComponent("WatchImages", isDirectory: true)

    /// Decoding work intended to run away from the main actor.
    static func importImage(from sourceURL: URL) throws -> String {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw WatchImageError.notAFile
        }
        if let size = values.fileSize, size > maximumInputBytes { throw WatchImageError.tooLarge }

        let input = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard input.count <= maximumInputBytes else { throw WatchImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(input as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw WatchImageError.unsupported
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
           width > 0, height > 0,
           width > maximumPixels / height {
            throw WatchImageError.tooManyPixels
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WatchImageError.unsupported
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw WatchImageError.couldNotEncode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WatchImageError.couldNotEncode }
        guard output.length <= maximumStoredBytes else { throw WatchImageError.tooLarge }
        guard Persistence.ensurePrivateDirectory(Persistence.directory),
              Persistence.ensurePrivateDirectory(directory) else {
            throw WatchImageError.unsafeStorage
        }

        let filename = "watch-\(UUID().uuidString).png"
        let destinationURL = directory.appendingPathComponent(filename, isDirectory: false)
        try (output as Data).write(to: destinationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        return filename
    }

    static func removeImage(named filename: String?) {
        guard let filename,
              safeFilename(filename) != nil,
              Persistence.ensurePrivateDirectory(Persistence.directory),
              Persistence.ensurePrivateDirectory(directory) else { return }
        let url = directory.appendingPathComponent(filename)
        guard Persistence.isSafeRegularFile(url, maximumBytes: maximumStoredBytes) else { return }
        try? FileManager.default.removeItem(at: url)
        Task { @MainActor in cache.removeObject(forKey: filename as NSString) }
    }

    @MainActor
    static func image(named filename: String?) -> NSImage? {
        guard let filename,
              safeFilename(filename) != nil,
              Persistence.ensurePrivateDirectory(Persistence.directory),
              Persistence.ensurePrivateDirectory(directory) else { return nil }
        let key = filename as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = directory.appendingPathComponent(filename)
        guard Persistence.isSafeRegularFile(url, maximumBytes: maximumStoredBytes),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    @MainActor
    static func defaultImage() -> NSImage? {
        if let cachedDefault { return cachedDefault }
        cachedDefault = bundledImage(named: "default-watch")
        return cachedDefault
    }

    @MainActor
    static func buttonGuideImage() -> NSImage? {
        if let cachedButtonGuide { return cachedButtonGuide }
        cachedButtonGuide = bundledImage(named: "button-guide")
        return cachedButtonGuide
    }

    private static func safeFilename(_ filename: String) -> String? {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasPrefix("watch-"),
              filename.hasSuffix(".png") else { return nil }
        return filename
    }

    @MainActor
    private static func bundledImage(named name: String) -> NSImage? {
        let developmentRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let developmentURL = developmentRoot
            .appendingPathComponent("Resources/Assets/\(name).png")
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Assets"
        ) ?? developmentURL
        return NSImage(contentsOf: url)
    }

    @MainActor private static let cache = NSCache<NSString, NSImage>()
    @MainActor private static var cachedDefault: NSImage?
    @MainActor private static var cachedButtonGuide: NSImage?
}
