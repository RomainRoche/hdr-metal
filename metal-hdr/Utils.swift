//
//  Utils.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import Foundation

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


