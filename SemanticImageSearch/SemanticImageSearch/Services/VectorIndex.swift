//
//  VectorIndex.swift
//  SemanticImageSearch
//
//  In-memory vector index for fast similarity search.
//  Uses a simple but efficient flat index with SIMD acceleration.
//

import Foundation
import Accelerate

/// Configuration for the vector index
struct VectorIndexConfig {
    /// Dimension of vectors
    let dimension: Int
    
    /// Maximum number of results to return
    let defaultK: Int
    
    /// Whether to normalize vectors before indexing
    let normalizeVectors: Bool
    
    static let clip = VectorIndexConfig(
        dimension: 512,  // CLIP ViT-B/32 dimension
        defaultK: 50,
        normalizeVectors: true
    )
}

/// Result from a similarity search
struct VectorSearchResult {
    let id: UUID
    let score: Float
}

/// In-memory vector index for fast similarity search
/// Uses flat index with SIMD-accelerated distance calculations
final class VectorIndex: @unchecked Sendable {
    private var ids: [UUID] = []
    private var vectors: [[Float]] = []
    private let config: VectorIndexConfig
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    init(config: VectorIndexConfig = .clip) {
        self.config = config
    }
    
    // MARK: - Index Operations
    
    /// Add a vector to the index
    func add(_ vector: [Float], id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        // Normalize if configured
        let normalizedVector = config.normalizeVectors ? normalize(vector) : vector
        
        // Check if ID already exists
        if let existingIndex = ids.firstIndex(of: id) {
            vectors[existingIndex] = normalizedVector
        } else {
            ids.append(id)
            vectors.append(normalizedVector)
        }
    }
    
    /// Add multiple vectors to the index
    func addBatch(_ items: [(vector: [Float], id: UUID)]) {
        lock.lock()
        defer { lock.unlock() }
        
        for item in items {
            let normalizedVector = config.normalizeVectors ? normalize(item.vector) : item.vector
            
            if let existingIndex = ids.firstIndex(of: item.id) {
                vectors[existingIndex] = normalizedVector
            } else {
                ids.append(item.id)
                vectors.append(normalizedVector)
            }
        }
    }
    
    /// Remove a vector from the index
    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            vectors.remove(at: index)
        }
    }
    
    /// Clear all vectors from the index
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        ids.removeAll()
        vectors.removeAll()
    }
    
    /// Get the number of vectors in the index
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return ids.count
    }
    
    // MARK: - Search
    
    /// Search for the k most similar vectors
    func search(query: [Float], k: Int? = nil) -> [VectorSearchResult] {
        lock.lock()
        defer { lock.unlock() }
        
        guard !vectors.isEmpty else { return [] }
        
        let normalizedQuery = config.normalizeVectors ? normalize(query) : query
        let limit = min(k ?? config.defaultK, vectors.count)
        
        // Calculate similarities using SIMD
        var similarities: [(index: Int, score: Float)] = []
        similarities.reserveCapacity(vectors.count)
        
        for (index, vector) in vectors.enumerated() {
            let similarity = cosineSimilarity(normalizedQuery, vector)
            similarities.append((index: index, score: similarity))
        }
        
        // Sort by score descending and take top k
        similarities.sort { $0.score > $1.score }
        
        return similarities.prefix(limit).map { item in
            VectorSearchResult(id: ids[item.index], score: item.score)
        }
    }
    
    /// Search with minimum score threshold
    func search(query: [Float], minScore: Float, maxResults: Int = 100) -> [VectorSearchResult] {
        lock.lock()
        defer { lock.unlock() }
        
        guard !vectors.isEmpty else { return [] }
        
        let normalizedQuery = config.normalizeVectors ? normalize(query) : query
        
        var results: [VectorSearchResult] = []
        
        for (index, vector) in vectors.enumerated() {
            let similarity = cosineSimilarity(normalizedQuery, vector)
            if similarity >= minScore {
                results.append(VectorSearchResult(id: ids[index], score: similarity))
            }
        }
        
        // Sort by score descending
        results.sort { $0.score > $1.score }
        
        return Array(results.prefix(maxResults))
    }
    
    // MARK: - Vector Math (SIMD Accelerated)
    
    /// Normalize a vector to unit length
    private func normalize(_ vector: [Float]) -> [Float] {
        var result = vector
        var norm: Float = 0
        
        // Calculate L2 norm using BLAS
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        
        guard norm > 0 else { return vector }
        
        // Divide by norm
        var normValue = norm
        vDSP_vsdiv(vector, 1, &normValue, &result, 1, vDSP_Length(vector.count))
        
        return result
    }
    
    /// Calculate cosine similarity between two vectors (assuming normalized)
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        
        return result
    }
}

// MARK: - Persistence

extension VectorIndex {
    /// Save index to disk
    func save(to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let data = VectorIndexData(
            ids: ids.map { $0.uuidString },
            vectors: vectors,
            dimension: config.dimension
        )
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded = try encoder.encode(data)
        try encoded.write(to: url)
    }
    
    /// Load index from disk
    func load(from url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let data = try Data(contentsOf: url)
        let decoder = PropertyListDecoder()
        let indexData = try decoder.decode(VectorIndexData.self, from: data)
        
        ids = indexData.ids.compactMap { UUID(uuidString: $0) }
        vectors = indexData.vectors
    }
}

/// Serializable index data
private struct VectorIndexData: Codable {
    let ids: [String]
    let vectors: [[Float]]
    let dimension: Int
}
