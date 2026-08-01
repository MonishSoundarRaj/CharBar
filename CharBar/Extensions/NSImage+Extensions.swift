//
//  NSImage+Extensions.swift
//  CharBar
//
//  Extracts dominant color from album artwork for adaptive backgrounds
//

import AppKit
import SwiftUI

extension NSImage {
    /// Extracts the average/dominant color from the image using Core Image
    /// This is computationally efficient - resizes to 1x1 pixel and reads that color
    var averageColor: Color {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .gray
        }
        
        // 1. Create CIImage from CGImage
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        
        // 2. Apply CIAreaAverage filter to get single pixel
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: inputExtent
        ]),
        let outputImage = filter.outputImage else {
            return .gray
        }
        
        // 3. Read the color data from the 1x1 pixel
        var bitmap = [UInt8](repeating: 0, count: 4)
        let renderContext = CIContext(options: [.workingColorSpace: kCFNull as Any])
        renderContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        
        // 4. Convert to SwiftUI Color
        return Color(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0,
            opacity: 1.0
        )
    }
    
    /// Extracts dominant color with saturation boost for more vibrant backgrounds
    var vibrantColor: Color {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .gray
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: inputExtent
        ]),
        let outputImage = filter.outputImage else {
            return .gray
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let renderContext = CIContext(options: [.workingColorSpace: kCFNull as Any])
        renderContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        
        // Convert to HSB and boost saturation
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        
        var h: Double = 0
        var s: Double = 0
        let v = maxC
        
        if delta > 0 {
            s = delta / maxC
            
            if maxC == r {
                h = (g - b) / delta + (g < b ? 6 : 0)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
        }
        
        // Boost saturation by 20% (capped at 1.0)
        let boostedS = min(s * 1.2, 1.0)
        
        return Color(hue: h, saturation: boostedS, brightness: v)
    }
}



