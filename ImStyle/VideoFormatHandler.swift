//
//  VideoFormatHandler.swift
//  ImStyle
//
//  Created by Jake Carlson on 10/24/17.
//  Copyright © 2017 ImageStyle. All rights reserved.
//

// [UIImage] to video resource: https://stackoverflow.com/questions/3741323/how-do-i-export-uiimage-array-as-a-movie/3742212#36297656

import Foundation
import UIKit
import AVFoundation
import Photos

class VideoFormatHandler {
    
    let sampleRate: Double!
    let mainVC: MainViewController!
    var numFramesLoaded: Int
    var numFramesRequested: Int
    var imageSize: Int
    var callback: Selector
    
    let videoWriter: VideoWriter!
    var settings: RenderSettings
    var frames: [UIImage]
    var frameNum: Int
    
    init(mainVC: MainViewController, imageSize: Int, callback: Selector) {
        self.sampleRate = 0.05
        self.mainVC = mainVC
        self.numFramesLoaded = 0
        self.numFramesRequested = 0
        self.imageSize = imageSize
        self.callback = callback
        
        self.settings = RenderSettings()
        self.settings.width = CGFloat(self.imageSize)
        self.settings.height = CGFloat(self.imageSize)
        self.settings.fps = Int32(1/self.sampleRate)
        
        self.videoWriter = VideoWriter(renderSettings: self.settings)
        self.frames = []
        self.frameNum = 0
    }
    
    func videoToArray(videoResource: NSURL) {
        self.numFramesLoaded = 0
        let asset = AVURLAsset(url: videoResource as URL)
        let generator = AVAssetImageGenerator.init(asset: asset)
        generator.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 15)
        generator.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 15)
        
        let times = Array(stride(from: 0.0, to: min(10.0, Double(CMTimeGetSeconds(asset.duration))), by: self.sampleRate))
        self.numFramesRequested = times.count
        generator.generateCGImagesAsynchronously(forTimes: times as [NSValue], completionHandler: self.frameGenCompletion(reqT:img:actualT:result:err:))
    }
    
    func frameGenCompletion(reqT: CMTime, img: CGImage?, actualT: CMTime, result: AVAssetImageGenerator.Result, err: Error?) -> Void {
        if (img == nil) {
            print("Could not get image: ", err!)
            self.numFramesRequested -= 1
        } else {
            // update the main view controller with the new frame
            var frame = UIImage(cgImage: img!, scale: 1, orientation: UIImage.Orientation.right)
            frame = frame.scaled(to: CGSize(width: self.imageSize, height: self.imageSize), scalingMode: .aspectFill)
            self.mainVC.videoFrames[0].append(frame)
            self.numFramesLoaded += 1
        }
        if (self.numFramesLoaded == self.numFramesRequested) {
            DispatchQueue.main.async {
                self.mainVC.videoTimer?.invalidate()
                self.mainVC.videoTimer = Timer.scheduledTimer(timeInterval: self.sampleRate, target: self.mainVC, selector: self.callback, userInfo: nil, repeats: true)
                self.mainVC.displayingVideo = true
                self.mainVC.updateStyle(oldStyle: 0)
            }
        }
    }
    
    func makeVideo(frames: [UIImage]) {
        self.removeTempVideoFile(videoUrl: self.settings.outputURL)
        self.frames = frames
        self.frameNum = 0
        self.videoWriter.start()
        self.videoWriter.render(appendPixelBuffers: appendPixelBuffers) {
            self.saveVideoToPhotoLibrary(videoUrl: self.settings.outputURL)
            self.frames = []
        }
    }
    
    func prepareAndShareVideo(frames: [UIImage]) {
        self.removeTempVideoFile(videoUrl: self.settings.outputURL)
        self.frames = frames
        self.frameNum = 0
        self.videoWriter.start()
        self.videoWriter.render(appendPixelBuffers: appendPixelBuffers) {
            self.mainVC.shareVideo(videoUrl: self.settings.outputURL)
            self.frames = []
        }
    }
    
    func appendPixelBuffers(writer: VideoWriter) -> Bool {
        // kTimescale 600
        let frameDuration = CMTimeMake(value: Int64(600 / settings.fps), timescale: 600)
        
        while !self.frames.isEmpty {
            
            if writer.isReadyForData == false {
                // Inform writer we have more buffers to write.
                return false
            }
            
            let image = self.frames.removeFirst()
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(self.frameNum))
            let success = videoWriter.addImage(image: image, withPresentationTime: presentationTime)
            if success == false {
                fatalError("addImage() failed")
            }
            
            self.frameNum += 1
        }
        
        // Inform writer all buffers have been written.
        return true
    }
    
    func saveVideoToPhotoLibrary(videoUrl: NSURL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl as URL)
        }) { (success, err) in
            if !success {
                print("Could not save video: ", err!)
            } else {
                self.mainVC.videoCallbackOnSuccess()
                self.removeTempVideoFile(videoUrl: videoUrl)
            }
        }
    }
    
    func removeTempVideoFile(videoUrl: NSURL) {
        do {
            try FileManager.default.removeItem(atPath: videoUrl.path!)
        }
        catch _ as NSError {
            print("Could not remove file")
        }
    }

}

