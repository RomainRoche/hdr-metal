//
//  Utils.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import Foundation
import UIKit
import CoreImage

func measureTime(_ label: String, _ closure: () -> Void) {
    let start = CFAbsoluteTimeGetCurrent()
    closure()
    let end = CFAbsoluteTimeGetCurrent()
    let elapsed = end - start
    print("\(label): \(String(format: "%.6f", elapsed))s")
}

extension Array {
    func chunked(into size: Int, paddingWith element: Element) -> [[Element]] {
        let remainder = count % size
        let padding = remainder == 0 ? 0 : size - remainder
        let paddedArray = self + Array(repeating: element, count: padding)
        
        return stride(from: 0, to: paddedArray.count, by: size).map {
            Array(paddedArray[$0..<Swift.min($0 + size, paddedArray.count)])
        }
    }
}

extension Array where Element == CIImage {
    
    func uiImages(with orientation: UIImage.Orientation) -> [UIImage] {
        let context = CIContext()
        return self.compactMap {
            guard let cgImage = context.createCGImage($0, from: $0.extent)
            else { return nil }
            return UIImage(cgImage: cgImage, scale: 1, orientation: UIDevice.current.imageOrientation)
        }
    }
    
}

extension UIImage {
    
    func reoriented(_ orientation: UIImage.Orientation? = nil) -> UIImage {
        guard let cgImage = cgImage else { return self }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation ?? UIDevice.current.imageOrientation)
    }
    
}

extension UIDevice {
    
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
