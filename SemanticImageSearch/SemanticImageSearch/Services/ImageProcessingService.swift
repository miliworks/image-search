//
//  ImageProcessingService.swift
//  SemanticImageSearch
//
//  Service for processing images: vectorization, OCR, and thumbnail generation.
//

import Foundation
import AppKit
import CoreImage

/// Service for processing images
actor ImageProcessingService {
    static let shared = ImageProcessingService()
    
    // MARK: - Properties
    
    private let vectorService = VectorService.shared
    private let ocrService = OCRService.shared
    
    /// Thumbnail size
    private let thumbnailSize: CGFloat = 200
    
    /// JPEG compression quality for thumbnails
    private let thumbnailQuality: CGFloat = 0.7
    
    /// Supported image extensions
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Image Processing
    
    /// Process an image at the given URL
    func processImage(at url: URL, folderId: UUID) async -> ImageItem? {
        // Validate file exists and is an image
        guard FileManager.default.fileExists(atPath: url.path),
              Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }
        
        // Load image
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        
        // Generate vector embedding
        guard let vector = try? await vectorService.generateImageEmbedding(from: image) else {
            return nil
        }
        
        // Extract OCR text (optional, don't fail if OCR fails)
        let ocrText = try? await ocrService.extractText(from: image)
        
        // Generate thumbnail
        let thumbnailData = generateThumbnailData(from: image)
        
        // Create ImageItem
        return ImageItem.create(
            from: url,
            folderId: folderId,
            vector: vector,
            ocrText: ocrText,
            thumbnailData: thumbnailData
        )
    }
    
    /// Process multiple images in batch
    func processImages(at urls: [URL], folderId: UUID, progress: @escaping (Int, Int) -> Void) async -> [ImageItem] {
        var results: [ImageItem] = []
        let total = urls.count
        
        for (index, url) in urls.enumerated() {
            if let item = await processImage(at: url, folderId: folderId) {
                results.append(item)
            }
            progress(index + 1, total)
        }
        
        return results
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate compressed thumbnail data from an image
    private func generateThumbnailData(from image: NSImage) -> Data? {
        guard let resized = image.resized(toMaxDimension: thumbnailSize) else {
            return nil
        }
        
        return resized.jpegData(compressionQuality: thumbnailQuality)
    }
    
    // MARK: - Validation
    
    /// Check if a URL points to a supported image file
    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
    
    /// Get file info without fully processing
    func getImageInfo(at url: URL) -> ImageInfo? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }
        
        // Get dimensions
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        
        return ImageInfo(
            url: url,
            fileSize: fileSize,
            width: width,
            height: height
        )
    }
}

// MARK: - Supporting Types

/// Basic image information
struct ImageInfo {
    let url: URL
    let fileSize: Int64
    let width: Int
    let height: Int
    
    var fileName: String {
        url.lastPathComponent
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var dimensions: String {
        "\(width) × \(height)"
    }
}

// MARK: - Image Comparison

extension ImageProcessingService {
    /// Calculate similarity between two images
    func calculateSimilarity(image1: NSImage, image2: NSImage) async -> Float? {
        guard let vector1 = try? await vectorService.generateImageEmbedding(from: image1),
              let vector2 = try? await vectorService.generateImageEmbedding(from: image2) else {
            return nil
        }
        
        return cosineSimilarity(vector1, vector2)
    }
    
    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
}
