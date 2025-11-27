//
//  Capturer.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import AVKit
import Foundation
import Combine
import CoreImage

public typealias CaptureOutput = (images: [CIImage], orientation: UIImage.Orientation)

public protocol Capturer {
    var onCapture: PassthroughSubject<CaptureOutput, Never> { get }
    var output: AVCaptureOutput { get }
    @MainActor func capture()
}

public final class BracketCapturer: NSObject, Capturer, AVCapturePhotoCaptureDelegate {
    
    public var onCapture: PassthroughSubject<CaptureOutput, Never> = .init()
    
    private let stillImageOutput = AVCapturePhotoOutput()
    public var output: AVCaptureOutput { stillImageOutput }
    
    private let exposures: [AVCaptureAutoExposureBracketedStillImageSettings] = [
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -2.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 0.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 1.0),
    ]
    
    @MainActor
    private var photos: [CIImage] = []
    
    @MainActor
    private var captureTime: TimeInterval = 0
    
    @MainActor
    public func capture() {
        captureTime = Date().timeIntervalSinceReferenceDate
        stillImageOutput.maxPhotoQualityPrioritization = .quality
        
        let photoSettings = AVCapturePhotoBracketSettings(
            rawPixelFormatType: 0,
            processedFormat: [AVVideoCodecKey : AVVideoCodecType.jpeg],
            bracketedSettings: exposures
        )
        
        photoSettings.isLensStabilizationEnabled = true
        photoSettings.flashMode = .off
        
        measureTime("Bracket capture") {
            capture(with: photoSettings)
        }
    }
    
    @MainActor
    private func capture(with photoSettings: AVCapturePhotoSettings) {
        stillImageOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard let image = photo.ciImage else { return }
        photos.append(image)
        
        if photos.count == exposures.count {
            onCapture.send((photos, UIDevice.current.imageOrientation))
            print("Bracket capture: took \(String(format: "%.6f", Date().timeIntervalSinceReferenceDate - captureTime))s")
            photos = []
        }
    }
    
}

public final class MultipleBracketCapturer: NSObject, Capturer, AVCapturePhotoCaptureDelegate {
    public var onCapture: PassthroughSubject<CaptureOutput, Never> = .init()
    
    private let stillImageOutput = AVCapturePhotoOutput()
    public var output: AVCaptureOutput { stillImageOutput }
    
    private let exposures: [AVCaptureAutoExposureBracketedStillImageSettings] = [
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -4.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -3.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -2.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -1.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 0.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 1.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 2.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 3.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 4.0),
    ]
    
    @MainActor
    private var photos: [CIImage] = []
    
    @MainActor
    private var captureTime: TimeInterval = 0
    
    @MainActor
    public func capture() {
        captureTime = Date().timeIntervalSinceReferenceDate
        stillImageOutput.maxPhotoQualityPrioritization = .quality
        
        let defaultExp = AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 0.0)
        let exposuresChunks = exposures.chunked(into: 3, paddingWith: defaultExp)
        
        measureTime("Multiple bracket capture") {
            for exposures in exposuresChunks {
                let photoSettings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: [AVVideoCodecKey : AVVideoCodecType.jpeg],
                    bracketedSettings: exposures
                )
                
                photoSettings.isLensStabilizationEnabled = true
                photoSettings.flashMode = .off
                
                capture(with: photoSettings)
            }
        }
    }
    
    @MainActor
    private func capture(with photoSettings: AVCapturePhotoSettings) {
        stillImageOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard let image = photo.ciImage else { return }
        photos.append(image)
        
        if photos.count == exposures.count {
            onCapture.send((photos, UIDevice.current.imageOrientation))
            print("Multiple bracket capture: took \(String(format: "%.6f", Date().timeIntervalSinceReferenceDate - captureTime))s")
            photos = []
        }
    }
    
}

fileprivate extension AVCapturePhoto {
    
    var uiImage: UIImage? {
#if os(iOS)
        guard let imageData = fileDataRepresentation(),
              let imageSource = CGImageSourceCreateWithData((imageData as CFData), nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: UIDevice.current.imageOrientation)
#else
        return nil
#endif
    }
    
    var ciImage: CIImage? {
        guard let imageData = fileDataRepresentation() else { return nil }
        return CIImage(data: imageData)
    }
    
}
