//
//  NSImage+Extensions.swift
//  SemanticImageSearch
//
//  NSImage utility extensions.
//

import AppKit
import CoreGraphics

extension NSImage {
    /// Get CGImage representation
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    func resized(toMaxDimension maxDimension: CGFloat) -> NSImage? {
        let currentSize = size
        
        guard currentSize.width > 0 && currentSize.height > 0 else {
            return nil
        }
        
        // Calculate new size
        let aspectRatio = currentSize.width / currentSize.height
        var newSize: NSSize
        
        if currentSize.width > currentSize.height {
            newSize = NSSize(
                width: min(currentSize.width, maxDimension),
                height: min(currentSize.width, maxDimension) / aspectRatio
            )
        } else {
            newSize = NSSize(
                width: min(currentSize.height, maxDimension) * aspectRatio,
                height: min(currentSize.height, maxDimension)
            )
        }
        
        // Create resized image
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: currentSize),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Resize image to exact dimensions
    func resized(to size: NSSize) -> NSImage? {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        
        draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Convert to JPEG data
    func jpegData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let cgImage = cgImage else { return nil }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
    
    /// Convert to PNG data
    func pngData() -> Data? {
        guard let cgImage = cgImage else { return nil }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
    
    /// Create a thumbnail with rounded corners
    func thumbnail(size: CGFloat, cornerRadius: CGFloat = 8) -> NSImage? {
        guard let resized = resized(toMaxDimension: size) else {
            return nil
        }
        
        let newImage = NSImage(size: resized.size)
        newImage.lockFocus()
        
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: resized.size),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.addClip()
        
        resized.draw(
            in: NSRect(origin: .zero, size: resized.size),
            from: NSRect(origin: .zero, size: resized.size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    /// Crop image to square (center crop)
    func croppedToSquare() -> NSImage? {
        let minDimension = min(size.width, size.height)
        let cropRect = NSRect(
            x: (size.width - minDimension) / 2,
            y: (size.height - minDimension) / 2,
            width: minDimension,
            height: minDimension
        )
        
        guard let cgImage = cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        return NSImage(cgImage: croppedCGImage, size: NSSize(width: minDimension, height: minDimension))
    }
}

// MARK: - Color Analysis

extension NSImage {
    /// Get the dominant color of the image
    var dominantColor: NSColor? {
        guard let cgImage = cgImage else { return nil }
        
        let width = 10
        let height = 10
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        var totalR: Int = 0
        var totalG: Int = 0
        var totalB: Int = 0
        
        for i in 0..<(width * height) {
            let offset = i * 4
            totalR += Int(pixels[offset])
            totalG += Int(pixels[offset + 1])
            totalB += Int(pixels[offset + 2])
        }
        
        let count = width * height
        
        return NSColor(
            red: CGFloat(totalR) / CGFloat(count * 255),
            green: CGFloat(totalG) / CGFloat(count * 255),
            blue: CGFloat(totalB) / CGFloat(count * 255),
            alpha: 1.0
        )
    }
}
