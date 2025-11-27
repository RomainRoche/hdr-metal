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
        guard let offset = computePhaseCorrelation(sourceGray, reference: refGray) else {
            return source // Return original if alignment fails
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
    
    private func computePhaseCorrelation(_ source: MTLTexture, reference: MTLTexture) -> CGPoint? {
        // Simplified: just compute basic cross-correlation
        // For production, you'd want FFT-based phase correlation
        
        // For now, return a simple center-based approach
        // In a real implementation, you'd:
        // 1. Compute FFT of both images
        // 2. Compute cross-power spectrum
        // 3. Find peak in IFFT
        
        return CGPoint(x: 0, y: 0) // Placeholder
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

