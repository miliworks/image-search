//
//  SearchEngine.swift
//  SemanticImageSearch
//
//  Combined semantic and text search engine.
//

import Foundation

/// Search engine combining vector similarity and text matching
actor SearchEngine {
    static let shared = SearchEngine()
    
    // MARK: - Properties
    
    private let vectorService = VectorService.shared
    private let databaseService = DatabaseService.shared
    
    /// Weight for semantic search in combined mode (0-1)
    private let semanticWeight: Float = 0.7
    
    /// Minimum score threshold for results
    private let minScoreThreshold: Float = 0.1
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Search
    
    /// Perform a search with the specified mode
    func search(query: String, mode: SearchMode, limit: Int = 50) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        switch mode {
        case .semantic:
            return try await semanticSearch(query: query, limit: limit)
        case .text:
            return try await textSearch(query: query, limit: limit)
        case .combined:
            return try await combinedSearch(query: query, limit: limit)
        }
    }
    
    // MARK: - Semantic Search
    
    /// Search using vector similarity
    private func semanticSearch(query: String, limit: Int) async throws -> [SearchResult] {
        // Generate query embedding
        let queryVector = try await vectorService.generateTextEmbedding(from: query)
        
        // Search vector index
        let vectorResults = await vectorService.search(query: queryVector, k: limit)
        
        guard !vectorResults.isEmpty else {
            return []
        }
        
        // Load image details
        let imageIds = vectorResults.map { $0.id }
        let images = try await databaseService.loadImages(ids: imageIds)
        
        // Create search results
        var results: [SearchResult] = []
        
        for vectorResult in vectorResults {
            guard let image = images.first(where: { $0.id == vectorResult.id }) else {
                continue
            }
            
            // Normalize score to 0-1 range
            let normalizedScore = (vectorResult.score + 1) / 2  // Cosine similarity is in [-1, 1]
            
            if normalizedScore >= minScoreThreshold {
                results.append(.semantic(image, score: normalizedScore))
            }
        }
        
        return results.sorted(by: >)
    }
    
    // MARK: - Text Search
    
    /// Search using OCR text matching
    private func textSearch(query: String, limit: Int) async throws -> [SearchResult] {
        // Perform full-text search
        let textResults = try await databaseService.searchByText(query, limit: limit)
        
        guard !textResults.isEmpty else {
            return []
        }
        
        // Load image details
        let imageIds = textResults.map { $0.id }
        let images = try await databaseService.loadImages(ids: imageIds)
        
        // Create search results
        var results: [SearchResult] = []
        
        for (index, textResult) in textResults.enumerated() {
            guard let image = images.first(where: { $0.id == textResult.id }) else {
                continue
            }
            
            // Calculate text relevance score (based on position in results)
            let score = Float(textResults.count - index) / Float(textResults.count)
            
            results.append(.text(image, score: score, snippets: [textResult.snippet]))
        }
        
        return results.sorted(by: >)
    }
    
    // MARK: - Combined Search
    
    /// Search using both vector similarity and text matching
    private func combinedSearch(query: String, limit: Int) async throws -> [SearchResult] {
        // Perform both searches in parallel
        async let semanticResults = semanticSearch(query: query, limit: limit * 2)
        async let textResults = textSearch(query: query, limit: limit * 2)
        
        let (semantic, text) = try await (semanticResults, textResults)
        
        // Merge results
        var scoreMap: [UUID: (semantic: Float, text: Float, snippets: [String])] = [:]
        var imageMap: [UUID: ImageItem] = [:]
        
        // Add semantic scores
        for result in semantic {
            scoreMap[result.id] = (semantic: result.semanticScore, text: 0, snippets: [])
            imageMap[result.id] = result.image
        }
        
        // Add text scores
        for result in text {
            if var existing = scoreMap[result.id] {
                existing.text = result.textScore
                existing.snippets = result.matchedSnippets
                scoreMap[result.id] = existing
            } else {
                scoreMap[result.id] = (semantic: 0, text: result.textScore, snippets: result.matchedSnippets)
                imageMap[result.id] = result.image
            }
        }
        
        // Create combined results
        var results: [SearchResult] = []
        
        for (id, scores) in scoreMap {
            guard let image = imageMap[id] else { continue }
            
            let result = SearchResult.combined(
                image,
                semanticScore: scores.semantic,
                textScore: scores.text,
                snippets: scores.snippets,
                semanticWeight: semanticWeight
            )
            
            if result.combinedScore >= minScoreThreshold {
                results.append(result)
            }
        }
        
        // Sort by combined score and limit
        return Array(results.sorted(by: >).prefix(limit))
    }
    
    // MARK: - Search Suggestions
    
    /// Get search suggestions based on indexed content
    func getSuggestions(for query: String, limit: Int = 10) async throws -> [String] {
        guard query.count >= 2 else { return [] }
        
        // Get OCR text snippets that match the query
        let textResults = try await databaseService.searchByText(query, limit: limit)
        
        var suggestions: Set<String> = []
        
        for result in textResults {
            // Extract words from snippets
            let words = result.snippet
                .replacingOccurrences(of: "<b>", with: "")
                .replacingOccurrences(of: "</b>", with: "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.lowercased().contains(query.lowercased()) && $0.count > 2 }
            
            for word in words {
                suggestions.insert(word.lowercased())
            }
        }
        
        return Array(suggestions.prefix(limit)).sorted()
    }
}

// MARK: - Search Statistics

extension SearchEngine {
    /// Get search statistics
    func getStatistics() async -> SearchStatistics {
        let indexSize = await vectorService.indexSize
        let imageCount = (try? await databaseService.getImageCount()) ?? 0
        
        return SearchStatistics(
            totalImages: imageCount,
            indexedVectors: indexSize
        )
    }
}

/// Search statistics
struct SearchStatistics {
    let totalImages: Int
    let indexedVectors: Int
    
    var isFullyIndexed: Bool {
        totalImages == indexedVectors
    }
}
