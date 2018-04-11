//
//  StyleTransfer.swift
//  ImStyle
//
//  Created by Ian Johnson on 10/5/17.
//  Copyright © 2017 ImageStyle. All rights reserved.
//

import Foundation
import UIKit
import MobileCoreServices
import QuartzCore
import CoreML
import Photos
import CoreImage
import VideoToolbox

let modelNames = ["No Style", "Mosaic", "Udnie", "Wave", "Water", "Eye"]
let modelList = ["none", "mosaic_style", "udnie_style", "wave_style", "water_style", "eye_style"]
var model = mosaic_style().model

var mosaic_style_: MLModel?
var udnie_style_: MLModel?
var wave_style_: MLModel?
var water_style_: MLModel?
var eye_style_: MLModel?
var models: [MLModel] = []

func setModel(targetModel: String) {
    switch targetModel {
    case "mosaic_style":
        model = mosaic_style_!
    case "udnie_style":
        model = udnie_style_!
    case "wave_style":
        model = wave_style_!
    case "water_style":
        model = water_style_!
    case "eye_style":
        model = eye_style_!
    default:
        break
    }
}

func modelInput(inputImage: CVPixelBuffer) -> MLFeatureProvider {
    switch String(describing: type(of: model)) {
    case "mosaic_style":
        return mosaic_styleInput(inputImage: inputImage)
    case "udnie_style":
        return udnie_styleInput(inputImage: inputImage)
    case "wave_style":
        return wave_styleInput(inputImage: inputImage)
    case "water_style":
        return water_styleInput(inputImage: inputImage)
    case "eye_style":
        return eye_styleInput(inputImage: inputImage)
    // default to mosaic style
    default:
        return mosaic_styleInput(inputImage: inputImage)
    }
}

func loadModels() {
    mosaic_style_ = mosaic_style().model
    udnie_style_  = udnie_style().model
    wave_style_ = wave_style().model
    water_style_ = water_style().model
    eye_style_ = eye_style().model
    models = [mosaic_style_!, udnie_style_!, wave_style_!, water_style_!, eye_style_!]
}

func unloadModels() {
    mosaic_style_ = nil
    udnie_style_ = nil
    wave_style_ = nil
    water_style_ = nil
    eye_style_ = nil
    models = []
}

func applyStyleTransfer(uiImage: UIImage, model: MLModel) -> UIImage {
    let input = modelInput(inputImage: uiImage.buffer()!)
    let outFeatures = try! model.prediction(from: input)
    let output = outFeatures.featureValue(for: "outputImage")!.imageBufferValue!
    return toUIImage(pixelBuffer: output)
}

func toUIImage(pixelBuffer: CVPixelBuffer) -> UIImage {
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(pixelBuffer, nil, &cgImage)
    return UIImage(cgImage: cgImage!)
}

extension UIImage {
    func buffer() -> CVPixelBuffer? {
        return UIImage.buffer(from: self)
    }
    
    // Taken from:
    // https://stackoverflow.com/questions/44462087/how-to-convert-a-uiimage-to-a-cvpixelbuffer
    // https://www.hackingwithswift.com/whats-new-in-ios-11
    static func buffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: image.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    func resizeTo(_ size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContext(size)
        draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

