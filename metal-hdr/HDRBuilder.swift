//
//  HDRBuilder.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//


import Metal
import MetalKit
import CoreImage
import Accelerate

class HDRBuilder {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let ciContext: CIContext
    
    // Pipeline states
    private var computeWeightsPipeline: MTLComputePipelineState!
    private var mergePipeline: MTLComputePipelineState!
    private var reinhardToneMapPipeline: MTLComputePipelineState!
    private var acesToneMapPipeline: MTLComputePipelineState!
    private var exposureAdjustPipeline: MTLComputePipelineState!
    
    // MARK: - Initialization
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }
        
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            print("Failed to create command queue")
            return nil
        }
        self.commandQueue = queue
        
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return nil
        }
        self.library = library
        
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .cacheIntermediates: false
        ])
        
        setupPipelines()
    }
    
    private func setupPipelines() {
        do {
            // Compute weights pipeline
            let weightsFunction = library.makeFunction(name: "computeExposureWeights")!
            computeWeightsPipeline = try device.makeComputePipelineState(function: weightsFunction)
            
            // Merge pipeline
            let mergeFunction = library.makeFunction(name: "weightedMerge")!
            mergePipeline = try device.makeComputePipelineState(function: mergeFunction)
            
            // Tone mapping pipelines
            let reinhardFunction = library.makeFunction(name: "reinhardToneMap")!
            reinhardToneMapPipeline = try device.makeComputePipelineState(function: reinhardFunction)
            
            let acesFunction = library.makeFunction(name: "acesToneMap")!
            acesToneMapPipeline = try device.makeComputePipelineState(function: acesFunction)
            
            // Exposure adjustment
            let exposureFunction = library.makeFunction(name: "adjustExposure")!
            exposureAdjustPipeline = try device.makeComputePipelineState(function: exposureFunction)
            
        } catch {
            fatalError("Failed to create pipeline states: \(error)")
        }
    }
    
    // MARK: - Public API
    
    enum ToneMappingMode {
        case reinhard(exposure: Float)
        case aces
    }
    
    func buildHDR(
        from images: [UIImage],
        alignment: Bool = true,
        toneMapping: ToneMappingMode = .reinhard(exposure: 1.0)
    ) -> UIImage? {
        
        guard !images.isEmpty else { return nil }
        let textures = images.compactMap({ createTexture(from: $0) })
        
        // Convert UIImages to Metal textures
        guard textures.count == images.count else {
            print("Failed to convert images to textures")
            return nil
        }
        
        // Align images if requested
        let alignedTextures: [MTLTexture]
        if alignment && textures.count > 1 {
            alignedTextures = alignImages(textures, referenceIndex: textures.count / 2)
        } else {
            alignedTextures = textures
        }
        
        // Normalize exposures (assume images are ordered from dark to bright)
        let normalizedTextures = normalizeExposures(alignedTextures)
        
        // Compute weights for each image
        guard let weights = computeWeights(for: normalizedTextures) else {
            print("Failed to compute weights")
            return nil
        }
        
        // Merge images
        guard let mergedTexture = mergeImages(normalizedTextures, weights: weights) else {
            print("Failed to merge images")
            return nil
        }
        
        // Tone mapping
        guard let toneMappedTexture = applyToneMapping(to: mergedTexture, mode: toneMapping) else {
            print("Failed to apply tone mapping")
            return nil
        }
        
        // Convert back to UIImage
        return createImage(from: toneMappedTexture)
    }
    
    // MARK: - Pipeline Steps
    
    private func normalizeExposures(_ textures: [MTLTexture]) -> [MTLTexture] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return textures
        }
        
        var normalizedTextures: [MTLTexture] = []
        let middleIndex = textures.count / 2
        
        for (index, texture) in textures.enumerated() {
            // Calculate exposure offset from middle image
            let evOffset = Float(index - middleIndex)
            let exposureMultiplier = pow(2.0, -evOffset)
            
            guard let normalizedTexture = makeTexture(like: texture),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                normalizedTextures.append(texture)
                continue
            }
            
            encoder.setComputePipelineState(exposureAdjustPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(normalizedTexture, index: 1)
            
            var exposure = exposureMultiplier
            encoder.setBytes(&exposure, length: MemoryLayout<Float>.stride, index: 0)
            
            dispatchThreads(encoder: encoder, texture: texture)
            encoder.endEncoding()
            
            normalizedTextures.append(normalizedTexture)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return normalizedTextures
    }
    
    private func computeWeights(for textures: [MTLTexture]) -> [MTLTexture]? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        var weightTextures: [MTLTexture] = []
        
        for texture in textures {
            guard let weightTexture = makeTexture(like: texture, pixelFormat: .r32Float),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                return nil
            }
            
            encoder.setComputePipelineState(computeWeightsPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(weightTexture, index: 1)
            
            var sigma: Float = 0.2
            encoder.setBytes(&sigma, length: MemoryLayout<Float>.stride, index: 0)
            
            dispatchThreads(encoder: encoder, texture: texture)
            encoder.endEncoding()
            
            weightTextures.append(weightTexture)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return weightTextures
    }
    
    private func mergeImages(_ images: [MTLTexture], weights: [MTLTexture]) -> MTLTexture? {
        guard images.count == weights.count,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let outputTexture = makeTexture(like: images[0]) else {
            return nil
        }
        
        encoder.setComputePipelineState(mergePipeline)
        
        // Set input textures
        for (index, texture) in images.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        
        // Set weight textures
        for (index, texture) in weights.enumerated() {
            encoder.setTexture(texture, index: images.count + index)
        }
        
        // Set output texture
        encoder.setTexture(outputTexture, index: images.count + weights.count)
        
        // Set number of images
        var numImages = Int32(images.count)
        encoder.setBytes(&numImages, length: MemoryLayout<Int32>.stride, index: 0)
        
        dispatchThreads(encoder: encoder, texture: images[0])
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
    
    private func applyToneMapping(to texture: MTLTexture, mode: ToneMappingMode) -> MTLTexture? {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let outputTexture = makeTexture(like: texture) else {
            return nil
        }
        
        switch mode {
        case .reinhard(let exposure):
            encoder.setComputePipelineState(reinhardToneMapPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(outputTexture, index: 1)
            var exp = exposure
            encoder.setBytes(&exp, length: MemoryLayout<Float>.stride, index: 0)
            
        case .aces:
            encoder.setComputePipelineState(acesToneMapPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(outputTexture, index: 1)
        }
        
        dispatchThreads(encoder: encoder, texture: texture)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
    
    // MARK: - Image Alignment
    
    private func alignImages(_ textures: [MTLTexture], referenceIndex: Int) -> [MTLTexture] {
        guard referenceIndex < textures.count else {
            return textures
        }
        
        let aligner = ImageAlignment()
        let reference = textures[referenceIndex]
        
        var aligned: [MTLTexture] = []
        
        for (index, texture) in textures.enumerated() {
            if index == referenceIndex {
                aligned.append(texture)
            } else {
                if let alignedTexture = aligner.align(texture, to: reference, device: device, commandQueue: commandQueue) {
                    aligned.append(alignedTexture)
                } else {
                    aligned.append(texture)
                }
            }
        }
        
        return aligned
    }
    
    // MARK: - Utilities
    
    private func createTexture(from image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false // Important: work in linear space
        ]
        
        return try? textureLoader.newTexture(cgImage: cgImage, options: options)
    }
    
    private func makeTexture(like texture: MTLTexture, pixelFormat: MTLPixelFormat? = nil) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat ?? texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        
        return device.makeTexture(descriptor: descriptor)
    }
    
    private func dispatchThreads(encoder: MTLComputeCommandEncoder, texture: MTLTexture) {
        let threadGroupSize = MTLSize(
            width: 16,
            height: 16,
            depth: 1
        )
        
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }
    
    private func createImage(from texture: MTLTexture) -> UIImage? {
        // Don't specify colorspace when creating CIImage - let it use the texture's format
        guard let ciImage = CIImage(mtlTexture: texture, options: nil) else {
            return nil
        }

        // Explicitly use sRGB for the final render since tone mapping already converted to gamma-corrected space
        guard let cgImage = ciContext.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
