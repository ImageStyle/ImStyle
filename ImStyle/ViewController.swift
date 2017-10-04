//
//  ViewController.swift
//  ImStyle
//
//  Created by Jake Carlson on 10/3/17.
//  Copyright © 2017 ImageStyle. All rights reserved.
//

import UIKit
import MobileCoreServices
import QuartzCore

class ViewController: UIViewController {
    // image selection reference:
    // https://medium.com/@abhimuralidharan/accessing-photos-in-ios-swift-3-43da29ca4ccb
    
    @IBOutlet weak var openPhotoLib: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func openLibraryAction(_ sender: Any) {
        self.openPhotoLibrary()
        
    }
    
    func openPhotoLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.photoLibrary) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = UIImagePickerControllerSourceType.photoLibrary
            self.present(imagePicker, animated: true, completion: nil)
            
        } else {
            print("Cannot open photo library")
            return
        }
    }

}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true)
        }
        
        print(info)
        // get the image
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            return
        }
        
        // do something with it
        imageView.image = image
        
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        defer {
            picker.dismiss(animated: true)
        }
        
        print("Photo selection canceled")
    }
}

