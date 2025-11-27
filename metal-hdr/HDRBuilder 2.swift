import Foundation
import Metal
import MetalKit
import CoreImage
import UIKit

class HDRProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    private let ciContext: CIContext

    private let exposureAdjustPipeline: MTLComputePipelineState
    private let toneMappingPipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
        
        // Initialize CIContext with linear sRGB working and output color spaces for linear workflow
        let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB)!
        self.ciContext = CIContext(options: [
            .workingColorSpace: linearSRGB,
            .outputColorSpace: linearSRGB
        ])

        do {
            exposureAdjustPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "exposureAdjust")!)
            toneMappingPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "toneMapping")!)
        } catch {
            return nil
        }
    }

    // Linear space rendering of a CIImage into a Metal texture with rgba16Float pixel format
    private func createTexture(from ciImage: CIImage) -> MTLTexture? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: desc),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        ciContext.render(ciImage, to: texture, commandBuffer: commandBuffer, bounds: ciImage.extent, colorSpace: linear)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }

    // Create Metal texture from UIImage by creating CIImage and rendering linearly
    private func createTexture(from image: UIImage) -> MTLTexture? {
        guard let ciImage = CIImage(image: image) else { return nil }
        return createTexture(from: ciImage)
    }

    // Create a new texture like the given one, defaulting to rgba16Float pixel format
    private func makeTexture(like texture: MTLTexture, pixelFormat: MTLPixelFormat? = nil) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat ?? .rgba16Float,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: desc)
    }

    // Normalize exposures in linear space applying EV normalization using exposureAdjustPipeline and bracket biases
    private func normalizeExposures(_ textures: [MTLTexture]) -> [MTLTexture] {
        // Expected order: [-2, -1, 0, 1, 2]
        let expectedBiases: [Float] = [-2, -1, 0, 1, 2]
        let biases: [Float] = textures.count == expectedBiases.count ? expectedBiases : Array(repeating: 0, count: textures.count).map { Float($0) }
        var outputs: [MTLTexture] = []
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return textures }
        for (i, tex) in textures.enumerated() {
            let multiplier = powf(2.0, -biases[i])
            guard let out = makeTexture(like: tex, pixelFormat: .rgba16Float),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                outputs.append(tex)
                continue
            }
            encoder.setComputePipelineState(exposureAdjustPipeline)
            encoder.setTexture(tex, index: 0)
            encoder.setTexture(out, index: 1)
            var m = multiplier
            encoder.setBytes(&m, length: MemoryLayout<Float>.size, index: 0)
            dispatchThreads(encoder: encoder, texture: tex)
            encoder.endEncoding()
            outputs.append(out)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputs
    }

    // Create UIImage from Metal texture assuming already gamma-encoded; no extra gamma applied here
    private func createImage(from texture: MTLTexture) -> UIImage? {
        let ciImage = CIImage(mtlTexture: texture, options: [CIImageOption.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])?.oriented(.up)
        guard let ciImageUnwrapped = ciImage else { return nil }
        // Render to CGImage in sRGB for UIImage
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgImage = ciContext.createCGImage(ciImageUnwrapped, from: ciImageUnwrapped.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // Example placeholder for dispatching threadgroups (implementation assumed elsewhere)
    private func dispatchThreads(encoder: MTLComputeCommandEncoder, texture: MTLTexture) {
        let w = exposureAdjustPipeline.threadExecutionWidth
        let h = exposureAdjustPipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadgroups = MTLSize(
            width: (texture.width + w - 1) / w,
            height: (texture.height + h - 1) / h,
            depth: 1)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    // Apply tone mapping to input texture; ensure output texture uses rgba16Float format for linear float output
    func applyToneMapping(to texture: MTLTexture, mode: ToneMappingMode) -> MTLTexture? {
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: texture.width, height: texture.height, mipmapped: false)
        outputDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let outputTexture = device.makeTexture(descriptor: outputDesc),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(toneMappingPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        var modeRaw = mode.rawValue
        encoder.setBytes(&modeRaw, length: MemoryLayout<Int>.size, index: 0)

        let w = toneMappingPipeline.threadExecutionWidth
        let h = toneMappingPipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadgroups = MTLSize(
            width: (texture.width + w - 1) / w,
            height: (texture.height + h - 1) / h,
            depth: 1)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outputTexture
    }

    enum ToneMappingMode: Int {
        case reinhard = 0
        case filmic = 1
        case aces = 2
    }
}
