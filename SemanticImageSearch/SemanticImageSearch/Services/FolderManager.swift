//
//  FolderManager.swift
//  SemanticImageSearch
//
//  Service for scanning and monitoring folders for images.
//

import Foundation
import AppKit

/// Service for managing folder scanning
actor FolderManager {
    static let shared = FolderManager()
    
    // MARK: - Properties
    
    /// Supported image extensions
    private let supportedExtensions = ImageProcessingService.supportedExtensions
    
    /// Maximum number of files to scan in one batch
    private let batchSize = 100
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Scanning
    
    /// Scan a folder for image files recursively
    func scanForImages(in url: URL) throws -> [URL] {
        var imageURLs: [URL] = []
        
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .contentModificationDateKey
        ]
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FolderError.cannotEnumerate
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                // Skip directories
                if resourceValues.isDirectory == true {
                    continue
                }
                
                // Skip hidden files
                if resourceValues.isHidden == true {
                    continue
                }
                
                // Check if it's a supported image
                let ext = fileURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    imageURLs.append(fileURL)
                }
            } catch {
                // Skip files we can't read
                continue
            }
        }
        
        // Sort by modification date (newest first)
        imageURLs.sort { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }
        
        return imageURLs
    }
    
    /// Scan folder and return only new/modified images
    func scanForNewImages(in url: URL, since date: Date?) throws -> [URL] {
        let allImages = try scanForImages(in: url)
        
        guard let since = date else {
            return allImages
        }
        
        return allImages.filter { imageURL in
            guard let modDate = try? imageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return true
            }
            return modDate > since
        }
    }
    
    /// Get image count in folder without full scan
    func getImageCount(in url: URL) throws -> Int {
        var count = 0
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FolderError.cannotEnumerate
        }
        
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                count += 1
            }
        }
        
        return count
    }
    
    /// Check if folder is accessible
    func isAccessible(_ url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }
    
    /// Get folder statistics
    func getFolderStats(url: URL) throws -> FolderStats {
        let images = try scanForImages(in: url)
        
        var totalSize: Int64 = 0
        var oldestDate: Date?
        var newestDate: Date?
        
        for imageURL in images {
            if let size = try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
            
            if let modDate = try? imageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                if oldestDate == nil || modDate < oldestDate! {
                    oldestDate = modDate
                }
                if newestDate == nil || modDate > newestDate! {
                    newestDate = modDate
                }
            }
        }
        
        return FolderStats(
            imageCount: images.count,
            totalSize: totalSize,
            oldestImage: oldestDate,
            newestImage: newestDate
        )
    }
}

// MARK: - Supporting Types

/// Statistics for a folder
struct FolderStats {
    let imageCount: Int
    let totalSize: Int64
    let oldestImage: Date?
    let newestImage: Date?
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Errors for folder operations
enum FolderError: Error, LocalizedError {
    case cannotEnumerate
    case accessDenied
    case notADirectory
    
    var errorDescription: String? {
        switch self {
        case .cannotEnumerate:
            return "Cannot enumerate folder contents"
        case .accessDenied:
            return "Access denied to folder"
        case .notADirectory:
            return "Path is not a directory"
        }
    }
}

// MARK: - Folder Watching (Optional)

extension FolderManager {
    /// Create a file system watcher for a folder
    /// Returns a dispatch source that should be retained by the caller
    func createWatcher(for url: URL, onChange: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        
        source.setEventHandler {
            onChange()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        
        return source
    }
}
