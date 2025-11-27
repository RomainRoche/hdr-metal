//
//  CameraView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI
import AVKit

struct CameraView: UIViewRepresentable {
    
    private let cameraOutput: AVCaptureOutput
    
    init(with cameraOutput: AVCaptureOutput) {
        self.cameraOutput = cameraOutput
    }
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let cameraView = CameraPreviewView()
        cameraView.bound(to: cameraOutput)
        return cameraView
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Update the view if needed
    }
    
    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        // Clean up when the view is removed
        uiView.stopSession()
    }
    
}
