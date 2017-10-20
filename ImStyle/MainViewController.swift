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
    @IBOutlet weak var videoStyleProgressBar: UIProgressView!
    
    let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front)!
    let rearCamera = AVCaptureDevice.default(for: .video)!
    let frontCameraSession = AVCaptureSession()
    let rearCameraSession = AVCaptureSession()
    let num_styles = modelList.count
    var stylePreviewAnimation: UIViewPropertyAnimator?
    var perform_transfer = false
    var currentStyle = 0
    var isStylizingVideo = false
    var recordingVideo = false
    var displayingVideo = false
    var videoStyleWasInterrupted = false
    var videoFrames: [UIImage] = []
    var stylizedVideoFrames: [UIImage] = []
    var videoPlaybackFrame = 0
    
    private var videoTimer : Timer? = nil
    private var stylePreviewTimer : Timer? = nil
    
    private var isRearCamera = true
    private var frontCaptureDevice: AVCaptureDevice?
    private var rearCaptureDevice: AVCaptureDevice?
    private var prevImage: UIImage?
    private let image_size = 720
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.stylePreviewImageView.isHidden = true
        self.stylePreviewImageBorder.isHidden = true
        self.stylePreviewImageBorder.layer.cornerRadius = 4
        
        self.clearImageButton.isEnabled = false
        
        self.rearCaptureDevice = rearCamera
        self.frontCaptureDevice = frontCamera
        
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
        self.videoStyleProgressBar.isHidden = true
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
            let img = UIImage(ciImage: ciImage).resizeTo(CGSize(width: 720, height: 720))
            if let uiImage = img {
                var outImage : UIImage
                if (perform_transfer) {
                    if(!isRearCamera){
                        self.prevImage = UIImage(cgImage: uiImage.cgImage!, scale: 1.0, orientation: .upMirrored)
                    } else {
                        self.prevImage = uiImage
                    }
                    outImage = applyStyleTransfer(uiImage: uiImage, model: model)
                } else {
                    outImage = uiImage;
                }
                if (!isRearCamera) {
                    outImage = UIImage(cgImage: outImage.cgImage!, scale: 1.0, orientation: .upMirrored)
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
        UIGraphicsBeginImageContext(CGSize(width: self.imageView.frame.size.width, height: self.imageView.frame.size.height))
        self.imageView.drawHierarchy(in: CGRect(x: 0.0, y: 0.0, width: self.imageView.frame.size.width, height: self.imageView.frame.size.height), afterScreenUpdates: true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        self.saveToPhotoLibrary(uiImage: image!)
    }
    
    @objc func startVideo() {
        if(self.currentStyle != 0) {
            print("TODO: alert user that you can't record live video in style")
            return
        }
        self.videoTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(saveFrame), userInfo: nil, repeats: true)
        self.loadImageButton.isHidden = true
        self.loadImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
        self.saveImageButton.isEnabled = false
        self.recordingVideo = true
        self.videoPlaybackFrame = 0
        self.videoFrames = []
    }
    
    @objc func saveFrame(){
        self.videoFrames.append(self.imageView.image!)
    }
    
    @objc func renderVideoFrame() {
        if(self.currentStyle == 0 || self.videoFrames.count != self.stylizedVideoFrames.count) {
            self.imageView.image = self.videoFrames[self.videoPlaybackFrame]
        } else {
            self.imageView.image = self.stylizedVideoFrames[self.videoPlaybackFrame]
        }
        self.videoPlaybackFrame += 1;
        if(self.videoPlaybackFrame == self.videoFrames.count) {
            self.videoPlaybackFrame = 0;
        }
    }
    
    @IBAction func takePhotoTouchDown(_ sender: Any) {
        self.videoTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(startVideo), userInfo: nil, repeats: false)
    }
    
    @IBAction func takePhotoTouchUpInside(_ sender: Any) {
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
            self.videoTimer!.invalidate()
        }
        self.toggleCameraButton.isEnabled = false
        self.toggleCameraButton.isHidden = true
        self.takePhotoButton.isEnabled = false
        self.takePhotoButton.isHidden = true
        self.saveImageButton.isEnabled = true
        self.saveImageButton.isHidden = false
        self.clearImageButton.isEnabled = true
        self.clearImageButton.isHidden = false
        self.loadImageButton.isEnabled = false
        self.loadImageButton.isHidden = true

    }
    
    @IBAction func clearImageAction(_ sender: Any) {
        if(self.displayingVideo) {
            self.displayingVideo = false
            self.videoTimer!.invalidate()
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
        self.toggleCameraButton.isHidden = false
        self.toggleCameraButton.isEnabled = true
        self.saveImageButton.isEnabled = false
        self.saveImageButton.isHidden = true
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
    
    func updateStyle(oldStyle: Int) {
        if(self.isStylizingVideo) {
            self.videoStyleWasInterrupted = true
        }
        setModel(targetModel: modelList[self.currentStyle])
        if(self.displayingVideo && self.currentStyle != 0) {
            DispatchQueue.global().sync {
                while(self.isStylizingVideo) {} //busy wait on a separate thread
            }
            self.saveImageButton.isEnabled = false
            self.clearImageButton.isEnabled = false
            self.videoStyleProgressBar.progress = 0;
            self.videoStyleProgressBar.isHidden = false
            DispatchQueue.global().async {
                self.isStylizingVideo = true
                self.stylizedVideoFrames = []
                for (index, frame) in self.videoFrames.enumerated() {
                    if(self.videoStyleWasInterrupted) {break}
                    DispatchQueue.main.async {
                        self.videoStyleProgressBar.progress = Float(index) / Float(self.videoFrames.count)
                    }
                    self.stylizedVideoFrames.append(applyStyleTransfer(uiImage: frame, model: model))
                }
                self.isStylizingVideo = false
                self.videoStyleWasInterrupted = false
                DispatchQueue.main.async {
                    if(!self.isStylizingVideo) {
                        self.videoStyleProgressBar.isHidden = true
                        self.saveImageButton.isEnabled = true
                        self.clearImageButton.isEnabled = true
                    }
                }
            }
        } else {
            self.videoStyleProgressBar.isHidden = true
        }
        if(oldStyle == 0) {
            self.prevImage = self.imageView.image;
        }
        self.perform_transfer = self.currentStyle != 0
        if(!rearCameraSession.isRunning && !frontCameraSession.isRunning) { // if we're looking at a single image
            self.imageView.image = self.prevImage;
        }
        if(self.perform_transfer) {
            self.stylizeAndUpdate()
        }
        self.showStylePreview()
    }
    
    @IBAction func loadPhotoButtonPressed(_ sender: Any) {
        self.openPhotoLibrary()
    }
    
    func openPhotoLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.photoLibrary) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self as UIImagePickerControllerDelegate as? UIImagePickerControllerDelegate & UINavigationControllerDelegate
            imagePicker.sourceType = UIImagePickerControllerSourceType.photoLibrary
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
        let image = (self.imageView.image!).scaled(to: CGSize(width: image_size, height: image_size), scalingMode: .aspectFit)
        let stylized_image = applyStyleTransfer(uiImage: image, model: model)
        self.imageView.image = stylized_image
    }
    
    func showStylePreview() {
        if (self.stylePreviewImageView.isHidden == false) {
            self.hideStylePreview()
            self.stylePreviewTimer?.invalidate()
        }
        if (self.currentStyle != 0) {
            self.stylePreviewImageView.image = UIImage(named: modelList[self.currentStyle] + "-source-image")
            //        self.stylePreviewImageView.alpha = 1
            self.stylePreviewImageView.isHidden = false
            self.stylePreviewImageBorder.isHidden = false
            self.stylePreviewTimer = Timer.scheduledTimer(timeInterval: 1.8, target: self, selector: #selector(hideStylePreviewAnimate), userInfo: nil, repeats: false)
        }
    }
    
    @objc func hideStylePreviewAnimate(timer: Timer) {
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
    
}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true)
        }

        // get the image
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            return
        }
        
        // save to imageView
        self.imageView.image = image
        self.prevImage = image
        if(self.currentStyle != 0) {
            self.stylizeAndUpdate()
        }
        self.clearImageButton.isEnabled = true
        self.clearImageButton.isHidden = false
        self.loadImageButton.isEnabled = false
        self.loadImageButton.isHidden = true
        
        self.takePhotoButton.isEnabled = false
        self.saveImageButton.isEnabled = true
        
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

