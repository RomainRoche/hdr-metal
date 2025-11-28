import UIKit
import Metal
import CoreImage

class HDRBuilderTer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let exposureAdjustPipeline: MTLComputePipelineState
    private let ciContext: CIContext

    private var currentEVBiases: [Float]? = nil

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)

        let library = device.makeDefaultLibrary()
        let kernel = library?.makeFunction(name: "adjustExposure")
        do {
            self.exposureAdjustPipeline = try device.makeComputePipelineState(function: kernel!)
        } catch {
            return nil
        }
    }

    // MARK: - Public API

    func buildHDR(from images: [UIImage], alignment: Bool, toneMapping: ToneMappingMode) -> UIImage? {
        let ciImages = images.compactMap { CIImage(image: $0) }
        return buildHDR(from: ciImages, alignment: alignment, toneMapping: toneMapping)
    }

    /// Overload allowing real EV biases captured from the camera to be passed in.
    func buildHDR(from images: [UIImage], alignment: Bool, toneMapping: ToneMappingMode, evBiases: [Float]) -> UIImage? {
        self.currentEVBiases = evBiases
        let result = buildHDR(from: images, alignment: alignment, toneMapping: toneMapping)
        self.currentEVBiases = nil
        return result
    }

    func buildHDR(from ciImages: [CIImage], alignment: Bool, toneMapping: ToneMappingMode) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let textures = ciImages.compactMap { makeTexture(from: $0, device: device) }
        return buildHDRFromTextures(textures, alignment: alignment, toneMapping: toneMapping)
    }

    /// Overload allowing real EV biases captured from the camera to be passed in.
    func buildHDR(from ciImages: [CIImage], alignment: Bool, toneMapping: ToneMappingMode, evBiases: [Float]) -> UIImage? {
        self.currentEVBiases = evBiases
        let result = buildHDR(from: ciImages, alignment: alignment, toneMapping: toneMapping)
        self.currentEVBiases = nil
        return result
    }

    // MARK: - Private Helpers

    private func buildHDRFromTextures(_ textures: [MTLTexture], alignment: Bool, toneMapping: ToneMappingMode) -> UIImage? {
        let normalizedTextures = normalizeExposures(textures)
        // Additional HDR building steps here...
        // For the sake of example, just convert the first texture to UIImage
        guard let firstTexture = normalizedTextures.first else { return nil }
        return image(from: firstTexture)
    }

    private func normalizeExposures(_ textures: [MTLTexture]) -> [MTLTexture] {
        // Use provided EV biases if available; otherwise fallback to a sensible default for 5 images
        let defaultBiases: [Float] = [-2, -1, 0, 1, 2]
        let biases: [Float]
        if let provided = currentEVBiases, provided.count == textures.count {
            biases = provided
        } else if defaultBiases.count == textures.count {
            biases = defaultBiases
        } else {
            biases = Array(repeating: 0, count: textures.count)
        }

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

    private func makeTexture(from ciImage: CIImage, device: MTLDevice) -> MTLTexture? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        ciContext.render(ciImage, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return texture
    }

    private func makeTexture(like texture: MTLTexture, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: texture.width, height: texture.height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    private func dispatchThreads(encoder: MTLComputeCommandEncoder, texture: MTLTexture) {
        let w = exposureAdjustPipeline.threadExecutionWidth
        let h = exposureAdjustPipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(texture.width, texture.height, 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    private func image(from texture: MTLTexture) -> UIImage? {
        let ciImage = CIImage(mtlTexture: texture, options: nil)
        let context = CIContext()
        guard let ciImageUnwrapped = ciImage,
              let cgImage = context.createCGImage(ciImageUnwrapped, from: ciImageUnwrapped.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum ToneMappingMode {
    case none
    case linear
    case reinhard
    case filmic
}
