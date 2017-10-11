//
//  ViewController.swift
//  RocDevDemoApp
//
//  Created by Michael Lewis-Swanson on 10/3/17.
//  Copyright © 2017 Michael Lewis-Swanson. All rights reserved.
//
import UIKit
import Photos
import Vision


class ViewController: UIViewController {
    private var orientationMap: [UIDeviceOrientation : AVCaptureVideoOrientation] = [
        .unknown            : .portrait,
        .portrait           : .portrait,
        .portraitUpsideDown : .portraitUpsideDown,
        .landscapeLeft      : .landscapeRight,
        .landscapeRight     : .landscapeLeft,
        .faceUp             : .portrait,
        .faceDown           : .portrait
    ]
    @IBOutlet weak var previewView: UIImageView!
    @IBOutlet weak var predicationLabel: UILabel!

    // MARK: - Camera Capture Properties
    var previewLayer:AVCaptureVideoPreviewLayer!
    var videoOutput: AVCaptureVideoDataOutput!
    var photoOutput:Any?
    var captureDevice: AVCaptureDevice!
    let session = AVCaptureSession()
    var model: VNCoreMLModel?
    private var sessionQueue = DispatchQueue(label: "camera session queue")
    private var sessionConfigured: Bool = false
    var requests: [VNRequest] = []
    var coremlRequest: VNRequest?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Make sure we can use the camera and if we can start it up
        checkCameraAuthorization { authorized in
            if authorized {

                self.sessionQueue.async { [weak self] in
                    guard let strongSelf = self else { return }

                    // We're good to go
                    if strongSelf.sessionConfigured {
                        if !strongSelf.session.isRunning {
                            strongSelf.session.startRunning()
                            strongSelf.startRectangleDetection()
                            //strongSelf.startObjectClassification()
                        }
                    } else {
                        strongSelf.beginSession()
                    }
                }
                return
            }
        }

    }

    override func viewDidLayoutSubviews() {
        previewView.layer.sublayers?[0].frame = previewView.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {

        sessionQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            if strongSelf.sessionConfigured && strongSelf.session.isRunning {
                strongSelf.session.stopRunning()
            }
        }

        super.viewWillDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Private Functions
    private func checkCameraAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            completionHandler(true)

        case .notDetermined:

            // The user has not yet been presented with the option to grant video access so request access.
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { success in
                completionHandler(success)
            })

        case .denied:
            completionHandler(false)
        case .restricted:
            completionHandler(false)
        }
    }

    private func startRectangleDetection() {
        let detectRectangles = VNDetectRectanglesRequest(completionHandler: self.dectectRectanglesHandler)
        detectRectangles.minimumConfidence = 0.25
        detectRectangles.maximumObservations = 10
        detectRectangles.minimumSize = 5
        requests.append(detectRectangles)
    }

    private func dectectRectanglesHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results else {
            print("no result")
            return
        }
        let result = observations.map({$0 as? VNRectangleObservation})

        DispatchQueue.main.async() {
            self.predicationLabel.text = ""
        }

        // Do the object recognition
        for region in result {
            guard let rg = region else { continue }

            let imageRect = transformRect(fromRect: rg.boundingBox, toViewRect: previewView)
            let handler = VNImageRequestHandler(cgImage: (previewView.image?.cgImage?.cropping(to: imageRect))!, options: [:])
            do {
                try handler.perform([self.coremlRequest!])
            } catch {
                print("CoreML Request Failed: \(error)")
            }
        }

        // Draw our rectangles
        DispatchQueue.main.async() {
            self.previewView.layer.sublayers?.removeSubrange(1...)
            for region in result {
                guard let rg = region else { continue }
                self.highlightRectangle(box: rg)
            }
        }

    }

    private func highlightRectangle(box: VNRectangleObservation) {
        let transformed = transformRect(fromRect: box.boundingBox, toViewRect: self.previewView)

        let outline = CALayer()
        outline.frame = transformed
        outline.borderWidth = 2.0
        outline.borderColor = UIColor.yellow.cgColor
        
//        let text = CATextLayer()
//        text.frame = CGRect(x: transformed.minX + 8, y: transformed.minY + 8, width: transformed.width, height: transformed.height)
//        text.string = "Object XXXXXXXXXXXXX: 99.99%"
//        text.fontSize = 12
//        text.foregroundColor = UIColor.green.cgColor

        previewView.layer.addSublayer(outline)
//        previewView.layer.addSublayer(text)
    }
    
    // NOTE: Important notes about the conversion
