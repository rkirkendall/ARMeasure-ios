//
//  ViewController.swift
//  MeasureAR
//
//  Created by Ricky Kirkendall on 2/24/18.
//  Copyright © 2018 Ricky Kirkendall. All rights reserved.
//

import UIKit
import SceneKit
import ARKit


// Static vector math funcs

func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(
        left.x + right.x, left.y + right.y, left.z + right.z
    )
}
func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(
        left.x - right.x, left.y - right.y, left.z - right.z
    )
}

class Box: SCNNode {
    
    override init() {
        super.init()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    lazy var box: SCNNode = makeBox()
    
    func resizeTo(extent: Float) {
        var (min, max) = boundingBox
        max.x = extent
        update(minExtents: min, maxExtents: max)
    }
    
    func update(minExtents: SCNVector3, maxExtents: SCNVector3) {
        guard let scnBox = box.geometry as? SCNBox else {
            fatalError("Geometry is not SCNBox")
        }
        // Normalize the bounds so that min is always < max
        let absMin = SCNVector3(
            x: min(minExtents.x, maxExtents.x),
            y: min(minExtents.y, maxExtents.y),
            z: min(minExtents.z, maxExtents.z)
        )
        let absMax = SCNVector3(
            x: max(minExtents.x, maxExtents.x),
            y: max(minExtents.y, maxExtents.y),
            z: max(minExtents.z, maxExtents.z)
        )
        // Set the new bounding box
        boundingBox = (absMin, absMax)
        // Calculate the size vector
        let size = absMax - absMin
        // Take the absolute distance
        let absDistance = CGFloat(abs(size.x))
        // The new width of the box is the absolute distance
        scnBox.width = absDistance
        // Give it a offset of half the new size so they box remains fixed
        let offset = size.x * 0.5
        // Create a new vector with the min position
        // of the new bounding box
        let vector = SCNVector3(x: absMin.x, y: absMin.y, z: absMin.z)
        // And set the new position of the node with the offset
        box.position = vector + SCNVector3(x: offset, y: 0, z: 0)
    }
    
    func makeBox() -> SCNNode {
        let box = SCNBox(
            width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0
        )
        return convertToNode(geometry: box)
    }
    func convertToNode(geometry: SCNGeometry) -> SCNNode {
        for material in geometry.materials {
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white
            material.isDoubleSided = false
        }
        let node = SCNNode(geometry: geometry)
        self.addChildNode(node)
        return node
    }
}

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var textView: UITextView!
    
    var box: Box!
    var status: String!
    var startPosition: SCNVector3!
    var distance: Float!
    var trackingState: ARCamera.TrackingState!
    enum Mode {
        case waitingForMeasuring
        case measuring
    }
    
    var mode: Mode = .waitingForMeasuring {
        didSet {
            switch mode {
            case .waitingForMeasuring:
                status = "NOT READY"
            case .measuring:
                box.update(
                    minExtents: SCNVector3Zero, maxExtents: SCNVector3Zero)
                box.isHidden = false
                startPosition = nil
                distance = 0.0
                setStatusText()
            }
        }
    }
    
    func setStatusText() {
        var text = "Status: \(status!)\n"
        text += "Tracking: \(getTrackigDescription())\n"
        text += "Distance: \(String(format:"%.2f cm", distance! * 100.0))"
        textView.text = text
    }
    
    func getTrackigDescription() -> String {
        var description = ""
        if let t = trackingState {
            switch(t) {
            case .notAvailable:
                description = "TRACKING UNAVAILABLE"
            case .normal:
                description = "TRACKING NORMAL"
            case .limited(let reason):
                switch reason {
                case .excessiveMotion:
                    description =
                    "TRACKING LIMITED - Too much camera movement"
                case .insufficientFeatures:
                    description =
                    "TRACKING LIMITED - Not enough surface detail"
                case .initializing:
                    description = "INITIALIZING"
                }
            }
        }
        return description
    }
    
    
    @IBAction func switchChanged(_ sender: UISwitch) {
        
        if sender.isOn {
            mode = .measuring
        } else {
            mode = .waitingForMeasuring
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        // Set the view's delegate
        sceneView.delegate = self
        // Set a padding in the text view
        textView.textContainerInset =
            UIEdgeInsetsMake(20.0, 10.0, 10.0, 0.0)
        // Instantiate the box and add it to the scene
        box = Box()
        box.isHidden = true;
        sceneView.scene.rootNode.addChildNode(box)
        // Set the initial mode
        mode = .waitingForMeasuring
        // Set the initial distance
        distance = 0.0
        // Display the initial status
        setStatusText()
   }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Create a session configuration with plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the view's session
        sceneView.session.pause()
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        trackingState = camera.trackingState
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Call the method asynchronously to perform
        //  this heavy task without slowing down the UI
        DispatchQueue.main.async {
            self.measure()
            self.setStatusText()
        }
    }
    func measure() {
        let screenCenter : CGPoint = CGPoint(
            x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        let planeTestResults = sceneView.hitTest(
            screenCenter, types: [.existingPlaneUsingExtent])
        if let result = planeTestResults.first {
            status = "READY"
        } else {
            status = "NOT READY"
        }
        
        if let result = planeTestResults.first {
            status = "READY"
            if mode == .measuring {
                status = "MEASURING"
                let worldPosition = SCNVector3Make(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
                )
                
                if startPosition == nil {
                    startPosition = worldPosition
                    box.position = worldPosition
                }
                
                distance = calculateDistance(
                    from: startPosition!, to: worldPosition
                )
                
                box.resizeTo(extent: distance)
                
                let angleInRadians = calculateAngleInRadians(
                    from: startPosition!, to: worldPosition
                )
                box.rotation = SCNVector4(x: 0, y: 1, z: 0,
                                          w: -(angleInRadians + Float.pi)
                )
            }
        }
        
        
        
    }
    
    func calculateAngleInRadians(from: SCNVector3, to: SCNVector3) -> Float {
        let x = from.x - to.x
        let z = from.z - to.z
        return atan2(z, x)
    }
    
    func calculateDistance(from: SCNVector3, to: SCNVector3) -> Float {
        let x = from.x - to.x
        let y = from.y - to.y
        let z = from.z - to.z
        return sqrtf( (x * x) + (y * y) + (z * z))
    }


}

