//
//  ContentView.swift
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            CameraView()
                .ignoresSafeArea()
            
            VStack {
                Spacer()
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

#Preview {
    ContentView()
}