//    Vision: origin ---> bottom left
//    Size ---> Max value of 1
//    UIkit : origin ---> top left
//    Size ---> UIVIEW bounds
    func transformRect(fromRect: CGRect , toViewRect :UIView) -> CGRect {
        
        var toRect = CGRect()
        toRect.size.width = fromRect.size.width * toViewRect.frame.size.width
        toRect.size.height = fromRect.size.height * toViewRect.frame.size.height
        toRect.origin.y =  (toViewRect.frame.height) - (toViewRect.frame.height * fromRect.origin.y )
        toRect.origin.y  = toRect.origin.y -  toRect.size.height
        toRect.origin.x =  fromRect.origin.x * toViewRect.frame.size.width
        
        return toRect
    }
    
    // MARK: - CoreML Vision Handlers
    private func startObjectClassification() {
        do {
            model = try VNCoreMLModel(for: MobileNet().model)
            coremlRequest = VNCoreMLRequest(model: model!, completionHandler: { [weak self] request, error in
                self?.processClassifications(request: request, error: error)
            })
            self.requests = [coremlRequest!]
        } catch {
            print("Error loading model: \(error)")
        }
    }
    
    private func processClassifications(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else {
            print("Unexpected result type from VNCoreMLRequest")
            return
        }

        // Update UI on main queue
        DispatchQueue.main.async { [weak self] in
            let topResultText = "\(Int(results[0].confidence * 100))% it's \(results[0].identifier)"
            let secondResultText = "\(Int(results[1].confidence * 100))% it's \(results[1].identifier)"
            self?.predicationLabel.text = "\(topResultText)\n\(secondResultText)"
        }
    }

}


// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func beginSession() {

        // Choose the back dual camera if available, otherwise default to a wide angle camera.
        if #available(iOS 10.0, *) {
//            let output = AVCapturePhotoOutput()
//            output.isHighResolutionCaptureEnabled = true
//            output.isLivePhotoCaptureEnabled = false
//            photoOutput = output

            session.beginConfiguration()
            session.sessionPreset = AVCaptureSession.Preset.photo

            var defaultVideoDevice: AVCaptureDevice?
            do {
                if let defaultCameraDevice = AVCaptureDevice.default(for: .video)  {
                    defaultVideoDevice = defaultCameraDevice

                    let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
                    if session.canAddInput(videoDeviceInput) {
                        session.addInput(videoDeviceInput)
                    } else {
                        print("Could not add video device input to the session")
                        return
                    }
                } else {
                    print("Failed to get default video device. We're probably in the simulator.")
                    return
                }
            } catch {
                print("Failed to get capture device input.")
                return
            }

            // Add photo output
            // Setup our output (we need BGR image data for CoreML)
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .default))
            if (session.canAddOutput(videoOutput)) {
                session.addOutput(videoOutput)
            } else {
                print("Could not add photo output to the session")
                return
            }

            session.commitConfiguration()
            sessionConfigured = true

            // For iOS 9.x
        } else {

            // We don't need high resolution for what we're doing, just needs to be over 600x600
            session.sessionPreset = AVCaptureSession.Preset.photo

            guard let device = AVCaptureDevice.default(for: .video) else { return }
            captureDevice = device

            var err : NSError? = nil
            var deviceInput:AVCaptureDeviceInput?
            do {
                deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            } catch let error as NSError {
                err = error
                NSLog("Failed to get camera input: %s", err?.description ?? "Unknown Error")
                deviceInput = nil
                return
            }

            // Add the input
            if (session.canAddInput(deviceInput!)) {
                session.addInput(deviceInput!);
            }

            // Setup our output (we need BGR image data for CoreML)
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .default))
            if (session.canAddOutput(videoOutput)) {
                session.addOutput(videoOutput)
            }

        }

        // Setup the camera preview
        previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        //previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        //previewLayer.connection?.videoOrientation = self.videoOrientationForDeviceOrientation().0

        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }

            let rootLayer:CALayer = strongSelf.previewView.layer
            //rootLayer.masksToBounds = true
            strongSelf.previewLayer.frame = rootLayer.bounds
            rootLayer.addSublayer(strongSelf.previewLayer)
        }

        session.startRunning()
        startRectangleDetection()
        //startObjectClassification()
    }

    func videoOrientationForDeviceOrientation() -> (AVCaptureVideoOrientation, UIDeviceOrientation) {
        let deviceOrientation = UIDevice.current.orientation
        guard let newVideoOrientation = orientationMap[deviceOrientation] else { return (.portrait, .portrait) }

        return (newVideoOrientation, deviceOrientation)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var requestOptions:[VNImageOption : Any] = [:]

        if let camData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics:camData]
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }

}
