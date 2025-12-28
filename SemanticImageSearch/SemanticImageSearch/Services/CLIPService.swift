//
//  CLIPService.swift
//  SemanticImageSearch
//
//  CLIP model service for generating image and text embeddings.
//

import Foundation
import CoreML
import Vision
import AppKit

/// Configuration for CLIP model
struct CLIPConfig: Codable {
    let modelName: String
    let imageSize: Int
    let embeddingDim: Int
    let maxTextLength: Int
    let mean: [Float]
    let std: [Float]
    let imageEncoder: String
    let textEncoder: String
    let vocabFile: String
    
    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case imageSize = "image_size"
        case embeddingDim = "embedding_dim"
        case maxTextLength = "max_text_length"
        case mean, std
        case imageEncoder = "image_encoder"
        case textEncoder = "text_encoder"
        case vocabFile = "vocab_file"
    }
    
    static let `default` = CLIPConfig(
        modelName: "openai/clip-vit-base-patch32",
        imageSize: 224,
        embeddingDim: 512,
        maxTextLength: 77,
        mean: [0.48145466, 0.4578275, 0.40821073],
        std: [0.26862954, 0.26130258, 0.27577711],
        imageEncoder: "CLIPImageEncoder",
        textEncoder: "CLIPTextEncoder",
        vocabFile: "clip_vocab.json"
    )
}

/// CLIP tokenizer for text encoding
final class CLIPTokenizer {
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private let maxLength: Int
    
    // Special tokens
    private let startToken = "<|startoftext|>"
    private let endToken = "<|endoftext|>"
    private let padToken = "<|endoftext|>"
    
    init(vocabPath: URL, maxLength: Int = 77) throws {
        self.maxLength = maxLength
        
        let data = try Data(contentsOf: vocabPath)
        vocab = try JSONDecoder().decode([String: Int].self, from: data)
        
        for (token, id) in vocab {
            reverseVocab[id] = token
        }
    }
    
    /// Tokenize text to token IDs
    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = []
        
        // Add start token
        if let startId = vocab[startToken] {
            tokens.append(startId)
        }
        
        // Simple whitespace tokenization (for production, use BPE)
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        for word in words {
            // Try to find the word in vocab
            if let tokenId = vocab[word] {
                tokens.append(tokenId)
            } else {
                // Character-level fallback
                for char in word {
                    let charStr = String(char)
                    if let charId = vocab[charStr] {
                        tokens.append(charId)
                    }
                }
            }
            
            // Add space token if available
            if let spaceId = vocab["</w>"] {
                tokens.append(spaceId)
            }
        }
        
        // Add end token
        if let endId = vocab[endToken] {
            tokens.append(endId)
        }
        
        // Pad or truncate to maxLength
        if tokens.count > maxLength {
            tokens = Array(tokens.prefix(maxLength - 1))
            if let endId = vocab[endToken] {
                tokens.append(endId)
            }
        } else {
            let padId = vocab[padToken] ?? 0
            while tokens.count < maxLength {
                tokens.append(padId)
            }
        }
        
        return tokens
    }
    
    /// Create attention mask for tokens
    func createAttentionMask(_ tokens: [Int]) -> [Int] {
        let padId = vocab[padToken] ?? 0
        return tokens.map { $0 != padId ? 1 : 0 }
    }
}

