//
//  ContentView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    
    @State
    private var capturer: Capturer = MultipleBracketCapturer()
    
    @State
    private var hdrBuilder = HDRBuilder()
    
    @State
    private var cancels = Set<AnyCancellable>()
    
    @State
    private var images: [UIImage] = []

    @State
    private var ciImages: [CIImage] = []

    @State
    private var hdrResultOrientation: UIImage.Orientation = .up
    
    @State
    private var hdrImage: UIImage?
    
    @State
    private var showHDR: Bool = false

    @ViewBuilder
    var shutterButton: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 70, height: 70)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 85, height: 85)

            Circle()
                .fill(.white)
                .frame(width: 60, height: 60)
        }
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    var toHDR: some View {
        Button {
            guard let hdrBuilder else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                // Use CIImages directly to avoid colorspace conversion issues
                let result = hdrBuilder.buildHDR(
                    from: ciImages,
                    alignment: true,
                    toneMapping: .reinhard(exposure: 0.4)
                )

                DispatchQueue.main.async {
                    if let hdrImage = result {
                        self.hdrImage = hdrImage.reoriented(hdrResultOrientation)
                        showHDR = true
                    }
                }
            }
        } label: {
            Text("HDR")
                .foregroundStyle(Color.white)
                .padding()
                .frame(width: 140, height: 140)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

        }
    }
    
    @ViewBuilder
    var capturedImages: some View {
        if images.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
                    toHDR
                    
                    ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: 140 / (image.size.height / image.size.width),
                                height: 140
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.6), lineWidth: 1))
                            .onLongPressGesture {
                                UIPasteboard.general.image = image
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    var body: some View {
        ZStack {
            CameraView(with: capturer.output)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Button {
                    images = []
                    ciImages = []
                    capturer.capture()
                } label: {
                    shutterButton
                }
            }
            
            VStack {
                capturedImages
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .onAppear {
            capturer.onCapture
                .receive(on: DispatchQueue.main)
                .sink {
                    ciImages = $0.images
                    images = $0.images.uiImages(with: $0.orientation)
                    hdrResultOrientation = $0.orientation
                }
                .store(in: &cancels)
        }
        .sheet(isPresented: $showHDR) {
            if let hdrImage {
                Image(uiImage: hdrImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onLongPressGesture {
                        UIPasteboard.general.image = hdrImage
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            } else {
                EmptyView()
            }
        }
    }
    
}

#Preview {
    ContentView()
}
