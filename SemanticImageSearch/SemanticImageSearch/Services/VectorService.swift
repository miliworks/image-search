//
//  VectorService.swift
//  SemanticImageSearch
//
//  Service for vector embedding generation using Core ML.
//  Supports both CLIP models and Vision FeaturePrint fallback.
//

import Foundation
import CoreML
import Vision
import AppKit

/// Service for generating and managing vector embeddings
actor VectorService {
    static let shared = VectorService()
    
    // MARK: - Properties
    
    private let index = VectorIndex(config: .clip)
    private let clipService = CLIPService.shared
    private var useCLIP = false
    private var isInitialized = false
    
    // Index file path
    private var indexPath: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("SemanticImageSearch")
            .appendingPathComponent("vector_index.plist")
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initialize the vector service with ML models
    func initialize() async throws {
        guard !isInitialized else { return }
        
        // Try to initialize CLIP service
        do {
            try await clipService.initialize()
            useCLIP = await clipService.isAvailable
            if useCLIP {
                print("✅ Using CLIP models for embeddings")
            }
        } catch {
            print("⚠️ CLIP not available, using Vision FeaturePrint fallback")
        }
        
        // Try to load saved index
        if FileManager.default.fileExists(atPath: indexPath.path) {
            try? index.load(from: indexPath)
        }
        
        isInitialized = true
    }
    
    // MARK: - Image Embedding
    
    /// Generate embedding for an image
    func generateImageEmbedding(from image: NSImage) async throws -> [Float] {
        // Use CLIP if available
        if useCLIP {
            return try await clipService.encodeImage(image)
        }
        
        // Fallback to Vision FeaturePrint
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VectorError.invalidImage
        }
        
        return try await generateImageEmbeddingWithVision(from: cgImage)
    }
    
    /// Generate embedding for an image at URL
    func generateImageEmbedding(from url: URL) async throws -> [Float] {
        // Use CLIP if available
        if useCLIP {
            return try await clipService.encodeImage(at: url)
        }
        
        // Fallback to Vision FeaturePrint
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VectorError.invalidImage
        }
        
        return try await generateImageEmbeddingWithVision(from: cgImage)
    }
    
    /// Generate embedding from CGImage using Vision's feature print (fallback)
    private func generateImageEmbeddingWithVision(from cgImage: CGImage) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(throwing: VectorError.featureExtractionFailed)
                    return
                }
                
                // Convert feature print to float array
                let data = observation.data
                let floatCount = data.count / MemoryLayout<Float>.size
                var floats = [Float](repeating: 0, count: floatCount)
                
                data.withUnsafeBytes { buffer in
                    let floatBuffer = buffer.bindMemory(to: Float.self)
                    for i in 0..<floatCount {
                        floats[i] = floatBuffer[i]
                    }
                }
                
                // Normalize to 512 dimensions (pad or truncate)
                let targetDimension = 512
                var normalizedFloats: [Float]
                
                if floats.count >= targetDimension {
                    normalizedFloats = Array(floats.prefix(targetDimension))
                } else {
                    normalizedFloats = floats + [Float](repeating: 0, count: targetDimension - floats.count)
                }
                
                continuation.resume(returning: normalizedFloats)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Text Embedding
    
    /// Generate embedding for text query
    func generateTextEmbedding(from text: String) async throws -> [Float] {
        // Use CLIP if available
        if useCLIP {
            return try await clipService.encodeText(text)
        }
        
        // Fallback to simple embedding
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let embedding = self.simpleTextEmbedding(text)
                continuation.resume(returning: embedding)
            }
        }
    }
    
    /// Simple text embedding using character-level features
    /// This is a fallback when CLIP text encoder is not available
    private nonisolated func simpleTextEmbedding(_ text: String) -> [Float] {
        let targetDimension = 512
        var embedding = [Float](repeating: 0, count: targetDimension)
        
        let normalizedText = text.lowercased()
        let words = normalizedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // Create a simple hash-based embedding
        for (wordIndex, word) in words.enumerated() {
            for (charIndex, char) in word.unicodeScalars.enumerated() {
                let hash = Int(char.value) * (wordIndex + 1) * (charIndex + 1)
                let index = hash % targetDimension
                embedding[index] += 1.0 / Float(words.count)
            }
        }
        
        // Normalize
        var sumSquares: Float = 0
        for value in embedding {
            sumSquares += value * value
        }
        
        let norm = sqrt(sumSquares)
        if norm > 0 {
            for i in 0..<embedding.count {
                embedding[i] /= norm
            }
        }
        
        return embedding
    }
    
    /// Check if using CLIP models
    var isUsingCLIP: Bool {
        useCLIP
    }
    
    // MARK: - Index Operations
    
    /// Add a vector to the index
    func addVector(_ vector: [Float], id: UUID) {
        index.add(vector, id: id)
    }
    
    /// Add multiple vectors to the index
    func addVectors(_ items: [(vector: [Float], id: UUID)]) {
        index.addBatch(items)
    }
    
    /// Remove a vector from the index
    func removeVector(id: UUID) {
        index.remove(id: id)
    }
    
    /// Search for similar vectors
    func search(query: [Float], k: Int = 50) -> [VectorSearchResult] {
        index.search(query: query, k: k)
    }
    
    /// Search with minimum score threshold
    func search(query: [Float], minScore: Float, maxResults: Int = 100) -> [VectorSearchResult] {
        index.search(query: query, minScore: minScore, maxResults: maxResults)
    }
    
    /// Rebuild index from database
    func rebuildIndex() async {
        index.clear()
        
        do {
            let vectors = try await DatabaseService.shared.loadAllVectors()
            index.addBatch(vectors.map { (vector: $0.vector, id: $0.id) })
            try? index.save(to: indexPath)
        } catch {
            print("Error rebuilding index: \(error)")
        }
    }
    
    /// Save index to disk
    func saveIndex() {
        try? index.save(to: indexPath)
    }
    
    /// Get index size
    var indexSize: Int {
        index.count
    }
}

// MARK: - Errors

enum VectorError: Error, LocalizedError {
    case invalidImage
    case modelNotLoaded
    case featureExtractionFailed
    case embeddingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid or corrupted image"
        case .modelNotLoaded:
            return "ML model not loaded"
        case .featureExtractionFailed:
            return "Failed to extract image features"
        case .embeddingFailed:
            return "Failed to generate embedding"
        }
    }
}
