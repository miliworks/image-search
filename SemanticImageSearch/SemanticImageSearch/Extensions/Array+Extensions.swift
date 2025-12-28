//
//  Array+Extensions.swift
//  SemanticImageSearch
//
//  Array utility extensions.
//

import Foundation

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
    
    /// Safe subscript that returns nil for out-of-bounds access
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    /// Remove duplicates while preserving order
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array where Element == Float {
    /// Calculate L2 norm of the array
    var l2Norm: Float {
        sqrt(reduce(0) { $0 + $1 * $1 })
    }
    
    /// Normalize the array to unit length
    func normalized() -> [Float] {
        let norm = l2Norm
        guard norm > 0 else { return self }
        return map { $0 / norm }
    }
    
    /// Calculate dot product with another array
    func dot(_ other: [Float]) -> Float {
        guard count == other.count else { return 0 }
        return zip(self, other).reduce(0) { $0 + $1.0 * $1.1 }
    }
    
    /// Calculate cosine similarity with another array
    func cosineSimilarity(with other: [Float]) -> Float {
        let dotProduct = dot(other)
        let normProduct = l2Norm * other.l2Norm
        guard normProduct > 0 else { return 0 }
        return dotProduct / normProduct
    }
}
