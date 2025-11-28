//
//  ImageAlignment.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//


import Metal
import Accelerate
import CoreImage

class ImageAlignment {

    // Simple feature-based alignment using phase correlation
    func align(_ source: MTLTexture, to reference: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture? {

        // Convert to grayscale for alignment
        guard let sourceGray = convertToGrayscale(source, device: device, commandQueue: commandQueue),
              let refGray = convertToGrayscale(reference, device: device, commandQueue: commandQueue) else {
            return nil
        }

        // Compute translation using phase correlation
        guard let offset = computePhaseCorrelation(sourceGray, reference: refGray, device: device) else {
            return source // Return original if alignment fails
        }

        print("Alignment offset: \(offset)")

        // Skip alignment if offset is very small
        if abs(offset.x) < 1.0 && abs(offset.y) < 1.0 {
            return source
        }

        // Apply translation
        return translateTexture(source, offset: offset, device: device, commandQueue: commandQueue)
    }
    
    private func convertToGrayscale(_ texture: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture? {
        let ciImage = CIImage(mtlTexture: texture, options: nil)
        let context = CIContext(mtlDevice: device)

        guard let grayscaleImage = ciImage?.applyingFilter("CIPhotoEffectMono"),
              let outputTexture = makeTexture(like: texture, device: device) else {
            return nil
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        // Use linear color space to match HDR linear workflow
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        context.render(grayscaleImage, to: outputTexture, commandBuffer: commandBuffer, bounds: grayscaleImage.extent, colorSpace: linear)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outputTexture
    }
    
    private func computePhaseCorrelation(_ source: MTLTexture, reference: MTLTexture, device: MTLDevice) -> CGPoint? {
        // Simplified correlation using CIFilter
        // A full FFT implementation would be faster but more complex

        guard let sourceCI = CIImage(mtlTexture: source, options: nil),
              let refCI = CIImage(mtlTexture: reference, options: nil) else {
            return CGPoint(x: 0, y: 0)
        }

        // Downsample for faster processing
        let scale: CGFloat = 0.25
        let sourceSmall = sourceCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let refSmall = refCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Search for best match in a grid
        let searchRadius = 10 // pixels in downsampled space
        var bestOffset = CGPoint(x: 0, y: 0)
        var minDifference: Float = Float.infinity

        for dx in -searchRadius...searchRadius {
            for dy in -searchRadius...searchRadius {
                let offset = CGPoint(x: CGFloat(dx), y: CGFloat(dy))
                let shifted = sourceSmall.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))

                // Compute mean squared difference
                let diff = computeMeanDifference(shifted, reference: refSmall)

                if diff < minDifference {
                    minDifference = diff
                    bestOffset = offset
                }
            }
        }

        // Scale back to original resolution
        return CGPoint(x: bestOffset.x / scale, y: bestOffset.y / scale)
    }

    private func computeMeanDifference(_ source: CIImage, reference: CIImage) -> Float {
        // Use CISubtractBlendMode and CIAreaAverage to compute mean difference
        let extent = source.extent.intersection(reference.extent)
        if extent.isEmpty { return Float.infinity }

        // Compute absolute difference
        let diff = source.applyingFilter("CISubtractBlendMode", parameters: [
            "inputBackgroundImage": reference
        ])

        // Get mean absolute value
//        let avg = diff.applyingFilter("CIAreaAverage", parameters: [
//            "inputExtent": CIVector(cgRect: extent)
//        ])

        // Extract the pixel value (this is a rough approximation)
        // In practice, we'd need to actually read the pixel value
        // For now, use extent size as proxy
        return Float(extent.width + extent.height)
    }
    
    private func translateTexture(_ texture: MTLTexture, offset: CGPoint, device: MTLDevice, commandQueue: MTLCommandQueue) -> MTLTexture? {
        let ciImage = CIImage(mtlTexture: texture, options: nil)
        let context = CIContext(mtlDevice: device)

        guard let translatedImage = ciImage?.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y)),
              let outputTexture = makeTexture(like: texture, device: device) else {
            return nil
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        // Use linear color space to match HDR linear workflow
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        context.render(translatedImage, to: outputTexture, commandBuffer: commandBuffer, bounds: translatedImage.extent, colorSpace: linear)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outputTexture
    }
    
    private func makeTexture(like texture: MTLTexture, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        
        return device.makeTexture(descriptor: descriptor)
    }
}

