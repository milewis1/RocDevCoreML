//
//  ViewController.swift
//  HandwritingDemo
//
//  Created by Michael Lewis-Swanson on 10/3/17.
//  Copyright © 2017 Michael Lewis-Swanson. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet private weak var imageView: TouchCanvas!
    @IBOutlet weak var predictionLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set an empty image so we have something to draw into
        imageView.image = UIImage()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    @IBAction func predictPressed(_ sender: Any) {
        
        if let inputImage = imageView.image {

            // Preprocessing... We need an image that is 28x28 and is not spatially distored
            // to get we'll resize the image so that the smallest size is equal to the size we
            // need and then crop out a 28x28 square
            let desiredSize:CGFloat = 28
            let minSide = min(inputImage.size.width, inputImage.size.height)
            guard let resizedImage = inputImage.resizeImage(ratio: desiredSize / minSide) else {
                print("Error resizing image")
                return
            }

            let centerX = Int((resizedImage.size.width - desiredSize) / 2.0)
            let centerY = Int((resizedImage.size.height - desiredSize) / 2.0)
            let croppedImage = resizedImage.crop(CGRect(x: CGFloat(centerX), y: CGFloat(centerY), width: desiredSize, height: desiredSize))
            let grayscale = croppedImage.convertToGrayScale()
            guard let inputBuffer = grayscale.pixelBuffer() else {
                print("Error preprocessing image")
                return
            }

            let model = mnist()
            do {

                let output = try model.prediction(image: inputBuffer)

                var maxIndex = 0
                var maxValue = -9999.0
                for i in 0..<output.output1.count {
                    if output.output1[i].doubleValue >= maxValue {
                        maxIndex = i
                        maxValue = output.output1[i].doubleValue
                    }
                }

                predictionLabel.text = String.localizedStringWithFormat("%d: %0.2f%%", maxIndex, maxValue * 100.0)

            } catch {
                print("Error predicting digit: \(error)")
            }

        }

    }
    
}

