//
//  Shaders.metal
//  metal-hdr
//
//  Created by Romain Roche on 27/11/2025.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Utility Functions

float luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float saturation(float3 color) {
    float maxVal = max(max(color.r, color.g), color.b);
    float minVal = min(min(color.r, color.g), color.b);
    return maxVal - minVal;
}

float contrast(texture2d<float, access::read> image, uint2 gid) {
    // Simple Laplacian for contrast
    float center = luminance(image.read(gid).rgb);
    
    float laplacian = 0.0;
    
    if (gid.x > 0 && gid.x < image.get_width() - 1 &&
        gid.y > 0 && gid.y < image.get_height() - 1) {
        
        float top = luminance(image.read(gid + uint2(0, -1)).rgb);
        float bottom = luminance(image.read(gid + uint2(0, 1)).rgb);
        float left = luminance(image.read(gid + uint2(-1, 0)).rgb);
        float right = luminance(image.read(gid + uint2(1, 0)).rgb);
        
        laplacian = abs(-4.0 * center + top + bottom + left + right);
    }
    
    return laplacian;
}

// MARK: - Exposure Adjustment

kernel void adjustExposure(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float &exposureMultiplier [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    float4 pixel = input.read(gid);
    pixel.rgb *= exposureMultiplier;
    output.write(pixel, gid);
}

// MARK: - Weight Computation

kernel void computeExposureWeights(
    texture2d<float, access::read> image [[texture(0)]],
    texture2d<float, access::write> weights [[texture(1)]],
    constant float &sigma [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= image.get_width() || gid.y >= image.get_height()) {
        return;
    }
    
    float4 pixel = image.read(gid);
    
    // Use linear middle gray (~0.18) as exposure center in linear space
    const float exposureCenter = 0.18;
    float exposureWeight = exp(-pow(luminance(pixel.rgb) - exposureCenter, 2.0) / (2.0 * sigma * sigma));
    
    // Clamp contrast and saturation weights to avoid runaway weights on noise
    float contrastWeight = clamp(contrast(image, gid), 0.0, 1.0);
    float saturationWeight = clamp(saturation(pixel.rgb), 0.0, 1.0);
    
    // Combine weights
    float finalWeight = (exposureWeight + 0.2) * (contrastWeight + 0.01) * (saturationWeight + 0.01);
    
    weights.write(float4(finalWeight), gid);
}

// MARK: - Image Merging

kernel void weightedMerge(
    texture2d<float, access::read> image0 [[texture(0)]],
    texture2d<float, access::read> image1 [[texture(1)]],
    texture2d<float, access::read> image2 [[texture(2)]],
    texture2d<float, access::read> image3 [[texture(3)]],
    texture2d<float, access::read> image4 [[texture(4)]],
    texture2d<float, access::read> weight0 [[texture(5)]],
    texture2d<float, access::read> weight1 [[texture(6)]],
    texture2d<float, access::read> weight2 [[texture(7)]],
    texture2d<float, access::read> weight3 [[texture(8)]],
    texture2d<float, access::read> weight4 [[texture(9)]],
    texture2d<float, access::write> output [[texture(10)]],
    constant int &numImages [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 sumWeighted = float4(0.0);
    float sumWeights = 0.0;

    // Manually handle each image (Metal doesn't support dynamic array indexing in textures)
    if (numImages >= 1) {
        float w = weight0.read(gid).r;
        sumWeighted += image0.read(gid) * w;
        sumWeights += w;
    }

    if (numImages >= 2) {
        float w = weight1.read(gid).r;
        sumWeighted += image1.read(gid) * w;
        sumWeights += w;
    }

    if (numImages >= 3) {
        float w = weight2.read(gid).r;
        sumWeighted += image2.read(gid) * w;
        sumWeights += w;
    }

    if (numImages >= 4) {
        float w = weight3.read(gid).r;
        sumWeighted += image3.read(gid) * w;
        sumWeights += w;
    }

    if (numImages >= 5) {
        float w = weight4.read(gid).r;
        sumWeighted += image4.read(gid) * w;
        sumWeights += w;
    }

    float4 result = sumWeights > 0.0001 ? sumWeighted / sumWeights : float4(0.0);
    output.write(result, gid);
}

// MARK: - Tone Mapping

kernel void reinhardToneMap(
    texture2d<float, access::read> hdrImage [[texture(0)]],
    texture2d<float, access::write> ldrImage [[texture(1)]],
    constant float &exposure [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= hdrImage.get_width() || gid.y >= hdrImage.get_height()) {
        return;
    }
    
    float4 hdr = hdrImage.read(gid);
    
    // Apply exposure
    float3 color = hdr.rgb * exposure;
    
    // Reinhard operator
    float3 mapped = color / (1.0 + color);
    
    // Gamma correction
    mapped = pow(mapped, float3(1.0 / 2.2));
    
    ldrImage.write(float4(mapped, hdr.a), gid);
}

kernel void acesToneMap(
    texture2d<float, access::read> hdrImage [[texture(0)]],
    texture2d<float, access::write> ldrImage [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= hdrImage.get_width() || gid.y >= hdrImage.get_height()) {
        return;
    }
    
    float4 hdr = hdrImage.read(gid);
    float3 color = hdr.rgb;
    
    // ACES filmic tone mapping curve
    // https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
    float3 a = color * (color + 0.0245786) - 0.000090537;
    float3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    float3 mapped = clamp(a / b, 0.0, 1.0);
    
    // Gamma correction
    mapped = pow(mapped, float3(1.0 / 2.2));
    
    ldrImage.write(float4(mapped, hdr.a), gid);
}
