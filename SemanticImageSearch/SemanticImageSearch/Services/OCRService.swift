//
//  OCRService.swift
//  SemanticImageSearch
//
//  Service for extracting text from images using Vision framework.
//

import Foundation
import Vision
import AppKit

/// Service for OCR (Optical Character Recognition)
actor OCRService {
    static let shared = OCRService()
    
    // MARK: - Properties
    
    /// Supported languages for OCR
    private let recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]
    
    /// Minimum confidence threshold for text recognition
    private let confidenceThreshold: Float = 0.5
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Text Extraction
    
    /// Extract text from an image at URL
    func extractText(from url: URL) async throws -> String? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        return try await extractText(from: cgImage)
    }
    
    /// Extract text from an NSImage
    func extractText(from image: NSImage) async throws -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        return try await extractText(from: cgImage)
    }
    
    /// Extract text from a CGImage
    func extractText(from cgImage: CGImage) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Extract text from observations
                var extractedTexts: [String] = []
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first,
                          topCandidate.confidence >= self.confidenceThreshold else {
                        continue
                    }
                    
                    extractedTexts.append(topCandidate.string)
                }
                
                let combinedText = extractedTexts.joined(separator: " ")
                let result = combinedText.isEmpty ? nil : combinedText
                
                continuation.resume(returning: result)
            }
            
            // Configure the request
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = recognitionLanguages
            
            // Use revision 3 for better accuracy on macOS 13+
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Extract text with position information
    func extractTextWithPositions(from cgImage: CGImage) async throws -> [TextRegion] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var regions: [TextRegion] = []
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first,
                          topCandidate.confidence >= self.confidenceThreshold else {
                        continue
                    }
                    
                    let region = TextRegion(
                        text: topCandidate.string,
                        confidence: topCandidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                    
                    regions.append(region)
                }
                
                continuation.resume(returning: regions)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = recognitionLanguages
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Check if text recognition is available
    func isAvailable() -> Bool {
        return VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequestRevision3
        ).count > 0
    }
}

// MARK: - Supporting Types

/// Represents a detected text region
struct TextRegion {
    /// The recognized text
    let text: String
    
    /// Confidence score (0-1)
    let confidence: Float
    
    /// Bounding box in normalized coordinates (0-1)
    let boundingBox: CGRect
}

// MARK: - Text Utilities

extension OCRService {
    /// Clean and normalize extracted text
    func cleanText(_ text: String) -> String {
        // Remove excessive whitespace
        let cleaned = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract keywords from text
    func extractKeywords(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
        
        // Remove common stop words
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
            "be", "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "dare", "ought",
            "used", "this", "that", "these", "those", "it", "its"
        ]
        
        return words.filter { !stopWords.contains($0) }
    }
}
