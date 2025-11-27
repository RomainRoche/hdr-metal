//
//  Capturer.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import AVKit
import Foundation
import Combine

public protocol Capturer {
    var onCapture: PassthroughSubject<[UIImage], Never> { get }
    var output: AVCaptureOutput { get }
    @MainActor func capture()
}

public final class BracketCapturer: NSObject, Capturer, AVCapturePhotoCaptureDelegate {
    
    public var onCapture: PassthroughSubject<[UIImage], Never> = .init()
    
    private let stillImageOutput = AVCapturePhotoOutput()
    public var output: AVCaptureOutput { stillImageOutput }
    
    private let exposures: [AVCaptureAutoExposureBracketedStillImageSettings] = [
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: -2.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 0.0),
        AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: 1.0),
    ]
    
    @MainActor
    private var photos: [UIImage] = []
    
    @MainActor
    public func capture() {
        stillImageOutput.maxPhotoQualityPrioritization = .quality
        
        let photoSettings = AVCapturePhotoBracketSettings(
            rawPixelFormatType: 0,
            processedFormat: [AVVideoCodecKey : AVVideoCodecType.jpeg],
            bracketedSettings: exposures
        )
        
        photoSettings.isLensStabilizationEnabled = true
        photoSettings.flashMode = .off
        
        capture(with: photoSettings)
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
        guard let image = photo.uiImage else { return }
        photos.append(image)
        
        if photos.count == exposures.count {
            onCapture.send(photos)
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
    
}

fileprivate extension UIDevice {
    
    var imageOrientation: UIImage.Orientation {
        switch orientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .faceUp, .faceDown, .unknown:
            // Default to portrait orientation
            return .right
        @unknown default:
            return .right
        }
    }
    
}
