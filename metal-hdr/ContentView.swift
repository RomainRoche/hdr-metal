//
//  ContentView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI

struct ContentView: View {
    
    @State
    private var capturer: Capturer = MultipleBracketCapturer()

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

    var body: some View {
        ZStack {
            CameraView(with: capturer.output)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Button {
                    capturer.capture()
                } label: {
                    shutterButton
                }
            }
        }
    }
    
}

#Preview {
    ContentView()
}
