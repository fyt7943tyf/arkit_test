//
//  ViewController.swift
//  arkit_test
//
//  Created by 付云天 on 2022/1/19.
//

import ARKit
import UIKit
import SceneKit
import AVFoundation

public struct Data : Codable {
    public var blendShapeKeys: [String]
    public var blendShapeValues: [[Float]]
    public var vertices: [[[Float]]]
    public var textureCoordinates: [[[Float]]]
    public var triangleIndices: [[Int16]]
    
    enum CodingKeys: String, CodingKey {
        case blendShapeKeys = "blend_shape_keys"
        case blendShapeValues = "blend_shape_values"
        case vertices
        case textureCoordinates = "texture_coordinates"
        case triangleIndices = "triangle_indices"
    }
}

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var switchCon: UISwitch!
    @IBOutlet var blendShapeText: UILabel!
    var contentNode: SCNNode?
    private let arHelper = ARHelper()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        switchCon.isOn = false
        switchCon.addTarget(self, action: #selector(switchChange), for: .valueChanged)
        self.view.addSubview(switchCon)
    }
    
    @objc func switchChange() {
        if (switchCon.isOn) {
            if (!arHelper.start()) {
                switchCon.isOn = false
            }
        } else {
            arHelper.stop()
        }
    }
    
    func displayErrorMessage(title: String, message: String) {
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }
    
    func resetTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        if #available(iOS 13.0, *) {
            configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        }
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        arHelper.inBuffer(frame: frame)
    }
    
}

extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let sceneView = renderer as? ARSCNView,
            anchor is ARFaceAnchor else { return }
        #if targetEnvironment(simulator)
        #error("ARKit is not supported in iOS Simulator. Connect a physical iOS device and select it as your Xcode run destination, or select Generic iOS Device as a build-only destination.")
        #else
        DispatchQueue.main.async {
            let faceGeometry = ARSCNFaceGeometry(device: sceneView.device!)!
            let material = faceGeometry.firstMaterial!
            material.diffuse.contents = #imageLiteral(resourceName: "wireframeTexture")
            material.lightingModel = .physicallyBased
            self.contentNode = SCNNode(geometry: faceGeometry)
            node.addChildNode(self.contentNode!)
        }
        #endif
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceGeometry = self.contentNode?.geometry as? ARSCNFaceGeometry,
            let faceAnchor = anchor as? ARFaceAnchor
            else { return }
        faceGeometry.update(from: faceAnchor.geometry)
        arHelper.render(anchor: faceAnchor)
        DispatchQueue.global().async {
            var showText = ""
            for i in 0..<self.arHelper.blendShapeKeys.count {
                showText += self.arHelper.blendShapeKeys[i].rawValue + " " + faceAnchor.blendShapes[self.arHelper.blendShapeKeys[i]]!.description + "\n"
            }
            DispatchQueue.main.async { [self] in
                self.blendShapeText.text = showText
            }
        }
    }
}

