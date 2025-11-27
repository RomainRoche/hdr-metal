//
//  ContentView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI

struct ContentView: View {
    
    @State
    private var capturer: Capturer = BracketCapturer()
    
    var body: some View {
        ZStack {
            CameraView(with: capturer.output)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Button {
                    capturer.capture()
                } label: {
                    Text("Camera View")
                        .font(.title)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
        }
    }
    
}

#Preview {
    ContentView()
}