/// CLIP model service
actor CLIPService {
    static let shared = CLIPService()
    
    // MARK: - Properties
    
    private var imageEncoder: MLModel?
    private var textEncoder: MLModel?
    private var tokenizer: CLIPTokenizer?
    private var config: CLIPConfig = .default
    private var isInitialized = false
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initialize CLIP models
    func initialize() async throws {
        guard !isInitialized else { return }
        
        // Load config
        if let configURL = Bundle.main.url(forResource: "clip_config", withExtension: "json"),
           let configData = try? Data(contentsOf: configURL),
           let loadedConfig = try? JSONDecoder().decode(CLIPConfig.self, from: configData) {
            config = loadedConfig
        }
        
        // Try to load image encoder
        if let imageEncoderURL = Bundle.main.url(forResource: config.imageEncoder, withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: config.imageEncoder, withExtension: "mlpackage") {
            do {
                let compiledURL = try await compileModelIfNeeded(imageEncoderURL)
                imageEncoder = try MLModel(contentsOf: compiledURL)
                print("✅ CLIP Image Encoder loaded")
            } catch {
                print("⚠️ Failed to load CLIP Image Encoder: \(error)")
            }
        }
        
        // Try to load text encoder
        if let textEncoderURL = Bundle.main.url(forResource: config.textEncoder, withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: config.textEncoder, withExtension: "mlpackage") {
            do {
                let compiledURL = try await compileModelIfNeeded(textEncoderURL)
                textEncoder = try MLModel(contentsOf: compiledURL)
                print("✅ CLIP Text Encoder loaded")
            } catch {
                print("⚠️ Failed to load CLIP Text Encoder: \(error)")
            }
        }
        
        // Load tokenizer
        if let vocabURL = Bundle.main.url(forResource: "clip_vocab", withExtension: "json") {
            do {
                tokenizer = try CLIPTokenizer(vocabPath: vocabURL, maxLength: config.maxTextLength)
                print("✅ CLIP Tokenizer loaded")
            } catch {
                print("⚠️ Failed to load tokenizer: \(error)")
            }
        }
        
        isInitialized = true
    }
    
    /// Compile model if needed
    private func compileModelIfNeeded(_ url: URL) async throws -> URL {
        if url.pathExtension == "mlmodelc" {
            return url
        }
        
        // Compile mlpackage to temporary location
        let compiledURL = try await MLModel.compileModel(at: url)
        return compiledURL
    }
    
    // MARK: - Image Embedding
    
    /// Generate embedding for an image using CLIP
    func encodeImage(_ image: NSImage) throws -> [Float] {
        guard let imageEncoder = imageEncoder else {
            throw CLIPError.modelNotLoaded
        }
        
        // Preprocess image
        guard let pixelBuffer = preprocessImage(image) else {
            throw CLIPError.preprocessingFailed
        }
        
        // Create MLMultiArray from pixel buffer
        let inputArray = try createMLMultiArray(from: pixelBuffer)
        
        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": inputArray])
        let output = try imageEncoder.prediction(from: input)
        
        // Extract embedding
        guard let embeddingFeature = output.featureValue(for: "embedding"),
              let embeddingArray = embeddingFeature.multiArrayValue else {
            throw CLIPError.outputExtractionFailed
        }
        
        return multiArrayToFloats(embeddingArray)
    }
    
    /// Generate embedding for an image at URL
    func encodeImage(at url: URL) throws -> [Float] {
        guard let image = NSImage(contentsOf: url) else {
            throw CLIPError.invalidImage
        }
        return try encodeImage(image)
    }
    
    // MARK: - Text Embedding
    
    /// Generate embedding for text using CLIP
    func encodeText(_ text: String) throws -> [Float] {
        guard let textEncoder = textEncoder,
              let tokenizer = tokenizer else {
            throw CLIPError.modelNotLoaded
        }
        
        // Tokenize text
        let tokens = tokenizer.encode(text)
        let attentionMask = tokenizer.createAttentionMask(tokens)
        
        // Create MLMultiArrays
        let inputIds = try createMLMultiArray(from: tokens)
        let maskArray = try createMLMultiArray(from: attentionMask)
        
        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIds,
            "attention_mask": maskArray
        ])
        let output = try textEncoder.prediction(from: input)
        
        // Extract embedding
        guard let embeddingFeature = output.featureValue(for: "embedding"),
              let embeddingArray = embeddingFeature.multiArrayValue else {
            throw CLIPError.outputExtractionFailed
        }
        
        return multiArrayToFloats(embeddingArray)
    }
    
    // MARK: - Preprocessing
    
    /// Preprocess image for CLIP
    private func preprocessImage(_ image: NSImage) -> CVPixelBuffer? {
        let targetSize = config.imageSize
        
        // Resize image
        guard let resized = image.resized(to: NSSize(width: targetSize, height: targetSize)),
              let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetSize,
            targetSize,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        
        return buffer
    }
    
    /// Create MLMultiArray from pixel buffer
    private func createMLMultiArray(from pixelBuffer: CVPixelBuffer) throws -> MLMultiArray {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Create array with shape [1, 3, height, width]
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CLIPError.preprocessingFailed
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Convert ARGB to normalized RGB with CLIP preprocessing
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                
                let r = Float(buffer[offset + 1]) / 255.0
                let g = Float(buffer[offset + 2]) / 255.0
                let b = Float(buffer[offset + 3]) / 255.0
                
                // Normalize with CLIP mean and std
                let normalizedR = (r - config.mean[0]) / config.std[0]
                let normalizedG = (g - config.mean[1]) / config.std[1]
                let normalizedB = (b - config.mean[2]) / config.std[2]
                
                let index = y * width + x
                array[[0, 0, NSNumber(value: y), NSNumber(value: x)] as [NSNumber]] = NSNumber(value: normalizedR)
                array[[0, 1, NSNumber(value: y), NSNumber(value: x)] as [NSNumber]] = NSNumber(value: normalizedG)
                array[[0, 2, NSNumber(value: y), NSNumber(value: x)] as [NSNumber]] = NSNumber(value: normalizedB)
            }
        }
        
        return array
    }
    
    /// Create MLMultiArray from int array
    private func createMLMultiArray(from ints: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: ints.count)], dataType: .int32)
        
        for (index, value) in ints.enumerated() {
            array[[0, NSNumber(value: index)] as [NSNumber]] = NSNumber(value: value)
        }
        
        return array
    }
    
    /// Convert MLMultiArray to float array
    private func multiArrayToFloats(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = pointer[i]
        }
        
        return result
    }
    
    // MARK: - Status
    
    /// Check if CLIP models are available
    var isAvailable: Bool {
        imageEncoder != nil && textEncoder != nil
    }
    
    /// Get embedding dimension
    var embeddingDimension: Int {
        config.embeddingDim
    }
}

// MARK: - Errors

enum CLIPError: Error, LocalizedError {
    case modelNotLoaded
    case invalidImage
    case preprocessingFailed
    case outputExtractionFailed
    case tokenizationFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "CLIP model not loaded"
        case .invalidImage:
            return "Invalid image"
        case .preprocessingFailed:
            return "Image preprocessing failed"
        case .outputExtractionFailed:
            return "Failed to extract model output"
        case .tokenizationFailed:
            return "Text tokenization failed"
        }
    }
}
