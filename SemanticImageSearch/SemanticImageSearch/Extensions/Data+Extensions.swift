//
//  Data+Extensions.swift
//  SemanticImageSearch
//
//  Data utility extensions.
//

import Foundation

extension Data {
    /// Convert data to hex string
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    
    /// Initialize from hex string
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    /// Convert float array to data
    init(floats: [Float]) {
        self = floats.withUnsafeBytes { Data($0) }
    }
    
    /// Convert data to float array
    func toFloats() -> [Float] {
        withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}

// MARK: - Compression

extension Data {
    /// Compress data using LZFSE
    func compressed() -> Data? {
        try? (self as NSData).compressed(using: .lzfse) as Data
    }
    
    /// Decompress data using LZFSE
    func decompressed() -> Data? {
        try? (self as NSData).decompressed(using: .lzfse) as Data
    }
}
