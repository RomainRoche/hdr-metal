# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

metal-hdr is an iOS SwiftUI application that captures multiple bracketed exposures and merges them into HDR (High Dynamic Range) images using Metal compute shaders. The app uses AVFoundation for camera capture and Metal for GPU-accelerated image processing.

## Build and Run

This is an Xcode project. To build and run:

```bash
# Open the project
open metal-hdr.xcodeproj

# Build from command line (requires xcodebuild)
xcodebuild -project metal-hdr.xcodeproj -scheme metal-hdr -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run on device requires signing configuration in Xcode
```

## Architecture

### HDR Processing Pipeline

The HDR creation follows this flow:

1. **Capture** (Capturer.swift): Captures bracketed exposures using AVCapturePhotoBracketSettings
   - `BracketCapturer`: 3 exposures (-2.0, 0.0, +1.0 EV)
   - `MultipleBracketCapturer`: 9 exposures (-4.0 to +4.0 EV) captured in chunks of 3
   - Output: Array of `CIImage` objects published via Combine

2. **Alignment** (ImageAlignment.swift): Aligns images to compensate for camera shake
   - Converts to grayscale for alignment computation
   - Uses phase correlation (currently placeholder implementation)
   - Applies translation transform to align images

3. **HDR Merging** (HDRBuilder.swift + Shaders.metal): Metal-based GPU processing
   - **Exposure Normalization**: Adjusts each image's exposure based on its EV offset
   - **Weight Computation**: Calculates per-pixel weights based on:
     - Exposure quality (Gaussian curve favoring mid-tones)
     - Contrast (Laplacian edge detection)
     - Saturation
   - **Weighted Merge**: Combines normalized images using computed weights
   - **Tone Mapping**: Converts HDR to displayable LDR
     - Reinhard operator with adjustable exposure
     - ACES filmic curve

4. **Display** (ContentView.swift): Shows captured images and final HDR result

### Metal Shaders

All GPU compute kernels are in Shaders.metal:

- `adjustExposure`: Multiplies image by exposure factor
- `computeExposureWeights`: Calculates quality weights per pixel
- `weightedMerge`: Hardcoded to handle up to 5 images (Metal limitation on dynamic texture arrays)
- `reinhardToneMap`: Reinhard tone mapping with gamma correction
- `acesToneMap`: ACES filmic tone mapping

**Important**: The `weightedMerge` kernel is hardcoded for 5 images maximum due to Metal's lack of dynamic texture array indexing. To support more images, the shader must be modified to handle additional texture slots.

### Camera Integration

- `CameraPreviewView`: UIKit view managing AVCaptureSession
- `CameraView`: SwiftUI wrapper using UIViewRepresentable
- Camera output is bound to Capturer's AVCapturePhotoOutput

### Data Flow

```
CameraPreviewView → Capturer.output → AVCapturePhotoBracketSettings
    ↓
Capturer.onCapture (Combine Publisher)
    ↓
ContentView.images (State)
    ↓
HDRBuilder.buildHDR()
    ↓
ContentView.hdrImage (displayed in sheet)
```

## Key Implementation Details

### Working Color Space

HDRBuilder uses extended linear sRGB color space for processing:
```swift
.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
```

This preserves HDR values greater than 1.0 during computation.

### Texture Loading

Images are loaded with `.SRGB: false` to work in linear space. Gamma correction is applied during tone mapping.

### Thread Group Sizing

Metal compute operations use 16×16 thread groups for optimal GPU utilization.

### Orientation Handling

Device orientation is mapped to UIImage.Orientation in Utils.swift (UIDevice.imageOrientation extension). Portrait mode maps to `.right` orientation.

## Common Modifications

### Adding More Bracketed Exposures

1. Modify the exposures array in MultipleBracketCapturer
2. Update `weightedMerge` kernel in Shaders.metal to handle more texture slots
3. Adjust chunking logic if exceeding 3 captures per bracket

### Changing Tone Mapping

Pass different ToneMappingMode to HDRBuilder.buildHDR():
```swift
.reinhard(exposure: Float)  // Adjustable exposure
.aces                        // Filmic curve
```

### Disabling Image Alignment

Set `alignment: false` when calling buildHDR():
```swift
hdrBuilder.buildHDR(from: images, alignment: false, toneMapping: .reinhard(exposure: 1.2))
```
