/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's main view controller object.
*/

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    private var cameraView: CameraView { view as! CameraView }
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    private let drawOverlay = CAShapeLayer()
    private let drawPath = UIBezierPath()
    private var evidenceBuffer = [HandGestureProcessor.PointsPair]()
    private var lastDrawPoint: CGPoint?
    private var isFirstSegment = true
    private var lastObservationTimestamp = Date()
    
    private var gestureProcessor = HandGestureProcessor()
    
    @IBOutlet weak var fpsView: FpsView!
    @IBOutlet weak var showFPS: UILabel!
    var fps = 0
    var timer = Date()
    var fpspoints = [ 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        drawOverlay.frame = view.layer.bounds
        drawOverlay.lineWidth = 5
        drawOverlay.backgroundColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0).cgColor
        drawOverlay.strokeColor = #colorLiteral(red: 0.6, green: 0.1, blue: 0.3, alpha: 1).cgColor
        drawOverlay.fillColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0).cgColor
        drawOverlay.lineCap = .round
        view.layer.addSublayer(drawOverlay)
        // This sample app detects one hand only.
        handPoseRequest.maximumHandCount = 1
        // Add state change handler to hand gesture processor.
//        gestureProcessor.didChangeStateClosure = { [weak self] state in
//            self?.handleGestureStateChange(state: state)
//        }
        // Add double tap gesture recognizer for clearing the draw path.
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        recognizer.numberOfTouchesRequired = 1
        recognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(recognizer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            if cameraFeedSession == nil {
                cameraView.previewLayer.videoGravity = .resizeAspectFill
                try setupAVSession()
                cameraView.previewLayer.session = cameraFeedSession
            }
            cameraFeedSession?.startRunning()
        } catch {
            AppError.display(error, inViewController: self)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    func setupAVSession() throws {
        // Select a front facing camera, make an input.
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw AppError.captureSessionSetup(reason: "Could not find a front facing camera.")
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            throw AppError.captureSessionSetup(reason: "Could not create video device input.")
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            throw AppError.captureSessionSetup(reason: "Could not add video device input to the session")
        }
        session.addInput(deviceInput)
        
        var selectedFormat = videoDevice.formats.first
        
        for format in videoDevice.formats {
            let description = format.formatDescription as CMFormatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let width = dimensions.width
            let height = dimensions.height
            
            let maxFps = format.videoSupportedFrameRateRanges.first!.maxFrameRate

            if  120 <= maxFps && width == 1920 && height == 1080 {
              selectedFormat = format
            }
        }
        
        
        print(videoDevice.activeFormat.videoSupportedFrameRateRanges)
        try videoDevice.lockForConfiguration()
        videoDevice.activeFormat = selectedFormat!
        videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 120)
        videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 120)
        videoDevice.unlockForConfiguration()
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            throw AppError.captureSessionSetup(reason: "Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
}
    
    func processPoints(points: [CGPoint], lines: [HandGestureProcessor.PointsPair]) {
        // Check that we have both points.
        guard !points.isEmpty else {
            // If there were no observations for more than 2 seconds reset gesture processor.
//            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
//                gestureProcessor.reset()
//            }
            cameraView.showPoints([], lines: [], color: .clear)
            return
        }
        
        // Convert points from AVFoundation coordinates to UIKit coordinates.
        let previewLayer = cameraView.previewLayer
        
        var convertedPoints: [CGPoint] = []
        var convertedLines: [HandGestureProcessor.PointsPair] = []
        
        for point in points {
            convertedPoints.append(previewLayer.layerPointConverted(fromCaptureDevicePoint: point))
        }
        
        for line in lines {
            let (first, second) = line
            convertedLines.append((previewLayer.layerPointConverted(fromCaptureDevicePoint: first), previewLayer.layerPointConverted(fromCaptureDevicePoint: second)))
        }
        
    
        cameraView.showPoints(convertedPoints, lines: convertedLines, color: .orange)
        
        // Process new points
//        gestureProcessor.processPointsPair((thumbPointConverted, indexPointConverted))
    }
    
    private func handleGestureStateChange(state: HandGestureProcessor.State) {
        let pointsPair = gestureProcessor.lastProcessedPointsPair
        var tipsColor: UIColor
        switch state {
        case .possiblePinch, .possibleApart:
            // We are in one of the "possible": states, meaning there is not enough evidence yet to determine
            // if we want to draw or not. For now, collect points in the evidence buffer, so we can add them
            // to a drawing path when required.
            evidenceBuffer.append(pointsPair)
            tipsColor = .orange
        case .pinched:
            // We have enough evidence to draw. Draw the points collected in the evidence buffer, if any.
            for bufferedPoints in evidenceBuffer {
                updatePath(with: bufferedPoints, isLastPointsPair: false)
            }
            // Clear the evidence buffer.
            evidenceBuffer.removeAll()
            // Finally, draw the current point.
            updatePath(with: pointsPair, isLastPointsPair: false)
            tipsColor = .green
        case .apart, .unknown:
            // We have enough evidence to not draw. Discard any evidence buffer points.
            evidenceBuffer.removeAll()
            // And draw the last segment of our draw path.
            updatePath(with: pointsPair, isLastPointsPair: true)
            tipsColor = .red
        }
//        cameraView.showPoints([pointsPair.thumbTip, pointsPair.indexTip], color: tipsColor)
    }
    
    private func updatePath(with points: HandGestureProcessor.PointsPair, isLastPointsPair: Bool) {
        // Get the mid point between the tips.
        let (thumbTip, indexTip) = points
        let drawPoint = CGPoint.midPoint(p1: thumbTip, p2: indexTip)

        if isLastPointsPair {
            if let lastPoint = lastDrawPoint {
                // Add a straight line from the last midpoint to the end of the stroke.
                drawPath.addLine(to: lastPoint)
            }
            // We are done drawing, so reset the last draw point.
            lastDrawPoint = nil
        } else {
            if lastDrawPoint == nil {
                // This is the beginning of the stroke.
                drawPath.move(to: drawPoint)
                isFirstSegment = true
            } else {
                let lastPoint = lastDrawPoint!
                // Get the midpoint between the last draw point and the new point.
                let midPoint = CGPoint.midPoint(p1: lastPoint, p2: drawPoint)
                if isFirstSegment {
                    // If it's the first segment of the stroke, draw a line to the midpoint.
                    drawPath.addLine(to: midPoint)
                    isFirstSegment = false
                } else {
                    // Otherwise, draw a curve to a midpoint using the last draw point as a control point.
                    drawPath.addQuadCurve(to: midPoint, controlPoint: lastPoint)
                }
            }
            // Remember the last draw point for the next update pass.
            lastDrawPoint = drawPoint
        }
        // Update the path on the overlay layer.
        drawOverlay.path = drawPath.cgPath
    }
    
    @IBAction func handleGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        evidenceBuffer.removeAll()
        drawPath.removeAllPoints()
        drawOverlay.path = drawPath.cgPath
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var points: [CGPoint] = []
        var lines: [HandGestureProcessor.PointsPair] = []
        var conf = 0.0
        
        defer {
            DispatchQueue.main.sync {
                self.processPoints(points: points, lines: lines)
                
                let fps = Int(1/Date().timeIntervalSince(self.timer))
                self.timer = Date()
               
                self.fpspoints.remove(at: 0)
                self.fpspoints.append(fps)
                
                var pointsum = 0
                for point in self.fpspoints {
                    pointsum += point
                }
                
                self.showFPS.text = "FPS: \(pointsum / self.fpspoints.count)   AVG Confidence \(round(conf*100))"
                self.fpsView.showPoints(self.fpspoints)
                
            }
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            // Perform VNDetectHumanHandPoseRequest
            try handler.perform([handPoseRequest])
            // Continue only when a hand was detected in the frame.
            // Since we set the maximumHandCount property of the request to 1, there will be at most one observation.
            
            guard let observation = handPoseRequest.results?.first else {
                return
            }
            
            guard let thumbTipPoint = try? observation.recognizedPoint(.thumbTip),
                  let thumbIPPoint = try? observation.recognizedPoint(.thumbIP),
                  let thumbMPPoint = try? observation.recognizedPoint(.thumbMP),
                  let thumbCMCPoint = try? observation.recognizedPoint(.thumbCMC),
                    
                  let indexTipPoint = try? observation.recognizedPoint(.indexTip),
                  let indexDIPPoint = try? observation.recognizedPoint(.indexDIP),
                  let indexMCPPoint = try? observation.recognizedPoint(.indexMCP),
                  let indexPIPPoint = try? observation.recognizedPoint(.indexPIP),
                  
                  let middleTipPoint = try? observation.recognizedPoint(.middleTip),
                  let middleDIPPoint = try? observation.recognizedPoint(.middleDIP),
                  let middleMCPPoint = try? observation.recognizedPoint(.middleMCP),
                  let middlePIPPoint = try? observation.recognizedPoint(.middlePIP),
                  
                  let ringTipPoint = try? observation.recognizedPoint(.ringTip),
                  let ringDIPPoint = try? observation.recognizedPoint(.ringDIP),
                  let ringMCPPoint = try? observation.recognizedPoint(.ringMCP),
                  let ringPIPPoint = try? observation.recognizedPoint(.ringPIP),
                  
                  
                  let littleTipPoint = try? observation.recognizedPoint(.littleTip),
                  let littleDIPPoint = try? observation.recognizedPoint(.littleDIP),
                  let littleMCPPoint = try? observation.recognizedPoint(.littleMCP),
                  let littlePIPPoint = try? observation.recognizedPoint(.littlePIP),
                  
                  let wristPoint = try? observation.recognizedPoint(.wrist)
                    
            else {
                return
            }
            
            
            
            // Convert points from Vision coordinates to AVFoundation coordinates.
            points.append(CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y))
            points.append(CGPoint(x: thumbIPPoint.location.x, y: 1 - thumbIPPoint.location.y))
            lines.append((CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y),CGPoint(x: thumbIPPoint.location.x, y: 1 - thumbIPPoint.location.y)))
            points.append(CGPoint(x: thumbMPPoint.location.x, y: 1 - thumbMPPoint.location.y))
            lines.append((CGPoint(x: thumbIPPoint.location.x, y: 1 - thumbIPPoint.location.y),CGPoint(x: thumbMPPoint.location.x, y: 1 - thumbMPPoint.location.y)))
            points.append(CGPoint(x: thumbCMCPoint.location.x, y: 1 - thumbCMCPoint.location.y))
            lines.append((CGPoint(x: thumbMPPoint.location.x, y: 1 - thumbMPPoint.location.y),CGPoint(x: thumbCMCPoint.location.x, y: 1 - thumbCMCPoint.location.y)))
            lines.append((CGPoint(x: thumbCMCPoint.location.x, y: 1 - thumbCMCPoint.location.y),CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)))
            
            points.append(CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y))
            points.append(CGPoint(x: indexDIPPoint.location.x, y: 1 - indexDIPPoint.location.y))
            lines.append((CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y),CGPoint(x: indexDIPPoint.location.x, y: 1 - indexDIPPoint.location.y)))
            points.append(CGPoint(x: indexPIPPoint.location.x, y: 1 - indexPIPPoint.location.y))
            lines.append((CGPoint(x: indexDIPPoint.location.x, y: 1 - indexDIPPoint.location.y),CGPoint(x: indexPIPPoint.location.x, y: 1 - indexPIPPoint.location.y)))
            points.append(CGPoint(x: indexMCPPoint.location.x, y: 1 - indexMCPPoint.location.y))
            lines.append((CGPoint(x: indexPIPPoint.location.x, y: 1 - indexPIPPoint.location.y),CGPoint(x: indexMCPPoint.location.x, y: 1 - indexMCPPoint.location.y)))
            lines.append((CGPoint(x: indexMCPPoint.location.x, y: 1 - indexMCPPoint.location.y),CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)))
            
            points.append(CGPoint(x: middleTipPoint.location.x, y: 1 - middleTipPoint.location.y))
            points.append(CGPoint(x: middleDIPPoint.location.x, y: 1 - middleDIPPoint.location.y))
            lines.append((CGPoint(x: middleTipPoint.location.x, y: 1 - middleTipPoint.location.y),CGPoint(x: middleDIPPoint.location.x, y: 1 - middleDIPPoint.location.y)))
            points.append(CGPoint(x: middlePIPPoint.location.x, y: 1 - middlePIPPoint.location.y))
            lines.append((CGPoint(x: middleDIPPoint.location.x, y: 1 - middleDIPPoint.location.y),CGPoint(x: middlePIPPoint.location.x, y: 1 - middlePIPPoint.location.y)))
            points.append(CGPoint(x: middleMCPPoint.location.x, y: 1 - middleMCPPoint.location.y))
            lines.append((CGPoint(x: middlePIPPoint.location.x, y: 1 - middlePIPPoint.location.y),CGPoint(x: middleMCPPoint.location.x, y: 1 - middleMCPPoint.location.y)))
            lines.append((CGPoint(x: middleMCPPoint.location.x, y: 1 - middleMCPPoint.location.y),CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)))
            
            points.append(CGPoint(x: ringTipPoint.location.x, y: 1 - ringTipPoint.location.y))
            points.append(CGPoint(x: ringDIPPoint.location.x, y: 1 - ringDIPPoint.location.y))
            lines.append((CGPoint(x: ringTipPoint.location.x, y: 1 - ringTipPoint.location.y),CGPoint(x: ringDIPPoint.location.x, y: 1 - ringDIPPoint.location.y)))
            points.append(CGPoint(x: ringPIPPoint.location.x, y: 1 - ringPIPPoint.location.y))
            lines.append((CGPoint(x: ringDIPPoint.location.x, y: 1 - ringDIPPoint.location.y),CGPoint(x: ringPIPPoint.location.x, y: 1 - ringPIPPoint.location.y)))
            points.append(CGPoint(x: ringMCPPoint.location.x, y: 1 - ringMCPPoint.location.y))
            lines.append((CGPoint(x: ringPIPPoint.location.x, y: 1 - ringPIPPoint.location.y),CGPoint(x: ringMCPPoint.location.x, y: 1 - ringMCPPoint.location.y)))
            lines.append((CGPoint(x: ringMCPPoint.location.x, y: 1 - ringMCPPoint.location.y),CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)))
            
            
            points.append(CGPoint(x: littleTipPoint.location.x, y: 1 - littleTipPoint.location.y))
            points.append(CGPoint(x: littleDIPPoint.location.x, y: 1 - littleDIPPoint.location.y))
            lines.append((CGPoint(x: littleTipPoint.location.x, y: 1 - littleTipPoint.location.y),CGPoint(x: littleDIPPoint.location.x, y: 1 - littleDIPPoint.location.y)))
            points.append(CGPoint(x: littlePIPPoint.location.x, y: 1 - littlePIPPoint.location.y))
            lines.append((CGPoint(x: littleDIPPoint.location.x, y: 1 - littleDIPPoint.location.y),CGPoint(x: littlePIPPoint.location.x, y: 1 - littlePIPPoint.location.y)))
            points.append(CGPoint(x: littleMCPPoint.location.x, y: 1 - littleMCPPoint.location.y))
            lines.append((CGPoint(x: littlePIPPoint.location.x, y: 1 - littlePIPPoint.location.y),CGPoint(x: littleMCPPoint.location.x, y: 1 - littleMCPPoint.location.y)))
            lines.append((CGPoint(x: littleMCPPoint.location.x, y: 1 - littleMCPPoint.location.y),CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y)))
            
            points.append(CGPoint(x: wristPoint.location.x, y: 1 - wristPoint.location.y))
            
            var observedPoints: [VNRecognizedPoint] = []
            observedPoints.append(thumbTipPoint)
            observedPoints.append(thumbMPPoint)
            observedPoints.append(thumbIPPoint)
            observedPoints.append(thumbCMCPoint)
            observedPoints.append(indexTipPoint)
            observedPoints.append(indexMCPPoint)
            observedPoints.append(indexDIPPoint)
            observedPoints.append(indexPIPPoint)
            observedPoints.append(middleTipPoint)
            observedPoints.append(middleMCPPoint)
            observedPoints.append(middleDIPPoint)
            observedPoints.append(middlePIPPoint)
            observedPoints.append(littleTipPoint)
            observedPoints.append(littleMCPPoint)
            observedPoints.append(littleDIPPoint)
            observedPoints.append(littlePIPPoint)
            observedPoints.append(wristPoint)
            
            
            for point in observedPoints {
                conf = Double(point.confidence) + conf
            }
            conf = conf/17.0
            
        } catch {
            cameraFeedSession?.stopRunning()
            let error = AppError.visionError(error: error)
            DispatchQueue.main.async {
                error.displayInViewController(self)
            }
        }
    }
}

