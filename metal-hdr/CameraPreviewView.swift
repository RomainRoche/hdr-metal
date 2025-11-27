//
//  CameraPreviewView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import UIKit
import AVFoundation

class CameraPreviewView: UIView {
    
    // MARK: - Properties
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        let captureSession = AVCaptureSession()
        self.captureSession = captureSession
        
        captureSession.sessionPreset = .high
        
        // Get the default camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Unable to access camera")
            return
        }
        
        do {
            // Create input from camera device
            let input = try AVCaptureDeviceInput(device: camera)
            
            // Add input to session
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // Create preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds
            
            layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            
            // Start the session on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
            
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    
    func startSession() {
        guard let captureSession = captureSession, !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
    
    func stopSession() {
        guard let captureSession = captureSession, captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.stopRunning()
        }
    }
    
    func bound(to output: AVCaptureOutput) {
        guard let captureSession else { return }
        if captureSession.canAddOutput(output) {
            output.connection(with: .video)?.videoRotationAngle = 90
            captureSession.addOutput(output)
        }
    }
    
}
