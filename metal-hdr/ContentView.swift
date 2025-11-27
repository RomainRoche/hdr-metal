//
//  ContentView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI
import Combine

struct ContentView: View {
    
    @State
    private var capturer: Capturer = MultipleBracketCapturer()
    
    @State
    private var cancels = Set<AnyCancellable>()
    
    @State
    private var images: [UIImage] = []

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
    var capturedImages: some View {
        if images.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
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
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 12)
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
                    images = $0
                }
                .store(in: &cancels)
        }
    }
    
}

#Preview {
    ContentView()
}
