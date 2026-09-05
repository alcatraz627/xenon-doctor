import AppKit
import SceneKit

/// A solid 3D model of the pad. The body is the pad's outline extruded into a slab, the
/// controls are raised shapes on its face, and pressing one lights it up. Dragging orbits
/// the camera (SceneKit's own control, with inertia), scrolling zooms, double-click
/// re-centres. The view is a SceneKit view, so it resizes like any other view.
final class ControllerView: SCNView {
    var readings = PadReadings()

    private var buttons: [String: SCNNode] = [:]
    private var faceColors: [String: NSColor] = [:]
    private var leftKnob = SCNNode()
    private var rightKnob = SCNNode()
    private var leftFill = SCNNode()
    private var rightFill = SCNNode()
    private var lightBar = SCNNode()
    private var body = SCNNode()
    private var cameraNode = SCNNode()

    // Pad dimensions in scene units; the body is about 16 wide.
    private let depth: CGFloat = 2.2

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        scene = buildScene()
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        allowsCameraControl = true
        defaultCameraController.interactionMode = .orbitTurntable
        defaultCameraController.inertiaEnabled = true
        defaultCameraController.maximumVerticalAngle = 80
        defaultCameraController.minimumVerticalAngle = -20
        autoenablesDefaultLighting = false
        pointOfView = cameraNode
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resetCamera()
            return
        }
        super.mouseDown(with: event)
    }

    private func resetCamera() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        cameraNode.position = SCNVector3(0, -9, 15)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        SCNTransaction.commit()
    }

    // MARK: scene

    private func shellMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(white: 0.20, alpha: 1)
        m.roughness.contents = 0.55
        m.metalness.contents = 0.05
        return m
    }

    private func controlMaterial(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = 0.4
        m.metalness.contents = 0.1
        return m
    }

    private func node(_ geometry: SCNGeometry, at p: SCNVector3, key: String? = nil, color: NSColor = NSColor(white: 0.32, alpha: 1)) -> SCNNode {
        geometry.materials = [controlMaterial(color)]
        let n = SCNNode(geometry: geometry)
        n.position = p
        body.addChildNode(n)
        if let k = key { buttons[k] = n }
        return n
    }

    /// A short cylinder standing on the face, like a real button cap.
    private func cap(radius: CGFloat, height: CGFloat = 0.5, at p: SCNVector3, key: String, color: NSColor = NSColor(white: 0.32, alpha: 1)) -> SCNNode {
        let n = node(SCNCylinder(radius: radius, height: height), at: p, key: key, color: color)
        n.eulerAngles.x = .pi / 2
        return n
    }

    private func label(_ text: String, at p: SCNVector3, size: CGFloat = 0.55, color: NSColor = NSColor(white: 0.75, alpha: 1)) {
        let t = SCNText(string: text, extrusionDepth: 0.02)
        t.font = NSFont.systemFont(ofSize: size, weight: .semibold)
        t.flatness = 0.15
        t.materials = [controlMaterial(color)]
        let n = SCNNode(geometry: t)
        let (mn, mx) = t.boundingBox
        n.pivot = SCNMatrix4MakeTranslation((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0)
        n.position = p
        body.addChildNode(n)
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Body: the outline with two grips, extruded, in the XY plane facing the camera.
        let outline = NSBezierPath(roundedRect: NSRect(x: -8, y: -2.2, width: 16, height: 5.2), xRadius: 2.4, yRadius: 2.4)
        outline.appendRoundedRect(NSRect(x: -7.6, y: -6.2, width: 3.6, height: 5.5), xRadius: 1.7, yRadius: 1.7)
        outline.appendRoundedRect(NSRect(x: 4.0, y: -6.2, width: 3.6, height: 5.5), xRadius: 1.7, yRadius: 1.7)
        outline.windingRule = .nonZero
        outline.flatness = 0.02  // SceneKit polygonises the path at this tolerance; the default makes octagons of the grips
        let slab = SCNShape(path: outline, extrusionDepth: depth)
        slab.chamferRadius = 0.35
        slab.chamferMode = .both
        slab.materials = [shellMaterial()]
        body = SCNNode(geometry: slab)
        scene.rootNode.addChildNode(body)
        let face = depth / 2

        // Triggers and bumpers along the top edge, standing up from the body.
        for (side, x) in [("L", CGFloat(-5.2)), ("R", CGFloat(5.2))] {
            let trigger = SCNBox(width: 2.4, height: 1.0, length: 1.3, chamferRadius: 0.2)
            let tn = node(trigger, at: SCNVector3(x, 3.4, -0.2), key: "\(side)2")
            let fill = SCNBox(width: 2.2, height: 0.9, length: 0.15, chamferRadius: 0.05)
            let fn = node(fill, at: SCNVector3(0, 0, 0.72), color: .controlAccentColor)
            fn.removeFromParentNode()
            tn.addChildNode(fn)
            fn.scale = SCNVector3(0.001, 1, 1)
            if side == "L" { leftFill = fn } else { rightFill = fn }
            let bumper = SCNBox(width: 2.4, height: 0.45, length: 0.9, chamferRadius: 0.15)
            _ = node(bumper, at: SCNVector3(x, 2.7, face + 0.1), key: "\(side)1")
            label("\(side)1", at: SCNVector3(x, 2.7, face + 0.58), size: 0.4)
            label("\(side)2", at: SCNVector3(x, 3.4, 0.5), size: 0.4)
        }

        // D-pad: a cross of two bars in a shallow well.
        let well = SCNCylinder(radius: 1.7, height: 0.12)
        let wellNode = node(well, at: SCNVector3(-4.6, 0.6, face), color: NSColor(white: 0.14, alpha: 1))
        wellNode.eulerAngles.x = .pi / 2
        let dc = SCNVector3(-4.6, 0.6, face + 0.25)
        for (k, w, h, dx, dy) in [("up", 0.7, 1.0, 0.0, 0.75), ("down", 0.7, 1.0, 0.0, -0.75), ("left", 1.0, 0.7, -0.75, 0.0), ("right", 1.0, 0.7, 0.75, 0.0)] as [(String, CGFloat, CGFloat, CGFloat, CGFloat)] {
            _ = node(SCNBox(width: w, height: h, length: 0.45, chamferRadius: 0.12), at: SCNVector3(dc.x + dx, dc.y + dy, dc.z), key: k)
        }

        // Face buttons with PlayStation colours.
        let fwell = node(SCNCylinder(radius: 1.9, height: 0.12), at: SCNVector3(4.6, 0.6, face), color: NSColor(white: 0.14, alpha: 1))
        fwell.eulerAngles.x = .pi / 2
        let fc = SCNVector3(4.6, 0.6, face + 0.25)
        let faces: [(String, CGFloat, CGFloat, NSColor)] = [
            ("triangle", 0, 1.05, .systemGreen), ("cross", 0, -1.05, .systemBlue),
            ("square", -1.05, 0, .systemPink), ("circle", 1.05, 0, .systemRed),
        ]
        for (k, dx, dy, c) in faces {
            faceColors[k] = c
            _ = cap(radius: 0.45, at: SCNVector3(fc.x + dx, fc.y + dy, fc.z), key: k, color: c.blended(withFraction: 0.55, of: NSColor(white: 0.2, alpha: 1)) ?? c)
        }

        // Sticks: a recessed ring, a stalk, and a knob that leans with the reading.
        for (side, x) in [("L", CGFloat(-2.3)), ("R", CGFloat(2.3))] {
            let ring = node(SCNTorus(ringRadius: 1.05, pipeRadius: 0.18), at: SCNVector3(x, -1.3, face + 0.05), color: NSColor(white: 0.14, alpha: 1))
            ring.eulerAngles.x = .pi / 2
            let stalk = node(SCNCylinder(radius: 0.28, height: 0.9), at: SCNVector3(x, -1.3, face + 0.45), key: "\(side)3")
            stalk.eulerAngles.x = .pi / 2
            let knob = SCNSphere(radius: 0.7)
            let kn = node(knob, at: SCNVector3(x, -1.3, face + 1.0), color: NSColor(white: 0.28, alpha: 1))
            kn.scale = SCNVector3(1, 1, 0.55)
            if side == "L" { leftKnob = kn } else { rightKnob = kn }
            label("\(side)3", at: SCNVector3(x, -2.85, face + 0.05), size: 0.35, color: NSColor(white: 0.55, alpha: 1))
        }

        // Touchpad, Share, Options, PS, light bar.
        _ = node(SCNBox(width: 3.6, height: 1.7, length: 0.25, chamferRadius: 0.15), at: SCNVector3(0, 1.4, face + 0.1), key: "touchpad", color: NSColor(white: 0.26, alpha: 1))
        _ = node(SCNBox(width: 0.35, height: 0.9, length: 0.35, chamferRadius: 0.1), at: SCNVector3(-2.35, 1.6, face + 0.15), key: "share")
        _ = node(SCNBox(width: 0.35, height: 0.9, length: 0.35, chamferRadius: 0.1), at: SCNVector3(2.35, 1.6, face + 0.15), key: "options")
        label("Share", at: SCNVector3(-2.35, 0.75, face + 0.05), size: 0.3, color: NSColor(white: 0.55, alpha: 1))
        label("Options", at: SCNVector3(2.35, 0.75, face + 0.05), size: 0.3, color: NSColor(white: 0.55, alpha: 1))
        _ = cap(radius: 0.4, height: 0.35, at: SCNVector3(0, -0.5, face + 0.17), key: "ps")
        label("PS", at: SCNVector3(0, -0.5, face + 0.4), size: 0.3)
        let bar = SCNBox(width: 3.0, height: 0.22, length: 0.15, chamferRadius: 0.06)
        lightBar = node(bar, at: SCNVector3(0, 2.75, face + 0.02), color: NSColor(white: 0.1, alpha: 1))

        // Lights: a key light from the upper left, a soft fill, and ambient.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.castsShadow = true
        key.light?.shadowRadius = 6
        key.light?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        key.position = SCNVector3(-8, 10, 14)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 350
        fill.position = SCNVector3(9, -6, 10)
        scene.rootNode.addChildNode(fill)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        // Camera: front and a little above, looking at the centre of the pad.
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 42
        cameraNode.camera?.zNear = 1
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, -9, 15)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    // MARK: readings

    /// Pushes the latest readings into the model: lit buttons, leaning sticks, trigger fill.
    func apply() {
        let r = readings
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        // A darker shell, not a see-through one: opacity would show the inner faces.
        body.geometry?.firstMaterial?.diffuse.contents = NSColor(white: r.connected ? 0.20 : 0.12, alpha: 1)
        for (k, n) in buttons {
            let on = r.pressed.contains(k) || (k == "L2" && r.leftTrigger > 0.5) || (k == "R2" && r.rightTrigger > 0.5)
            let glow = faceColors[k] ?? NSColor.controlAccentColor
            n.geometry?.firstMaterial?.emission.contents = on ? glow : NSColor.black
            if let base = faceColors[k] {
                n.geometry?.firstMaterial?.diffuse.contents = on ? base : base.blended(withFraction: 0.55, of: NSColor(white: 0.2, alpha: 1))
            }
        }
        leftFill.scale = SCNVector3(max(0.001, CGFloat(r.leftTrigger)), 1, 1)
        rightFill.scale = SCNVector3(max(0.001, CGFloat(r.rightTrigger)), 1, 1)
        let face = depth / 2
        leftKnob.position = SCNVector3(-2.3 + r.leftStick.x * 0.55, -1.3 + r.leftStick.y * 0.55, face + 1.0)
        rightKnob.position = SCNVector3(2.3 + r.rightStick.x * 0.55, -1.3 + r.rightStick.y * 0.55, face + 1.0)
        leftKnob.eulerAngles = SCNVector3(-r.leftStick.y * 0.5, r.leftStick.x * 0.5, 0)
        rightKnob.eulerAngles = SCNVector3(-r.rightStick.y * 0.5, r.rightStick.x * 0.5, 0)
        lightBar.geometry?.firstMaterial?.emission.contents = r.connected ? NSColor.systemBlue : NSColor.black
        SCNTransaction.commit()
    }
}