class ARHelper {
    var currentBuffer: CMSampleBuffer!
    var documentURL: URL!
    private var isStart = false
    private let unfairLock: UnsafeMutablePointer<os_unfair_lock> = {
            let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
            pointer.initialize(to: os_unfair_lock())
            return pointer
        }()
    private var timeStr = ""
    private var height = 0
    private var width = 0
    private var frameId = 0
    var videoWriter: AVAssetWriter?
    var writerInput: AVAssetWriterInput?
    var timeToIndex: Dictionary<Float64, Int> = [:]
    var outJsonData = Data(blendShapeKeys: [
        ARFaceAnchor.BlendShapeLocation.browDownLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.browDownRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.browInnerUp.rawValue,
        ARFaceAnchor.BlendShapeLocation.browOuterUpLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.browOuterUpRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.cheekPuff.rawValue,
        ARFaceAnchor.BlendShapeLocation.cheekSquintLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.cheekSquintRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeBlinkLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeBlinkRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookDownLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookDownRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookInLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookInRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookOutLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookOutRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookUpLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeLookUpRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeSquintLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeSquintRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeWideLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.eyeWideRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.jawForward.rawValue,
        ARFaceAnchor.BlendShapeLocation.jawLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.jawOpen.rawValue,
        ARFaceAnchor.BlendShapeLocation.jawRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthClose.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthDimpleLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthDimpleRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthFrownLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthFrownRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthFunnel.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthLowerDownLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthLowerDownRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthPressLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthPressRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthPucker.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthRollLower.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthRollUpper.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthShrugLower.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthShrugUpper.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthSmileLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthSmileRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthStretchLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthStretchRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthUpperUpLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.mouthUpperUpRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.noseSneerLeft.rawValue,
        ARFaceAnchor.BlendShapeLocation.noseSneerRight.rawValue,
        ARFaceAnchor.BlendShapeLocation.tongueOut.rawValue,
    ], blendShapeValues: [], vertices: [], textureCoordinates: [], triangleIndices: [])
    var blendShapeKeys: [ARFaceAnchor.BlendShapeLocation] = [
        ARFaceAnchor.BlendShapeLocation.browDownLeft,
        ARFaceAnchor.BlendShapeLocation.browDownRight,
        ARFaceAnchor.BlendShapeLocation.browInnerUp,
        ARFaceAnchor.BlendShapeLocation.browOuterUpLeft,
        ARFaceAnchor.BlendShapeLocation.browOuterUpRight,
        ARFaceAnchor.BlendShapeLocation.cheekPuff,
        ARFaceAnchor.BlendShapeLocation.cheekSquintLeft,
        ARFaceAnchor.BlendShapeLocation.cheekSquintRight,
        ARFaceAnchor.BlendShapeLocation.eyeBlinkLeft,
        ARFaceAnchor.BlendShapeLocation.eyeBlinkRight,
        ARFaceAnchor.BlendShapeLocation.eyeLookDownLeft,
        ARFaceAnchor.BlendShapeLocation.eyeLookDownRight,
        ARFaceAnchor.BlendShapeLocation.eyeLookInLeft,
        ARFaceAnchor.BlendShapeLocation.eyeLookInRight,
        ARFaceAnchor.BlendShapeLocation.eyeLookOutLeft,
        ARFaceAnchor.BlendShapeLocation.eyeLookOutRight,
        ARFaceAnchor.BlendShapeLocation.eyeLookUpLeft,
        ARFaceAnchor.BlendShapeLocation.eyeLookUpRight,
        ARFaceAnchor.BlendShapeLocation.eyeSquintLeft,
        ARFaceAnchor.BlendShapeLocation.eyeSquintRight,
        ARFaceAnchor.BlendShapeLocation.eyeWideLeft,
        ARFaceAnchor.BlendShapeLocation.eyeWideRight,
        ARFaceAnchor.BlendShapeLocation.jawForward,
        ARFaceAnchor.BlendShapeLocation.jawLeft,
        ARFaceAnchor.BlendShapeLocation.jawOpen,
        ARFaceAnchor.BlendShapeLocation.jawRight,
        ARFaceAnchor.BlendShapeLocation.mouthClose,
        ARFaceAnchor.BlendShapeLocation.mouthDimpleLeft,
        ARFaceAnchor.BlendShapeLocation.mouthDimpleRight,
        ARFaceAnchor.BlendShapeLocation.mouthFrownLeft,
        ARFaceAnchor.BlendShapeLocation.mouthFrownRight,
        ARFaceAnchor.BlendShapeLocation.mouthFunnel,
        ARFaceAnchor.BlendShapeLocation.mouthLeft,
        ARFaceAnchor.BlendShapeLocation.mouthLowerDownLeft,
        ARFaceAnchor.BlendShapeLocation.mouthLowerDownRight,
        ARFaceAnchor.BlendShapeLocation.mouthPressLeft,
        ARFaceAnchor.BlendShapeLocation.mouthPressRight,
        ARFaceAnchor.BlendShapeLocation.mouthPucker,
        ARFaceAnchor.BlendShapeLocation.mouthRight,
        ARFaceAnchor.BlendShapeLocation.mouthRollLower,
        ARFaceAnchor.BlendShapeLocation.mouthRollUpper,
        ARFaceAnchor.BlendShapeLocation.mouthShrugLower,
        ARFaceAnchor.BlendShapeLocation.mouthShrugUpper,
        ARFaceAnchor.BlendShapeLocation.mouthSmileLeft,
        ARFaceAnchor.BlendShapeLocation.mouthSmileRight,
        ARFaceAnchor.BlendShapeLocation.mouthStretchLeft,
        ARFaceAnchor.BlendShapeLocation.mouthStretchRight,
        ARFaceAnchor.BlendShapeLocation.mouthUpperUpLeft,
        ARFaceAnchor.BlendShapeLocation.mouthUpperUpRight,
        ARFaceAnchor.BlendShapeLocation.noseSneerLeft,
        ARFaceAnchor.BlendShapeLocation.noseSneerRight,
        ARFaceAnchor.BlendShapeLocation.tongueOut
    ]
    
    init() {
        let manager = FileManager.default
        let urls: [URL] = manager.urls(for: .documentDirectory, in: .userDomainMask)
        self.documentURL = urls.first!
    }
    
