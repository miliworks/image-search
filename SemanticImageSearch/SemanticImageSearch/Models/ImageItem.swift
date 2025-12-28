//
//  ImageItem.swift
//  SemanticImageSearch
//
//  Data model representing an indexed image.
//

import Foundation
import AppKit

/// Represents an indexed image with its metadata and embeddings
struct ImageItem: Identifiable, Codable, Equatable {
    /// Unique identifier
    let id: UUID
    
    /// Full path to the image file
    let path: String
    
    /// Parent folder ID
    let folderId: UUID
    
    /// File name
    let fileName: String
    
    /// File size in bytes
    let fileSize: Int64
    
    /// Image dimensions
    let width: Int
    let height: Int
    
    /// Creation date of the file
    let createdAt: Date
    
    /// Date when the image was indexed
    let indexedAt: Date
    
    /// Vector embedding (stored as compressed data)
    let vector: [Float]
    
    /// OCR extracted text (if any)
    let ocrText: String?
    
    /// Thumbnail data (compressed JPEG)
    let thumbnailData: Data?
    
    // MARK: - Computed Properties
    
    /// File URL
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    /// Formatted file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Image dimensions string
    var dimensionsString: String {
        "\(width) × \(height)"
    }
    
    /// File extension
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Thumbnail Loading

extension ImageItem {
    /// Load thumbnail from cached data or generate from file
    func loadThumbnail(maxSize: CGFloat = 200) -> NSImage? {
        // Try cached thumbnail first
        if let data = thumbnailData, let image = NSImage(data: data) {
            return image
        }
        
        // Generate from file
        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        
        return image.resized(toMaxDimension: maxSize)
    }
    
    /// Load full resolution image
    func loadFullImage() -> NSImage? {
        NSImage(contentsOfFile: path)
    }
}

// MARK: - Factory

extension ImageItem {
    /// Create a new ImageItem from file URL
    static func create(
        from url: URL,
        folderId: UUID,
        vector: [Float],
        ocrText: String?,
        thumbnailData: Data?
    ) -> ImageItem? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64,
              let createdAt = attributes[.creationDate] as? Date else {
            return nil
        }
        
        // Get image dimensions
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        
        return ImageItem(
            id: UUID(),
            path: url.path,
            folderId: folderId,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            width: width,
            height: height,
            createdAt: createdAt,
            indexedAt: Date(),
            vector: vector,
            ocrText: ocrText,
            thumbnailData: thumbnailData
        )
    }
}
