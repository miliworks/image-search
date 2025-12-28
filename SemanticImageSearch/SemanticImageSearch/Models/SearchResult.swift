//
//  SearchResult.swift
//  SemanticImageSearch
//
//  Data model representing a search result.
//

import Foundation

/// Represents a search result with relevance scoring
struct SearchResult: Identifiable, Equatable {
    /// Unique identifier (same as image ID)
    var id: UUID { image.id }
    
    /// The matched image
    let image: ImageItem
    
    /// Semantic similarity score (0-1, higher is better)
    let semanticScore: Float
    
    /// Text match score (0-1, higher is better)
    let textScore: Float
    
    /// Combined score
    let combinedScore: Float
    
    /// Matched text snippets (for highlighting)
    let matchedSnippets: [String]
    
    // MARK: - Computed Properties
    
    /// Overall relevance percentage
    var relevancePercentage: Int {
        Int(combinedScore * 100)
    }
    
    /// Formatted relevance string
    var relevanceString: String {
        "\(relevancePercentage)% match"
    }
    
    // MARK: - Equatable
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Comparable

extension SearchResult: Comparable {
    static func < (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.combinedScore < rhs.combinedScore
    }
}

// MARK: - Factory

extension SearchResult {
    /// Create a search result with only semantic score
    static func semantic(_ image: ImageItem, score: Float) -> SearchResult {
        SearchResult(
            image: image,
            semanticScore: score,
            textScore: 0,
            combinedScore: score,
            matchedSnippets: []
        )
    }
    
    /// Create a search result with only text score
    static func text(_ image: ImageItem, score: Float, snippets: [String]) -> SearchResult {
        SearchResult(
            image: image,
            semanticScore: 0,
            textScore: score,
            combinedScore: score,
            matchedSnippets: snippets
        )
    }
    
    /// Create a combined search result
    static func combined(
        _ image: ImageItem,
        semanticScore: Float,
        textScore: Float,
        snippets: [String],
        semanticWeight: Float = 0.7
    ) -> SearchResult {
        let textWeight = 1.0 - semanticWeight
        let combined = semanticScore * semanticWeight + textScore * textWeight
        
        return SearchResult(
            image: image,
            semanticScore: semanticScore,
            textScore: textScore,
            combinedScore: combined,
            matchedSnippets: snippets
        )
    }
}