    func start() -> Bool {
        os_unfair_lock_lock(unfairLock)
        if (self.isStart) {
            return false
        }
        os_unfair_lock_unlock(unfairLock)
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-dd-HH:mm:ss:SSS"
        let timeStr = formatter.string(from: Date())
        guard let videoWriter = try? AVAssetWriter(outputURL: self.documentURL.appendingPathComponent(timeStr + ".mp4", isDirectory: false), fileType: AVFileType.mp4) else {
            os_unfair_lock_unlock(unfairLock)
            return false
        }
        let writerInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [AVVideoCodecKey:AVVideoCodecType.h264, AVVideoWidthKey:width, AVVideoHeightKey: height])
        writerInput.transform = CGAffineTransform(rotationAngle: .pi/2)
        videoWriter.add(writerInput)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: currentBuffer.presentationTimeStamp)
        while (!writerInput.isReadyForMoreMediaData) {
            Thread.sleep(forTimeInterval: 1)
        }
        os_unfair_lock_lock(unfairLock)
        self.timeStr = timeStr
        self.videoWriter = videoWriter
        self.writerInput = writerInput
        frameId = -1
        outJsonData.blendShapeValues = []
        timeToIndex = [:]
        self.isStart = true
        os_unfair_lock_unlock(unfairLock)
        return true
    }
    
    func stop() {
        os_unfair_lock_lock(unfairLock)
        if (!self.isStart) {
            return
        }
        writerInput?.markAsFinished()
        videoWriter?.finishWriting {
            print("done")
        }
        frameId = -1
        var json: String = ""
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.outJsonData)
            json = String(data: data, encoding: .utf8)!
        } catch {
        }
        let url = self.documentURL.appendingPathComponent(self.timeStr + ".json", isDirectory: true) // txt文件会自动创建，只要给个名称就行
        do {
          try json.write(to: url, atomically: true, encoding: .utf8)
        } catch {
          print("write string error:\(error)")
        }
        outJsonData.blendShapeValues = []
        outJsonData.vertices = []
        outJsonData.triangleIndices = []
        outJsonData.textureCoordinates = []
        timeToIndex = [:]
        self.isStart = false
        os_unfair_lock_unlock(unfairLock)
    }
    
    func inBuffer(frame: ARFrame) {
        var newSampleBuffer: CMSampleBuffer? = nil
        let scale = CMTimeScale(NSEC_PER_SEC)
        let pts = CMTime(value: CMTimeValue(frame.timestamp * Double(scale)),
                         timescale: scale)
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: pts,
                                            decodeTimeStamp: CMTime.invalid)
        let pixelBuffer = frame.capturedImage
        var videoInfo: CMVideoFormatDescription? = nil
     
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &videoInfo)
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: videoInfo!, sampleTiming: &timingInfo, sampleBufferOut: &newSampleBuffer)
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
        os_unfair_lock_lock(unfairLock)
        self.currentBuffer = newSampleBuffer
        if (isStart) {
            self.writerInput?.append(currentBuffer)
            frameId += 1
            outJsonData.blendShapeValues.append([])
            outJsonData.vertices.append([])
            outJsonData.textureCoordinates.append([])
            outJsonData.triangleIndices.append([])
            timeToIndex[CMTimeGetSeconds(currentBuffer.presentationTimeStamp) * 1e6] = frameId
        }
        os_unfair_lock_unlock(unfairLock)
    }
    
    func render(anchor: ARFaceAnchor) {
        os_unfair_lock_lock(unfairLock)
        if (!isStart || self.frameId < 0) {
            os_unfair_lock_unlock(unfairLock)
            return
        }
        var blendShapeData: [Float] = []
        for key in self.blendShapeKeys {
            blendShapeData.append(anchor.blendShapes[key]!.floatValue)
        }
        /*
        var verticesData: [[Float]] = []
        for vertice in anchor.geometry.vertices {
            verticesData.append([vertice.x, vertice.y, vertice.z])
        }
        var textureCoordinateData: [[Float]] = []
        for textureCoordinate in anchor.geometry.textureCoordinates {
            textureCoordinateData.append([textureCoordinate.x, textureCoordinate.y])
        }
         */
        let id = timeToIndex[CMTimeGetSeconds(currentBuffer.presentationTimeStamp) * 1e6]!
        self.outJsonData.blendShapeValues[id] = blendShapeData
        /*
        self.outJsonData.vertices[id] = verticesData
        self.outJsonData.textureCoordinates[id] = textureCoordinateData
        self.outJsonData.triangleIndices[id] = anchor.geometry.triangleIndices
         */
        os_unfair_lock_unlock(unfairLock)
    }
}