// https://stackoverflow.com/questions/3741323/how-do-i-export-uiimage-array-as-a-movie/3742212#36297656
class VideoWriter {
    
    let renderSettings: RenderSettings
    
    var videoWriter: AVAssetWriter!
    var videoWriterInput: AVAssetWriterInput!
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    
    var isReadyForData: Bool {
        return videoWriterInput?.isReadyForMoreMediaData ?? false
    }
    
    func pixelBufferFromImage(image: UIImage, pixelBufferPool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer {
        
        var pixelBufferOut: CVPixelBuffer?
        
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        if status != kCVReturnSuccess {
            fatalError("CVPixelBufferPoolCreatePixelBuffer() failed")
        }
        
        let pixelBuffer = pixelBufferOut!
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        context!.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        let horizontalRatio = size.width / image.size.width
        let verticalRatio = size.height / image.size.height
        //aspectRatio = max(horizontalRatio, verticalRatio) // ScaleAspectFill
        let aspectRatio = min(horizontalRatio, verticalRatio) // ScaleAspectFit
        
        let newSize = CGSize(width: image.size.width * aspectRatio, height: image.size.height * aspectRatio)
        
        let x = newSize.width < size.width ? (size.width - newSize.width) / 2 : 0
        let y = newSize.height < size.height ? (size.height - newSize.height) / 2 : 0
        
        //        CGContextDrawImage(context, CGRect(x: x, y: y, width: newSize.width, height: newSize.height), image.cgImage)
        context?.draw(image.cgImage!, in: CGRect(x: x, y: y, width: newSize.width, height: newSize.height), byTiling: false)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    init(renderSettings: RenderSettings) {
        self.renderSettings = renderSettings
    }
    
    func start() {
        
        let avOutputSettings: [String: AnyObject] = [
            AVVideoCodecKey: renderSettings.avCodecKey as AnyObject,
            AVVideoWidthKey: NSNumber(value: Float(renderSettings.width)),
            AVVideoHeightKey: NSNumber(value: Float(renderSettings.height))
        ]
        
        func createPixelBufferAdaptor() {
            let sourcePixelBufferAttributesDictionary = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: NSNumber(value: Float(renderSettings.width)),
                kCVPixelBufferHeightKey as String: NSNumber(value: Float(renderSettings.height))
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput,
                                                                      sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
        }
        
        func createAssetWriter(outputURL: NSURL) -> AVAssetWriter {
            guard let assetWriter = try? AVAssetWriter(outputURL: outputURL as URL, fileType: AVFileType.mp4) else {
                fatalError("AVAssetWriter() failed")
            }
            
            guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
                fatalError("canApplyOutputSettings() failed")
            }
            
            return assetWriter
        }
        
        videoWriter = createAssetWriter(outputURL: renderSettings.outputURL)
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)
        
        if videoWriter.canAdd(videoWriterInput) {
            videoWriter.add(videoWriterInput)
        }
        else {
            fatalError("canAddInput() returned false")
        }
        
        // The pixel buffer adaptor must be created before we start writing.
        createPixelBufferAdaptor()
        
        if videoWriter.startWriting() == false {
            fatalError("startWriting() failed")
        }
        
        videoWriter.startSession(atSourceTime: CMTime.zero)
        
        precondition(pixelBufferAdaptor.pixelBufferPool != nil, "nil pixelBufferPool")
    }
    
    func render(appendPixelBuffers: @escaping (VideoWriter)->Bool, completion: @escaping ()->Void) {
        
        precondition(videoWriter != nil, "Call start() to initialze the writer")
        
        let queue = DispatchQueue(label: "mediaInputQueue")
        videoWriterInput.requestMediaDataWhenReady(on: queue) {
            let isFinished = appendPixelBuffers(self)
            if isFinished {
                self.videoWriterInput.markAsFinished()
                self.videoWriter.finishWriting() {
                    DispatchQueue.main.async() {
                        completion()
                    }
                }
            }
            else {
                // Fall through. The closure will be called again when the writer is ready.
            }
        }
    }
    
    func addImage(image: UIImage, withPresentationTime presentationTime: CMTime) -> Bool {
        
        precondition(pixelBufferAdaptor != nil, "Call start() to initialze the writer")
        
        let pixelBuffer = self.pixelBufferFromImage(image: image, pixelBufferPool: pixelBufferAdaptor.pixelBufferPool!, size: renderSettings.size)
        return pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }
    
}

struct RenderSettings {
    
    var width: CGFloat = 720
    var height: CGFloat = 720
    var fps: Int32 = 2   // 2 frames per second
    var avCodecKey = AVVideoCodecType.h264
    var videoFilename = "rendered"
    var videoFilenameExt = "mp4"
    
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
    
    var outputURL: NSURL {
        // Use the CachesDirectory so the rendered video file sticks around as long as we need it to.
        // Using the CachesDirectory ensures the file won't be included in a backup of the app.
        let fileManager = FileManager.default
        if let tmpDirURL = try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return tmpDirURL.appendingPathComponent(videoFilename).appendingPathExtension(videoFilenameExt) as NSURL
        }
        fatalError("URLForDirectory() failed")
    }
}
