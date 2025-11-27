//
//  CameraView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI

struct CameraView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let cameraView = CameraPreviewView()
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
