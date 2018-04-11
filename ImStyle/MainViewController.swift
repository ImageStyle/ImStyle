// Real-time style transfer

import UIKit
import AVFoundation
import VideoToolbox

class MainViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var loadImageButton: UIButton!
    @IBOutlet weak var saveImageButton: UIButton!
    @IBOutlet weak var clearImageButton: UIButton!
    @IBOutlet weak var takePhotoButton: UIButton!
    @IBOutlet weak var stylePreviewImageView: UIImageView!
    @IBOutlet weak var stylePreviewImageBorder: UIView!
    @IBOutlet weak var toggleCameraButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    
    let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front)!
    let rearCamera = AVCaptureDevice.default(for: .video)!
    let frontCameraSession = AVCaptureSession()
    let rearCameraSession = AVCaptureSession()
    let num_styles = modelList.count
    var stylePreviewAnimation: UIViewPropertyAnimator?
    var latestRawInputFrame: UIImage?
    var perform_transfer = false
    var hitMaxVideoLength = false
    var currentStyle = 0
    var isStylizingVideo = false
    var recordingVideo = false
    var displayingVideo = false
    var videoStyleWasInterrupted = false
    var videoFrames: [[UIImage]] = []
    var numFramesRendered: [Int] = []
    var videoPlaybackFrame = 0
    var progressView: UIView!
    
    var videoTimer : Timer? = nil
    private var stylePreviewTimer : Timer? = nil
    private var videoFormatHandler: VideoFormatHandler!
    private var isRearCamera = true
    private var frontCaptureDevice: AVCaptureDevice?
    private var rearCaptureDevice: AVCaptureDevice?
    private let image_size = 720
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(cleanMemory), name: Notification.Name("didEnterBackground"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Notification.Name("willEnterForeground"), object: nil)
        
        loadModels()
        
        self.progressView = UIView()
        self.stylePreviewImageView.addSubview(progressView)
        self.progressView.backgroundColor = UIColor.darkGray
        self.progressView.alpha = 0.75
        
        self.videoFormatHandler = VideoFormatHandler(mainVC: self, imageSize: self.image_size, callback: #selector(self.renderVideoFrame))
        
        self.stylePreviewImageView.isHidden = true
        self.stylePreviewImageBorder.isHidden = true
        self.stylePreviewImageBorder.layer.cornerRadius = 4
        
        self.clearImageButton.isEnabled = false
        
        self.rearCaptureDevice = rearCamera
        self.frontCaptureDevice = frontCamera
        
        for _ in 0..<modelList.count {
            self.videoFrames.append([])
            self.numFramesRendered.append(0)
        }
        
        do {
            let frontInput = try AVCaptureDeviceInput(device: frontCaptureDevice!)
            let rearInput = try AVCaptureDeviceInput(device: rearCaptureDevice!)

            frontCameraSession.beginConfiguration()
            rearCameraSession.beginConfiguration()

            if (frontCameraSession.canAddInput(frontInput)) {
                frontCameraSession.addInput(frontInput)
            }
            
            if (rearCameraSession.canAddInput(rearInput)) {
                rearCameraSession.addInput(rearInput)
            }

            let rearDataOutput = AVCaptureVideoDataOutput()
            rearDataOutput.videoSettings = [((kCVPixelBufferPixelFormatTypeKey as NSString) as String) : NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32)]
            rearDataOutput.alwaysDiscardsLateVideoFrames = true

            if (rearCameraSession.canAddOutput(rearDataOutput)) {
                rearCameraSession.addOutput(rearDataOutput)
            }
            
            let frontDataOutput = AVCaptureVideoDataOutput()
            frontDataOutput.videoSettings = [((kCVPixelBufferPixelFormatTypeKey as NSString) as String) : NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32)]
            frontDataOutput.alwaysDiscardsLateVideoFrames = true
            
            if (frontCameraSession.canAddOutput(frontDataOutput)) {
                frontCameraSession.addOutput(frontDataOutput)
            }

            let frontQueue = DispatchQueue(label: "com.styletransfer.front-video-output")
            let rearQueue = DispatchQueue(label: "com.styletransfer.rear-video-output")
            frontDataOutput.setSampleBufferDelegate(self, queue: frontQueue)
            rearDataOutput.setSampleBufferDelegate(self, queue: rearQueue)
            
            frontCameraSession.commitConfiguration()
            rearCameraSession.commitConfiguration()
            
            rearCameraSession.startRunning()
            rearCameraSession.stopRunning()
            frontCameraSession.startRunning()
            frontCameraSession.stopRunning()
            rearCameraSession.startRunning()
        }
        catch let error as NSError {
            NSLog("\(error), \(error.localizedDescription)")
        }
        
        self.clearImageButton.isHidden = true
        self.clearImageButton.isEnabled = false
        self.saveImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
        self.shareButton.isEnabled = false
        self.shareButton.isHidden = true
        self.progressView.isHidden = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        var frame = view.frame
        frame.size.height = frame.size.height - 35.0
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if(isRearCamera) {
            rearCameraSession.stopRunning()
        } else {
            frontCameraSession.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        connection.videoOrientation = .portrait
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let img = UIImage(ciImage: ciImage).resizeTo(CGSize(width: self.image_size, height: self.image_size))
            if let uiImage = img {
                var outImage : UIImage
                if(!isRearCamera){
                    outImage = UIImage(cgImage: uiImage.cgImage!, scale: 1.0, orientation: .upMirrored)
                } else {
                    outImage = uiImage
                }
                self.latestRawInputFrame = outImage
                if (perform_transfer) {
                    outImage = applyStyleTransfer(uiImage: outImage, model: model)
                    self.videoFrames[self.currentStyle] = [outImage]
                }
                DispatchQueue.main.async {
                    self.updateOutputImage(uiImage: outImage);
                }
            }
        }
    }
    
    func updateOutputImage(uiImage: UIImage) {
        if(self.takePhotoButton.isEnabled) {
            self.imageView.image = uiImage;
        }
    }
    
    private func changeCamera() {
        if(!isRearCamera) {
            rearCameraSession.startRunning()
            frontCameraSession.stopRunning()
        } else {
            rearCameraSession.stopRunning()
            frontCameraSession.startRunning()
        }
    }

    @IBAction func save_image(_ sender: Any) {
        if (self.displayingVideo) {
            self.videoFormatHandler.makeVideo(frames: self.videoFrames[self.currentStyle])
        } else {
            UIGraphicsBeginImageContext(CGSize(width: self.imageView.frame.size.width, height: self.imageView.frame.size.height))
            self.imageView.drawHierarchy(in: CGRect(x: 0.0, y: 0.0, width: self.imageView.frame.size.width, height: self.imageView.frame.size.height), afterScreenUpdates: true)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            self.saveToPhotoLibrary(uiImage: image!)
        }
    }
    
    @IBAction func shareAction(_ sender: Any) {
        if (self.displayingVideo) {
            self.videoFormatHandler.prepareAndShareVideo(frames: self.videoFrames[self.currentStyle])
        } else {
            let toShare = [self.imageView.image!]
            self.presetShareView(toShare: toShare)
        }
    }
    
    func shareVideo(videoUrl: NSURL) {
        let toShare = [videoUrl]
        self.presetShareView(toShare: toShare)
    }
    
    func presetShareView(toShare: [Any]) {
        // sharing: https://stackoverflow.com/questions/35931946/basic-example-for-sharing-text-or-image-with-uiactivityviewcontroller-in-swift
        let activityViewController = UIActivityViewController(activityItems: toShare, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash
        
        // exclude some activity types from the list (optional)
        // activityViewController.excludedActivityTypes = [ UIActivityType.airDrop, UIActivityType.postToFacebook ]
        
        // present the view controller
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    @objc func startVideo() {
        if(self.currentStyle != 0) {
            print("TODO: alert user that you can't record live video in style")
            return
        }
        for index in 0..<modelList.count {
            self.videoFrames[index] = []
            self.numFramesRendered[index] = 0
        }
        self.videoTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(saveFrame), userInfo: nil, repeats: true)
        self.loadImageButton.isHidden = true
        self.loadImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
        self.saveImageButton.isEnabled = false
        self.shareButton.isHidden = true
        self.shareButton.isEnabled = false
        self.recordingVideo = true
        self.videoPlaybackFrame = 0
    }
    
    @objc func saveFrame(){
        self.videoFrames[0].append(self.imageView.image!)
        if(self.videoFrames[0].count >= 200) {
            self.takePhotoTouchUpInside(true)
            self.hitMaxVideoLength = true
        }
    }
    
    @objc func renderVideoFrame() {
        if(self.currentStyle == 0 || self.videoFrames[0].count > self.videoFrames[self.currentStyle].count) {
            self.imageView.image = self.videoFrames[0][self.videoPlaybackFrame]
        } else {
            self.imageView.image = self.videoFrames[self.currentStyle][self.videoPlaybackFrame]
        }
        self.videoPlaybackFrame += 1;
        if(self.videoPlaybackFrame == self.videoFrames[0].count) {
            self.videoPlaybackFrame = 0;
        }
    }
    
    @IBAction func takePhotoTouchDown(_ sender: Any) {
        self.videoTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(startVideo), userInfo: nil, repeats: false)
    }
    
    func stylizeSingleFrame() {
        DispatchQueue.global().async {
            while(self.videoFrames[0].count == 0) {} // busy wait until new frame is ready
            for (index, model) in models.enumerated() {
                if (self.videoFrames[0].count == 0) {break}
                let image = self.videoFrames[0][0].scaled(to: CGSize(width: self.image_size, height: self.image_size), scalingMode: .aspectFill)
                self.videoFrames[index+1] = [applyStyleTransfer(uiImage: image, model: model)]
            }
        }
    }
    
    @IBAction func takePhotoTouchUpInside(_ sender: Any) {
        if(self.hitMaxVideoLength) {
            self.hitMaxVideoLength = false
            return
        }
        if(isRearCamera) {
            rearCameraSession.stopRunning()
        } else {
            frontCameraSession.stopRunning()
        }
        if(self.recordingVideo) {
            self.recordingVideo = false
            self.displayingVideo = true
            self.videoTimer!.invalidate()
            self.videoTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(renderVideoFrame), userInfo: nil, repeats: true)
        } else {
            self.videoFrames[0] = [self.latestRawInputFrame!]
            if(self.currentStyle == 0) {
                self.updateOutputImage(uiImage: self.latestRawInputFrame!);
            }
            for index in 1..<self.videoFrames.count {
                self.videoFrames[index] = []
            }
            self.videoTimer!.invalidate()
            self.stylizeSingleFrame()
        }
        self.toggleCameraButton.isEnabled = false
        self.toggleCameraButton.isHidden = true
        self.takePhotoButton.isEnabled = false
        self.takePhotoButton.isHidden = true
        self.saveImageButton.isEnabled = true
        self.saveImageButton.isHidden = false
        self.shareButton.isEnabled = true
        self.shareButton.isHidden = false
        self.clearImageButton.isEnabled = true
        self.clearImageButton.isHidden = false
        self.loadImageButton.isEnabled = false
        self.loadImageButton.isHidden = true
    }
    
    @IBAction func clearImageAction(_ sender: Any) {
        for index in 0..<self.videoFrames.count {
            self.videoFrames[index] = []
            self.numFramesRendered[index] = 0
        }
        if(self.displayingVideo) {
            self.displayingVideo = false
            self.videoTimer!.invalidate()
            self.progressView.isHidden = true
        }
        if(isRearCamera) {
            rearCameraSession.startRunning()
        } else {
            frontCameraSession.startRunning()
        }
        let oldStyle = self.currentStyle
        self.currentStyle = 0
        self.updateStyle(oldStyle: oldStyle)

        self.takePhotoButton.isEnabled = true
        self.takePhotoButton.isHidden = false
        self.clearImageButton.isEnabled = false
        self.clearImageButton.isHidden = true
        self.loadImageButton.isEnabled = true
        self.loadImageButton.isHidden = false
        self.toggleCameraButton.isHidden = false
        self.toggleCameraButton.isEnabled = true
        self.saveImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
        self.shareButton.isEnabled = false
        self.shareButton.isHidden = true
    }
    
    @IBAction func toggleCamera(_ sender: Any) {
        if self.isRearCamera {
            self.changeCamera()
            self.isRearCamera = false
        } else {
            self.changeCamera()
            self.isRearCamera = true
        }
    }
    
    @IBAction func swipeRight(_ sender: Any) {
        let oldStyle = self.currentStyle
        self.currentStyle = self.currentStyle - 1
        if(self.currentStyle < 0) {
            self.currentStyle = self.num_styles - 1
        }
        updateStyle(oldStyle: oldStyle)
    }
    
    @IBAction func swipeLeft(_ sender: Any) {
        let oldStyle = self.currentStyle
        self.currentStyle = (self.currentStyle + 1) % self.num_styles
        updateStyle(oldStyle: oldStyle)
    }
    
    func updateProgressView(frames: Int) {
        if(self.videoFrames[0].count == 0) {return}
        self.progressView.frame = CGRect(
            x: self.stylePreviewImageView!.frame.minX +
                (CGFloat(frames) /
                    CGFloat(self.videoFrames[0].count) *
                    self.stylePreviewImageView!.frame.width),
            y: self.stylePreviewImageView!.frame.minY,
            width: self.stylePreviewImageView!.frame.width *
                (1.0 - CGFloat(frames) /
                    CGFloat(self.videoFrames[0].count)),
            height: self.stylePreviewImageView!.frame.height
        )
    }
    
    func updateStyle(oldStyle: Int) {
        self.showStylePreview()
        if(self.isStylizingVideo) {
            self.videoStyleWasInterrupted = true
        }
        setModel(targetModel: modelList[self.currentStyle])
        if(self.displayingVideo && self.currentStyle != 0) {
            self.progressView.isHidden = false
            DispatchQueue.global().sync {
                while(self.isStylizingVideo) {} //busy wait on a separate thread
            }
            if(self.numFramesRendered[self.currentStyle] == self.videoFrames[0].count) {
                self.saveImageButton.isEnabled = true
                self.shareButton.isEnabled = true
                self.progressView.isHidden = true
                return
            }
            self.saveImageButton.isEnabled = false
            self.shareButton.isEnabled = false
            DispatchQueue.global().async {
                self.isStylizingVideo = true
                var finishedVideoStyle = false
                let style = self.currentStyle // thread-safe constant for which style this thread is working on
                for frame in self.videoFrames[0][self.numFramesRendered[style]..<self.videoFrames[0].count] {
                    if(self.videoStyleWasInterrupted) {break}
                    self.numFramesRendered[style] += 1
                    if(self.numFramesRendered[style] == self.videoFrames[0].count) {
                        finishedVideoStyle = true
                    }
                    DispatchQueue.main.async {
                        if(finishedVideoStyle) {
                            self.progressView.isHidden = true
                        } else {
                            self.updateProgressView(frames: self.numFramesRendered[style])
                        }
                    }
                    self.videoFrames[style].append(applyStyleTransfer(uiImage: frame, model: models[style-1]))
                }
                self.isStylizingVideo = false
                self.videoStyleWasInterrupted = false
                DispatchQueue.main.async {
                    if(finishedVideoStyle) {
                        self.hideStylePreviewAnimate()
                        self.saveImageButton.isEnabled = true
                        self.shareButton.isEnabled = true
                    }
                }
            }
        } else {
            self.updateProgressView(frames: self.videoFrames[0].count)
            self.saveImageButton.isEnabled = true
            self.shareButton.isEnabled = true
        }
        if(oldStyle == 0 && !self.displayingVideo) {
            self.videoFrames[0] = [self.imageView.image!];
        }
        self.perform_transfer = self.currentStyle != 0
        if(!rearCameraSession.isRunning && !frontCameraSession.isRunning) {
            // if we're looking at a single image TODO look @ this (maybe && !self.displayingVideo
            self.imageView.image = self.videoFrames[0][0];
        }
        if(self.perform_transfer) {
            self.stylizeAndUpdate()
        }
    }
    
    @IBAction func loadPhotoButtonPressed(_ sender: Any) {
        self.openPhotoLibrary()
    }
    
    func openPhotoLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.photoLibrary) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self as UIImagePickerControllerDelegate as? UIImagePickerControllerDelegate & UINavigationControllerDelegate
            imagePicker.sourceType = UIImagePickerControllerSourceType.photoLibrary
            imagePicker.mediaTypes = ["public.image", "public.movie"]
            self.present(imagePicker, animated: true)
        } else {
            print("Cannot open photo library")
            return
        }
    }
    
    func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self as UIImagePickerControllerDelegate as? UIImagePickerControllerDelegate & UINavigationControllerDelegate
            imagePicker.sourceType = UIImagePickerControllerSourceType.camera
            self.present(imagePicker, animated: true)
        } else {
            print("Cannot open camera")
            return
        }
    }
    
    func stylizeAndUpdate() {
        if(self.videoFrames[self.currentStyle].count == 0) {
            let image = (self.imageView.image!).scaled(to: CGSize(width: image_size, height: image_size), scalingMode: .aspectFill)
            self.videoFrames[self.currentStyle] = [applyStyleTransfer(uiImage: image, model: model)]
        }
        self.imageView.image = self.videoFrames[self.currentStyle][0]
    }
    
    func showStylePreview() {
        if (self.stylePreviewImageView.isHidden == false) {
            self.hideStylePreview()
            self.stylePreviewTimer?.invalidate()
        }
        if (self.currentStyle != 0) {
            self.stylePreviewImageView.image = UIImage(named: modelList[self.currentStyle] + "-source-image")
            self.stylePreviewImageView.isHidden = false
            self.stylePreviewImageBorder.isHidden = false
            self.stylePreviewTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(hideStylePreviewAnimate), userInfo: nil, repeats: false)
        }
    }
    
    @objc func hideStylePreviewAnimate() {
        if(self.isStylizingVideo) {return}
        self.stylePreviewAnimation = UIViewPropertyAnimator(duration: 1, curve: .easeOut, animations: {
            self.stylePreviewImageView.alpha = 0.0
            self.stylePreviewImageBorder.alpha = 0.0
        })
        self.stylePreviewAnimation!.addCompletion({ _ in
            self.hideStylePreview()
        })
        self.stylePreviewAnimation!.startAnimation()
    }
    
    func hideStylePreview() -> Void {
        self.stylePreviewAnimation?.stopAnimation(true)
        self.stylePreviewImageView.isHidden = true
        self.stylePreviewImageBorder.isHidden = true
        self.stylePreviewImageView.alpha = 1.0
        self.stylePreviewImageBorder.alpha = 0.9
    }
    
    @objc func cleanMemory() {
        // clean video frames
        for index in 0..<self.videoFrames.count {
            self.videoFrames[index] = []
            self.numFramesRendered[index] = 0
        }
        
        // invalidate timers
        self.videoTimer?.invalidate()
        self.stylePreviewTimer?.invalidate()
        
        unloadModels()
        
        // ui to default state
        self.takePhotoButton.isEnabled = true
        self.takePhotoButton.isHidden = false
        self.clearImageButton.isEnabled = false
        self.clearImageButton.isHidden = true
        self.loadImageButton.isEnabled = true
        self.loadImageButton.isHidden = false
        self.toggleCameraButton.isHidden = false
        self.toggleCameraButton.isEnabled = true
        self.saveImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
        self.shareButton.isEnabled = false
        self.shareButton.isHidden = true
    }
    
    @objc func reload() {
        self.rearCameraSession.startRunning()
        self.currentStyle = 0
        self.perform_transfer = false
        loadModels()
    }
    
}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true)
        }

        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            //make sure that the frames arrays are empty (this is almost always redundant, but can protect from an occasional thread collision issue.
            for index in 0..<self.videoFrames.count {
                self.videoFrames[index] = []
                self.numFramesRendered[index] = 0
            }
            
            // save to imageView
            let scaledImage = image.scaled(to: CGSize(width: self.image_size, height: self.image_size), scalingMode: .aspectFill)
            self.imageView.image = scaledImage
            self.videoFrames[0] = [scaledImage]
            if(self.currentStyle != 0) {
                self.stylizeAndUpdate()
            }
        }
        else if let videoUrl = info["UIImagePickerControllerMediaURL"] as? NSURL {
            //make sure that the frames arrays are empty (this is almost always redundant, but can protect from an occasional thread collision issue.
            for index in 0..<self.videoFrames.count {
                self.videoFrames[index] = []
                self.numFramesRendered[index] = 0
            }
            
            self.videoFormatHandler.videoToArray(videoResource: videoUrl)
        }
        else {
            return
        }
        
        self.clearImageButton.isEnabled = true
        self.clearImageButton.isHidden = false
        self.loadImageButton.isEnabled = false
        self.loadImageButton.isHidden = true
        
        self.takePhotoButton.isEnabled = false
        self.takePhotoButton.isHidden = true
        self.saveImageButton.isEnabled = true
        self.saveImageButton.isHidden = false
        self.shareButton.isEnabled = true
        self.shareButton.isHidden = false
        self.toggleCameraButton.isEnabled = false
        self.toggleCameraButton.isHidden = true
        
        if(isRearCamera) {
            rearCameraSession.stopRunning()
        } else {
            frontCameraSession.stopRunning()
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        defer {
            picker.dismiss(animated: true)
        }
        
        if(isRearCamera) {
            rearCameraSession.startRunning()
        } else {
            frontCameraSession.startRunning()
        }
        
        self.takePhotoButton.isEnabled = true
        self.takePhotoButton.isHidden = false
        
        self.clearImageButton.isEnabled = false
        self.clearImageButton.isHidden = true
        self.loadImageButton.isEnabled = true
        self.loadImageButton.isHidden = false
        
    }
}

