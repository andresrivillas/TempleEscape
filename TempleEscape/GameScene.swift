import SceneKit
import UIKit

// MARK: - Collision categories

enum BitMask {
    static let player: Int = 1 << 0
    static let obstacle: Int = 1 << 1
    static let coin: Int = 1 << 2
    static let boulder: Int = 1 << 3
}

/// The 3D game world. Everything is built procedurally from SceneKit
/// primitives — no external assets needed.
final class GameScene: SCNScene, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {

    weak var viewModel: GameViewModel?
    weak var scnView: SCNView?

    // MARK: - Constants

    private let tileLength: Float = 6
    private let tileCount = 6
    private let spawnZ: Float = -26

    // MARK: - State

    private var phase: GamePhase = .menu
    private var speed: Float = 0
    private var distance: Float = 0
    private var lastTime: TimeInterval?
    private var frameQueued = false
    private var dead = false
    private var runTime: Float = 0
    private var panStart = CGPoint.zero

    // Player
    private var playerNode: SCNNode!
    private var bodyRoot: SCNNode!
    private var leftLeg: SCNNode!
    private var rightLeg: SCNNode!
    private var leftArm: SCNNode!
    private var rightArm: SCNNode!
    private var scarf: SCNNode!
    private var playerBody: SCNPhysicsBody!
    private var standShape: SCNPhysicsShape!
    private var slideShape: SCNPhysicsShape!
    private var currentLane = 1
    private var grounded = true
    private var jumpMotion = TempleRules.JumpMotion()
    private var sliding = false
    private var slideTimer: Float = 0
    private var lanternLight: SCNLight?

    // World
    private var tiles: [SCNNode] = []
    private var boulderNode: SCNNode!
    private var cameraNode: SCNNode!
    private var lookTarget: SCNNode!
    private var torchLights: [SCNNode] = []

    // MARK: - Init

    override init() {
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Material helpers

    private func material(
        _ color: UIColor,
        roughness: Float = 0.8,
        metalness: Float = 0.0,
        emission: UIColor? = nil,
        emissionIntensity: CGFloat = 0
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        if let e = emission {
            m.emission.contents = e
            m.emission.intensity = emissionIntensity
        }
        return m
    }

    private func node(_ geometry: SCNGeometry, _ mat: SCNMaterial, name: String? = nil) -> SCNNode {
        geometry.materials = [mat]
        let n = SCNNode(geometry: geometry)
        n.name = name
        return n
    }

    /// Soft, non-PBR material — avoids light clipping on large surfaces like the ground.
    private func blinnMaterial(_ color: UIColor, shininess: CGFloat = 8) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor(white: 0.12, alpha: 1)
        m.shininess = shininess
        return m
    }

    /// A soft round sprite so particles don't render as harsh squares.
    private static let softParticleImage: UIImage? = {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(1.0).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                c.drawRadialGradient(grad, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
    }()

    // MARK: - World setup

    func setupWorld() {
        physicsWorld.gravity = SCNVector3(0, TempleRules.gravity, 0)
        physicsWorld.contactDelegate = self

        // Atmosphere: warm sunset haze
        fogStartDistance = 24
        fogEndDistance = 62
        fogColor = UIColor(red: 0.78, green: 0.6, blue: 0.46, alpha: 1)

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 1.0, green: 0.78, blue: 0.42, alpha: 1).cgColor,
            UIColor(red: 0.9, green: 0.5, blue: 0.34, alpha: 1).cgColor,
            UIColor(red: 0.45, green: 0.32, blue: 0.5, alpha: 1).cgColor,
            UIColor(red: 0.14, green: 0.16, blue: 0.28, alpha: 1).cgColor,
        ]
        gradient.locations = [0, 0.3, 0.65, 1]
        gradient.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        background.contents = gradient

        // Sun disc + halo (additive so it glows through the haze)
        let sun = node(
            SCNSphere(radius: 5),
            material(.clear, emission: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), emissionIntensity: 1.2)
        )
        sun.position = SCNVector3(20, 22, -52)
        rootNode.addChildNode(sun)
        let haloMat = material(.clear, emission: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 0.5), emissionIntensity: 1)
        haloMat.blendMode = .add
        haloMat.writesToDepthBuffer = false
        let halo = node(SCNSphere(radius: 11), haloMat)
        halo.position = sun.position
        rootNode.addChildNode(halo)

        lightingEnvironment.contents = UIColor(white: 0.22, alpha: 1)

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 62
        cam.zNear = 0.1
        cam.zFar = 300
        cameraNode = SCNNode()
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 2.9, 5.4)
        lookTarget = SCNNode()
        lookTarget.position = SCNVector3(0, 1.15, -10)
        rootNode.addChildNode(lookTarget)
        cameraNode.constraints = [SCNLookAtConstraint(target: lookTarget)]
        rootNode.addChildNode(cameraNode)

        // Ambient fill
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.78, green: 0.73, blue: 0.68, alpha: 1)
        ambient.intensity = 210
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        // Golden sun light (shadows)
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.color = UIColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1)
        sunLight.intensity = 560
        sunLight.castsShadow = true
        sunLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunLight.shadowSampleCount = 6
        sunLight.shadowRadius = 5
        sunLight.shadowColor = UIColor(white: 0, alpha: 0.38)
        sunLight.orthographicScale = 14
        sunLight.zNear = 1
        sunLight.zFar = 60
        let sunLightNode = SCNNode()
        sunLightNode.light = sunLight
        sunLightNode.position = SCNVector3(3, 22, 6)
        sunLightNode.eulerAngles = SCNVector3(-1.0, 0.15, 0.25)
        rootNode.addChildNode(sunLightNode)

        // Fireflies drifting around the camera
        let ff = SCNParticleSystem()
        ff.birthRate = 6
        ff.particleLifeSpan = 7
        ff.particleLifeSpanVariation = 3
        ff.particleSize = 0.035
        ff.particleSizeVariation = 0.02
        ff.particleVelocity = 0.25
        ff.particleVelocityVariation = 0.2
        ff.emitterShape = SCNSphere(radius: 7)
        ff.particleColor = UIColor(red: 0.8, green: 1, blue: 0.6, alpha: 0.85)
        ff.particleImage = GameScene.softParticleImage
        ff.isAffectedByGravity = false
        ff.blendMode = .additive
        let ffNode = SCNNode()
        ffNode.addParticleSystem(ff)
        cameraNode.addChildNode(ffNode)

        buildPlayer()
        buildBoulder()
        buildTiles()
    }

    // MARK: - Player

    private func buildPlayer() {
        playerNode = SCNNode()
        playerNode.name = "player"
        playerNode.position = SCNVector3(0, 0, 0)

        bodyRoot = SCNNode()
        playerNode.addChildNode(bodyRoot)

        // Torso
        let torso = node(
            SCNBox(width: 0.42, height: 0.52, length: 0.24, chamferRadius: 0.08),
            material(UIColor(red: 0.66, green: 0.45, blue: 0.25, alpha: 1), roughness: 0.85)
        )
        torso.position = SCNVector3(0, 0.82, 0)
        bodyRoot.addChildNode(torso)

        // Belt / satchel
        let belt = node(
            SCNBox(width: 0.46, height: 0.09, length: 0.3, chamferRadius: 0.03),
            material(UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1), roughness: 0.9)
        )
        belt.position = SCNVector3(0, 0.6, 0)
        bodyRoot.addChildNode(belt)

        // Head
        let head = node(
            SCNSphere(radius: 0.14),
            material(UIColor(red: 0.85, green: 0.68, blue: 0.52, alpha: 1), roughness: 0.7)
        )
        head.position = SCNVector3(0, 1.22, 0)
        bodyRoot.addChildNode(head)

        // Explorer helmet (brim + dome)
        let hatMat = material(UIColor(red: 0.72, green: 0.65, blue: 0.5, alpha: 1), roughness: 0.75)
        let brim = node(SCNCylinder(radius: 0.2, height: 0.035), hatMat)
        brim.position = SCNVector3(0, 1.32, 0)
        bodyRoot.addChildNode(brim)
        let dome = node(SCNSphere(radius: 0.1), hatMat)
        dome.position = SCNVector3(0, 1.4, 0)
        dome.scale = SCNVector3(1, 0.85, 1)
        bodyRoot.addChildNode(dome)

        // Red scarf
        scarf = node(
            SCNBox(width: 0.3, height: 0.07, length: 0.44, chamferRadius: 0.02),
            material(UIColor(red: 0.85, green: 0.22, blue: 0.18, alpha: 1), roughness: 0.9)
        )
        scarf.position = SCNVector3(0, 1.02, -0.14)
        bodyRoot.addChildNode(scarf)

        // Limbs: pivot at the joint, capsule hanging down
        func makeLimb(width: Float, height: Float, color: UIColor) -> SCNNode {
            let pivot = SCNNode()
            let seg = node(SCNCapsule(capRadius: CGFloat(width), height: CGFloat(height)), material(color, roughness: 0.85))
            seg.position = SCNVector3(0, -height / 2, 0)
            pivot.addChildNode(seg)
            return pivot
        }

        let legMat = UIColor(red: 0.42, green: 0.32, blue: 0.22, alpha: 1)
        let armMat = UIColor(red: 0.62, green: 0.42, blue: 0.23, alpha: 1)
        leftLeg = makeLimb(width: 0.075, height: 0.42, color: legMat)
        rightLeg = makeLimb(width: 0.075, height: 0.42, color: legMat)
        leftLeg.position = SCNVector3(-0.11, 0.45, 0)
        rightLeg.position = SCNVector3(0.11, 0.45, 0)
        bodyRoot.addChildNode(leftLeg)
        bodyRoot.addChildNode(rightLeg)
        leftArm = makeLimb(width: 0.06, height: 0.36, color: armMat)
        rightArm = makeLimb(width: 0.06, height: 0.36, color: armMat)
        leftArm.position = SCNVector3(-0.25, 0.95, 0)
        rightArm.position = SCNVector3(0.25, 0.95, 0)
        bodyRoot.addChildNode(leftArm)
        bodyRoot.addChildNode(rightArm)

        // Physics
        let standNode = SCNNode()
        standNode.geometry = SCNCapsule(capRadius: 0.3, height: 1.05)
        standNode.position = SCNVector3(0, 0.78, 0)
        standShape = SCNPhysicsShape(node: standNode, options: nil)
        let slideNode = SCNNode()
        slideNode.geometry = SCNCapsule(capRadius: 0.3, height: 0.55)
        slideNode.position = SCNVector3(0, 0.45, 0)
        slideShape = SCNPhysicsShape(node: slideNode, options: nil)
        playerBody = SCNPhysicsBody(type: .dynamic, shape: standShape)
        playerBody.mass = 1
        playerBody.isAffectedByGravity = false // jump is integrated manually
        playerBody.restitution = 0
        playerBody.friction = 0.8
        playerBody.categoryBitMask = BitMask.player
        playerBody.collisionBitMask = 0
        playerBody.contactTestBitMask = BitMask.obstacle | BitMask.coin | BitMask.boulder
        playerNode.physicsBody = playerBody
        rootNode.addChildNode(playerNode)

        // Lantern the explorer carries — warm glow that flickers
        let lantern = SCNLight()
        lantern.type = .omni
        lantern.color = UIColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1)
        lantern.intensity = 130
        lantern.attenuationStartDistance = 1.2
        lantern.attenuationEndDistance = 9
        lantern.attenuationFalloffExponent = 2
        lanternLight = lantern
        let lanternNode = SCNNode()
        lanternNode.light = lantern
        lanternNode.position = SCNVector3(0.5, 1.45, 1.0)
        playerNode.addChildNode(lanternNode)
        let lanternGem = node(
            SCNSphere(radius: 0.05),
            material(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), emission: UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1), emissionIntensity: 1)
        )
        lanternGem.position = SCNVector3(0.32, 1.0, 0.6)
        playerNode.addChildNode(lanternGem)
    }

    // MARK: - Boulder

    private func buildBoulder() {
        let rock = material(UIColor(red: 0.34, green: 0.31, blue: 0.27, alpha: 1), roughness: 0.95, metalness: 0.05)
        let geo = SCNSphere(radius: CGFloat(TempleRules.boulderRadius))
        geo.segmentCount = 32
        boulderNode = node(geo, rock, name: "boulder")
        boulderNode.position = SCNVector3(0, 0.9, TempleRules.boulderChaseZ)

        // Lumps to break the perfect sphere
        let lumpMat = material(UIColor(red: 0.42, green: 0.38, blue: 0.33, alpha: 1), roughness: 0.95)
        let darkLumpMat = material(UIColor(red: 0.28, green: 0.26, blue: 0.23, alpha: 1), roughness: 1)
        for i in 0..<10 {
            let r: Float = 0.22 + Float(i % 4) * 0.07
            let lump = node(SCNSphere(radius: CGFloat(r)), i % 3 == 0 ? darkLumpMat : lumpMat)
            let a = Float(i) * 0.9
            let b: Float = i % 2 == 0 ? 1 : -1
            let dir = SCNVector3(cos(a) * 0.75, sin(a) * 0.45 * b, sin(a) * 0.7)
            lump.position = SCNVector3(
                dir.x * (0.9 + r * 0.55),
                dir.y * (0.9 + r * 0.55) + 0.3,
                dir.z * (0.9 + r * 0.55)
            )
            boulderNode.addChildNode(lump)
        }
        // A couple of deep "cracks": thin dark boxes sunk into the surface
        let crackMat = material(UIColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1), roughness: 1)
        for i in 0..<3 {
            let crack = node(SCNBox(width: 0.05, height: 0.05, length: 0.55, chamferRadius: 0), crackMat)
            let a = Float(i) * 2.1
            crack.position = SCNVector3(cos(a) * 0.85, 0.15 + Float(i) * 0.28, sin(a) * 0.85)
            crack.eulerAngles = SCNVector3(0.3, a, 0.5)
            boulderNode.addChildNode(crack)
        }

        let body = SCNPhysicsBody(
            type: .kinematic,
            shape: SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(TempleRules.boulderRadius)), options: nil)
        )
        body.categoryBitMask = BitMask.boulder
        body.collisionBitMask = 0
        body.contactTestBitMask = BitMask.player
        boulderNode.physicsBody = body
        rootNode.addChildNode(boulderNode)

        // Dust trail
        let dust = SCNParticleSystem()
        dust.birthRate = 70
        dust.particleLifeSpan = 0.8
        dust.particleLifeSpanVariation = 0.3
        dust.particleSize = 0.18
        dust.particleSizeVariation = 0.09
        dust.particleVelocity = 0.4
        dust.particleVelocityVariation = 0.35
        dust.spreadingAngle = 35
        dust.emitterShape = SCNSphere(radius: 1.0)
        dust.particleColor = UIColor(red: 0.62, green: 0.55, blue: 0.45, alpha: 0.4)
        dust.particleImage = GameScene.softParticleImage
        dust.isAffectedByGravity = false
        dust.blendMode = .alpha
        let dustNode = SCNNode()
        dustNode.position = SCNVector3(0, 0.2, -0.9)
        dustNode.addParticleSystem(dust)
        boulderNode.addChildNode(dustNode)
    }

    // MARK: - Tiles (recycled ground segments)

    private func buildTiles() {
        for i in 0..<tileCount {
            let tile = makeTile()
            tile.position = SCNVector3(0, 0, spawnZ + Float(i) * tileLength + 3)
            tiles.append(tile)
            decorateTile(tile, index: i, allowObstacles: false)
            rootNode.addChildNode(tile)
        }
    }

    private func makeTile() -> SCNNode {
        let tile = SCNNode()
        tile.name = "tile"

        let ground = SCNNode()
        ground.name = "ground"

        let slab = node(
            SCNBox(width: 8.2, height: 0.5, length: CGFloat(tileLength), chamferRadius: 0.02),
            blinnMaterial(UIColor(red: 0.55, green: 0.49, blue: 0.4, alpha: 1), shininess: 6)
        )
        slab.position = SCNVector3(0, -0.25, 0)
        ground.addChildNode(slab)

        let trimMat = material(UIColor(red: 0.5, green: 0.44, blue: 0.36, alpha: 1), roughness: 0.95)
        for side: Float in [-1, 1] {
            let trim = node(SCNBox(width: 0.24, height: 0.09, length: CGFloat(tileLength), chamferRadius: 0), trimMat)
            trim.position = SCNVector3(side * 3.98, 0.015, 0)
            ground.addChildNode(trim)
        }

        let sepMat = material(UIColor(red: 0.42, green: 0.37, blue: 0.3, alpha: 1), roughness: 1)
        for lx: Float in [-1.25, 1.25] {
            let sep = node(SCNBox(width: 0.06, height: 0.02, length: CGFloat(tileLength), chamferRadius: 0), sepMat)
            sep.position = SCNVector3(lx, 0.006, 0)
            ground.addChildNode(sep)
        }

        let grassMat = material(UIColor(red: 0.26, green: 0.4, blue: 0.2, alpha: 1), roughness: 1)
        for side: Float in [-1, 1] {
            let grass = node(SCNBox(width: 3.0, height: 0.35, length: CGFloat(tileLength), chamferRadius: 0), grassMat)
            grass.position = SCNVector3(side * 5.7, -0.32, 0)
            ground.addChildNode(grass)
        }

        tile.addChildNode(ground)

        let decor = SCNNode()
        decor.name = "decor"
        tile.addChildNode(decor)
        return tile
    }

    // MARK: - Tile decoration & obstacle patterns

    private func decorateTile(_ tile: SCNNode, index: Int, allowObstacles: Bool) {
        guard let decor = tile.childNode(withName: "decor", recursively: false) else { return }
        decor.childNodes.forEach { $0.removeFromParentNode() }
        torchLights.removeAll(keepingCapacity: true)

        let difficulty = min(1, distance / 500)

        // Moss patches
        let mossMat = material(UIColor(red: 0.33, green: 0.52, blue: 0.27, alpha: 1), roughness: 1)
        for _ in 0..<Int.random(in: 0...2) {
            let moss = node(
                SCNBox(width: CGFloat(Float.random(in: 0.4...1.1)), height: 0.025, length: CGFloat(Float.random(in: 0.4...1.1)), chamferRadius: 0),
                mossMat
            )
            moss.position = SCNVector3(Float.random(in: -3.4...3.4), 0.016, Float.random(in: -2.4...2.4))
            decor.addChildNode(moss)
        }

        // Rubble
        let rubMat = material(UIColor(red: 0.58, green: 0.53, blue: 0.45, alpha: 1), roughness: 1)
        for _ in 0..<Int.random(in: 0...2) {
            let s = Float.random(in: 0.1...0.3)
            let rub = node(SCNBox(width: CGFloat(s), height: CGFloat(s * 0.7), length: CGFloat(s), chamferRadius: 0.02), rubMat)
            rub.position = SCNVector3(Float.random(in: -3.6...3.6), s * 0.35, Float.random(in: -2.4...2.4))
            rub.eulerAngles.y = Float.random(in: 0...Float.pi)
            decor.addChildNode(rub)
        }

        // Side ruins / palms on alternate tiles
        if index % 2 == 0 {
            let side: Float = Bool.random() ? -1 : 1
            if Bool.random() {
                let colMat = material(UIColor(red: 0.62, green: 0.56, blue: 0.46, alpha: 1), roughness: 0.9)
                let col = node(SCNCylinder(radius: 0.32, height: 2.2), colMat)
                col.position = SCNVector3(side * 4.9, 1.1, Float.random(in: -2...2))
                col.eulerAngles.z = side * Float.random(in: 0.08...0.18)
                decor.addChildNode(col)
                let cap = node(SCNBox(width: 0.9, height: 0.18, length: 0.9, chamferRadius: 0.03), colMat)
                cap.position = SCNVector3(side * 4.9, 2.3, col.position.z)
                cap.eulerAngles.z = col.eulerAngles.z
                decor.addChildNode(cap)
            } else {
                addPalm(to: decor, x: side * 5.6, z: Float.random(in: -2...2))
            }
        }

        // Torches
        if index % 3 == 0 {
            for side: Float in [-1, 1] {
                addTorch(to: decor, x: side * 3.5, z: Float.random(in: -2...2))
            }
        }

        guard allowObstacles, index < 2 else { return }

        // Obstacle patterns
        let roll = Float.random(in: 0...1)
        if roll < 0.26 {
            // Single pillar — dodge
            let lane = Int.random(in: 0...2)
            let free = (0...2).first { $0 != lane }!
            addPillar(decor, lane: lane, z: 0)
            addCoinLine(decor, lane: free, z: 0, count: 4)
        } else if roll < 0.44 {
            // Double pillar — squeeze through the open lane
            let blocked = Set([0, 1, 2].shuffled().prefix(2))
            let free = (0...2).first { !blocked.contains($0) }!
            for l in blocked { addPillar(decor, lane: l, z: 0) }
            addCoinLine(decor, lane: free, z: 0, count: 4)
        } else if roll < 0.62 {
            // Stone block — jump
            let lane = Int.random(in: 0...2)
            addBlock(decor, lane: lane, z: 0)
            addCoinArc(decor, lane: lane, z: 0)
        } else if roll < 0.74, difficulty > 0.15 {
            // Lintel — slide under
            let lane = Int.random(in: 0...2)
            addLintel(decor, lane: lane, z: 0)
            addCoinLine(decor, lane: (lane + 1) % 3, z: 0, count: 3)
        } else if roll < 0.9 {
            // Coin trail
            let lane = Int.random(in: 0...2)
            addCoinLine(decor, lane: lane, z: 0, count: 5)
        }
        // else: clear tile
    }

    private func addPalm(to parent: SCNNode, x: Float, z: Float) {
        let trunkMat = material(UIColor(red: 0.5, green: 0.38, blue: 0.24, alpha: 1), roughness: 0.9)
        let trunk = node(SCNCylinder(radius: 0.12, height: 2.7), trunkMat)
        trunk.position = SCNVector3(x, 1.35, z)
        trunk.eulerAngles.z = x > 0 ? -0.12 : 0.12
        parent.addChildNode(trunk)
        let leafMat = material(UIColor(red: 0.24, green: 0.45, blue: 0.18, alpha: 1), roughness: 1)
        for i in 0..<6 {
            let leaf = node(SCNSphere(radius: 0.55), leafMat)
            leaf.scale = SCNVector3(1, 0.12, 0.3)
            let a = Float(i) / 6 * .pi * 2
            leaf.position = SCNVector3(x + cos(a) * 0.62, 2.75 + sin(a * 3) * 0.08, z + sin(a) * 0.62)
            leaf.eulerAngles.y = -a
            parent.addChildNode(leaf)
        }
    }

    private func addTorch(to parent: SCNNode, x: Float, z: Float) {
        let postMat = material(UIColor(red: 0.4, green: 0.34, blue: 0.26, alpha: 1), roughness: 1, metalness: 0.2)
        let post = node(SCNCylinder(radius: 0.07, height: 1.5), postMat)
        post.position = SCNVector3(x, 0.75, z)
        parent.addChildNode(post)
        let bowl = node(
            SCNCone(topRadius: 0.02, bottomRadius: 0.12, height: 0.18),
            material(UIColor(red: 0.3, green: 0.26, blue: 0.22, alpha: 1), roughness: 1, metalness: 0.4)
        )
        bowl.position = SCNVector3(x, 1.55, z)
        parent.addChildNode(bowl)
        let flame = node(
            SCNSphere(radius: 0.1),
            material(UIColor(red: 1, green: 0.7, blue: 0.25, alpha: 1), emission: UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1), emissionIntensity: 1)
        )
        flame.position = SCNVector3(x, 1.68, z)
        parent.addChildNode(flame)
        let flameCore = node(
            SCNSphere(radius: 0.045),
            material(UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), emission: UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1), emissionIntensity: 1.4)
        )
        flameCore.position = SCNVector3(x, 1.71, z)
        parent.addChildNode(flameCore)

        let ps = SCNParticleSystem()
        ps.birthRate = 45
        ps.particleLifeSpan = 0.35
        ps.particleLifeSpanVariation = 0.15
        ps.particleSize = 0.12
        ps.particleSizeVariation = 0.05
        ps.particleVelocity = 0.7
        ps.particleVelocityVariation = 0.25
        ps.spreadingAngle = 12
        ps.particleColor = UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
        ps.particleImage = GameScene.softParticleImage
        ps.isAffectedByGravity = false
        ps.blendMode = .additive
        let psNode = SCNNode()
        psNode.position = SCNVector3(x, 1.7, z)
        psNode.addParticleSystem(ps)
        parent.addChildNode(psNode)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1, green: 0.55, blue: 0.25, alpha: 1)
        light.intensity = 240
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 5.5
        light.attenuationFalloffExponent = 2
        let ln = SCNNode()
        ln.light = light
        ln.position = SCNVector3(x, 1.75, z)
        parent.addChildNode(ln)
        torchLights.append(ln)
    }

    private func addPillar(_ parent: SCNNode, lane: Int, z: Float) {
        let mat = material(UIColor(red: 0.6, green: 0.55, blue: 0.47, alpha: 1), roughness: 0.9)
        let geo = SCNCylinder(radius: 0.5, height: 3.1)
        let p = SCNNode(geometry: geo)
        geo.materials = [mat]
        p.name = "obstacle"
        p.position = SCNVector3(TempleRules.lanes[lane], 1.55, z)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: geo, options: nil))
        body.categoryBitMask = BitMask.obstacle
        body.collisionBitMask = 0
        body.contactTestBitMask = BitMask.player
        p.physicsBody = body
        parent.addChildNode(p)

        let top = node(SCNBox(width: 0.9, height: 0.25, length: 0.9, chamferRadius: 0.04), mat)
        top.position = SCNVector3(TempleRules.lanes[lane], 3.2, z)
        top.eulerAngles.z = 0.25
        parent.addChildNode(top)
        let moss = node(
            SCNBox(width: 0.95, height: 0.03, length: 0.95, chamferRadius: 0),
            material(UIColor(red: 0.32, green: 0.5, blue: 0.28, alpha: 1), roughness: 1)
        )
        moss.position = SCNVector3(TempleRules.lanes[lane], 3.28, z)
        parent.addChildNode(moss)
    }

    private func addBlock(_ parent: SCNNode, lane: Int, z: Float) {
        let mat = material(UIColor(red: 0.55, green: 0.5, blue: 0.42, alpha: 1), roughness: 1)
        let geo = SCNBox(width: 1.0, height: 0.62, length: 1.0, chamferRadius: 0.05)
        let b = SCNNode(geometry: geo)
        geo.materials = [mat]
        b.name = "obstacle"
        b.position = SCNVector3(TempleRules.lanes[lane], 0.31, z)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: geo, options: nil))
        body.categoryBitMask = BitMask.obstacle
        body.collisionBitMask = 0
        body.contactTestBitMask = BitMask.player
        b.physicsBody = body
        parent.addChildNode(b)

        let trim = node(
            SCNBox(width: 1.02, height: 0.09, length: 1.02, chamferRadius: 0.02),
            material(UIColor(red: 0.75, green: 0.62, blue: 0.3, alpha: 1), roughness: 0.4, metalness: 0.6)
        )
        trim.position = SCNVector3(TempleRules.lanes[lane], 0.6, z)
        parent.addChildNode(trim)
    }

    private func addLintel(_ parent: SCNNode, lane: Int, z: Float) {
        let x = TempleRules.lanes[lane]
        let mat = material(UIColor(red: 0.62, green: 0.56, blue: 0.47, alpha: 1), roughness: 0.9)
        let beamGeo = SCNBox(width: 1.5, height: 0.5, length: 0.45, chamferRadius: 0.03)
        let beam = SCNNode(geometry: beamGeo)
        beamGeo.materials = [mat]
        beam.name = "obstacle"
        beam.position = SCNVector3(x, 1.45, z)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: beamGeo, options: nil))
        body.categoryBitMask = BitMask.obstacle
        body.collisionBitMask = 0
        body.contactTestBitMask = BitMask.player
        beam.physicsBody = body
        parent.addChildNode(beam)

        let postMat = material(UIColor(red: 0.58, green: 0.52, blue: 0.44, alpha: 1), roughness: 0.95)
        for s: Float in [-1, 1] {
            let post = node(SCNBox(width: 0.16, height: 1.35, length: 0.16, chamferRadius: 0.02), postMat)
            post.position = SCNVector3(x + s * 0.66, 0.68, z)
            parent.addChildNode(post)
        }
        let band = node(
            SCNBox(width: 1.52, height: 0.1, length: 0.47, chamferRadius: 0.02),
            material(UIColor(red: 0.78, green: 0.64, blue: 0.32, alpha: 1), roughness: 0.4, metalness: 0.5)
        )
        band.position = SCNVector3(x, 1.62, z)
        parent.addChildNode(band)
    }

    private func makeCoin() -> SCNNode {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1)
        mat.metalness.contents = 0.9
        mat.roughness.contents = 0.15
        mat.emission.contents = UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1)
        mat.emission.intensity = 0.5

        let geo = SCNCylinder(radius: 0.24, height: 0.07)
        let coin = SCNNode(geometry: geo)
        geo.materials = [mat]
        coin.name = "coin"
        coin.eulerAngles.x = .pi / 2

        // Slightly larger contact shape than the visual disc so coins are
        // caught reliably even at top speed.
        let shapeGeo = SCNCylinder(radius: 0.32, height: 0.14)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: shapeGeo, options: nil))
        body.categoryBitMask = BitMask.coin
        body.collisionBitMask = 0
        body.contactTestBitMask = BitMask.player
        coin.physicsBody = body

        let spin = SCNAction.repeatForever(SCNAction.rotate(by: .pi * 2, around: SCNVector3(0, 1, 0), duration: 1.4))
        coin.runAction(spin)
        return coin
    }

    private func addCoinLine(_ parent: SCNNode, lane: Int, z: Float, count: Int, y: Float = 0.85) {
        let x = TempleRules.lanes[lane]
        for i in 0..<count {
            let coin = makeCoin()
            coin.position = SCNVector3(x, y, z + 2.6 - Float(i) * 1.15)
            parent.addChildNode(coin)
        }
    }

    private func addCoinArc(_ parent: SCNNode, lane: Int, z: Float) {
        let x = TempleRules.lanes[lane]
        for i in 0..<7 {
            let t = Float(i) / 6
            let coin = makeCoin()
            coin.position = SCNVector3(x, 0.85 + sin(t * .pi) * 1.15, z + 2.8 - t * 5.6)
            parent.addChildNode(coin)
        }
    }

    // MARK: - Gestures

    func setupGestures(on view: SCNView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard phase == .running, !dead else { return }
        switch g.state {
        case .began:
            panStart = g.location(in: g.view)
        case .ended, .cancelled:
            let p = g.location(in: g.view)
            let dx = p.x - panStart.x
            let dy = p.y - panStart.y
            let threshold: CGFloat = 32
            if abs(dx) > abs(dy), abs(dx) > threshold {
                setLane(currentLane + (dx > 0 ? 1 : -1))
            } else if abs(dy) > threshold {
                if dy < 0 {
                    jump()
                } else {
                    if grounded { startSlide() } else { fastFall() }
                }
            }
        default:
            break
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard phase == .running, !dead else { return }
        jump()
    }

    // MARK: - Player actions

    private func setLane(_ lane: Int) {
        currentLane = TempleRules.clampedLane(lane)
    }

    private func jump() {
        guard grounded, !dead else { return }
        if sliding { endSlide() }
        grounded = false
        viewModel?.debugJumpCount += 1
        jumpMotion = TempleRules.JumpMotion(y: 0, vy: TempleRules.jumpImpulse, grounded: false)
        let stretch = SCNAction.customAction(duration: 0.1) { node, elapsed in
            let t = elapsed / 0.1
            node.scale = SCNVector3(1 + 0.05 * t, 1 + 0.12 * t, 1 + 0.05 * t)
        }
        let relax = SCNAction.customAction(duration: 0.22) { node, elapsed in
            let t = 1 - elapsed / 0.22
            node.scale = SCNVector3(1 + 0.05 * t, 1 + 0.12 * t, 1 + 0.05 * t)
        }
        bodyRoot.runAction(SCNAction.sequence([stretch, relax]))
    }

    private func fastFall() {
        jumpMotion.vy = -14
    }

    private func startSlide() {
        guard grounded, !sliding else { return }
        sliding = true
        slideTimer = 0.85
        playerBody.physicsShape = slideShape
        let crouch = SCNAction.customAction(duration: 0.08) { node, elapsed in
            let t = elapsed / 0.08
            node.scale = SCNVector3(1, 1 - 0.45 * t, 1)
        }
        bodyRoot.runAction(crouch)
    }

    private func endSlide() {
        guard sliding else { return }
        sliding = false
        playerBody.physicsShape = standShape
        let stand = SCNAction.customAction(duration: 0.12) { node, elapsed in
            let t = elapsed / 0.12
            node.scale = SCNVector3(1, 0.55 + 0.45 * t, 1)
        }
        bodyRoot.runAction(stand)
    }

    // MARK: - Run control

    func beginRun() {
        dead = false
        distance = 0
        viewModel?.debugJumpCount = 0
        speed = 7.2
        runTime = 0
        phase = .running
        currentLane = 1
        grounded = true
        jumpMotion = TempleRules.JumpMotion()
        playerBody.isAffectedByGravity = false
        if sliding { endSlide() }
        playerNode.position = SCNVector3(0, 0, 0)
        playerBody.velocity = SCNVector3Zero
        playerBody.angularVelocity = SCNVector4Zero
        playerBody.contactTestBitMask = BitMask.obstacle | BitMask.coin | BitMask.boulder
        physicsWorld.speed = 1
        boulderNode.position = SCNVector3(0, 0.9, TempleRules.boulderChaseZ)
        cameraNode.position = SCNVector3(0, 2.9, 5.4)
        cameraNode.camera?.fieldOfView = 62

        for (i, tile) in tiles.enumerated() {
            tile.position = SCNVector3(0, 0, spawnZ + Float(i) * tileLength + 3)
            decorateTile(tile, index: i, allowObstacles: i < 2)
        }

        // -debugcoins: put a coin line straight ahead so pickup is easy to test.
        if ProcessInfo.processInfo.arguments.contains("-debugcoins") {
            if let tile = tiles.first(where: { abs($0.position.z + 5) < 1.5 }) {
                for i in 0..<6 {
                    let coin = makeCoin()
                    coin.position = SCNVector3(0, 0.85, -1 - Float(i) * 1.2)
                    tile.addChildNode(coin)
                }
            }
        }
    }

    // MARK: - Per-frame updates

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let view = scnView, view.isPlaying else { return }
        if lastTime == nil { lastTime = time; return }
        var dt = Float(time - lastTime!)
        lastTime = time
        dt = min(dt, 1 / 30)

        // SceneKit fires this on its render thread, but the game touches
        // SwiftUI state here — so bounce the tick onto the main thread.
        guard !frameQueued else { return }
        frameQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameQueued = false
            switch self.phase {
            case .menu:
                self.updateMenu(dt, time)
            case .running:
                if self.dead {
                    self.updateDeath(dt, time)
                } else {
                    self.updateRunning(dt, time)
                }
            case .gameOver:
                self.updateGameOver(dt, time)
            }
        }
    }

    private func updateMenu(_ dt: Float, _ t: TimeInterval) {
        let tf = Float(t)
        moveWorld(dt * 3)
        boulderNode.eulerAngles.x -= dt * 1.2
        cameraNode.position.x = sin(tf * 0.5) * 0.5
        cameraNode.position.y = 2.9 + sin(tf * 0.37) * 0.12
        updatePlayer(dt, t)
        updateTorchLights()
    }

    private func updateRunning(_ dt: Float, _ t: TimeInterval) {
        speed = TempleRules.speed(forDistance: distance)
        distance += speed * dt
        viewModel?.updateScore(distance)

        moveWorld(dt * speed)

        // The boulder waits behind the camera, out of frame, until a crash.
        boulderNode.position.z = TempleRules.boulderChaseZ
        boulderNode.eulerAngles.x -= dt * speed / 0.9
        viewModel?.debugBoulderZ = boulderNode.position.z
        viewModel?.debugCameraZ = cameraNode.position.z

        updatePlayer(dt, t)

        if sliding {
            slideTimer -= dt
            if slideTimer <= 0 { endSlide() }
        }

        cameraNode.camera?.fieldOfView = 62 + CGFloat(min(8, speed * 0.5))
        updateTorchLights()
    }

    private func updatePlayer(_ dt: Float, _ t: TimeInterval) {
        // Lane lerp + lean
        let tx = TempleRules.lanes[currentLane]
        let dx = tx - playerNode.position.x
        playerNode.position.x += dx * min(1, dt * 16)
        bodyRoot.eulerAngles.z = max(-0.3, min(0.3, -dx * 1.4))

        // Locks: stay on the track
        playerNode.position.z = 0
        playerBody.velocity.z = 0
        playerBody.angularVelocity = SCNVector4(0, 0, 0, 0)

        // Jump integration (manual — see TempleRules.advanceJump). The physics
        // body's y-velocity is kept in sync so the death tumble stays coherent.
        if grounded {
            playerNode.position.y = 0
            jumpMotion = TempleRules.JumpMotion()
        } else {
            jumpMotion = TempleRules.advanceJump(jumpMotion, dt: dt)
            grounded = jumpMotion.grounded
            playerNode.position.y = jumpMotion.y
            playerBody.velocity.y = jumpMotion.vy
        }

        // Run cycle
        runTime += dt * (speed * 1.15)
        if speed > 0.5 {
            let sw = sin(runTime * 6.2)
            leftLeg.eulerAngles.x = sw * 0.8
            rightLeg.eulerAngles.x = -sw * 0.8
            leftArm.eulerAngles.x = -sw * 0.6
            rightArm.eulerAngles.x = sw * 0.6
            bodyRoot.position.y = abs(sw) * 0.05
        } else {
            let t2 = Float(t)
            leftArm.eulerAngles.x = sin(t2 * 1.8) * 0.06
            rightArm.eulerAngles.x = -sin(t2 * 1.8) * 0.06
            leftLeg.eulerAngles.x = 0
            rightLeg.eulerAngles.x = 0
            bodyRoot.position.y = sin(t2 * 1.4) * 0.02
        }
        scarf.eulerAngles.z = sin(runTime * 3.6) * 0.2
        scarf.eulerAngles.y = sin(runTime * 3.6 + 1) * 0.14

        // Lantern flicker
        lanternLight?.intensity = 130 + CGFloat(sin(runTime * 30) * 25)

        // Telemetry for the automated tests.
        viewModel?.debugPlayerY = playerNode.position.y
    }

    private func updateDeath(_ dt: Float, _ t: TimeInterval) {
        // The boulder rolls forward from behind the camera, through the frame,
        // over the tumbling runner and past them — running them over.
        let targetZ = TempleRules.boulderSmashZ
        boulderNode.position.z += (targetZ - boulderNode.position.z) * min(1, dt * 3.2)
        boulderNode.eulerAngles.x -= dt * 14
        scarf.eulerAngles.z = sin(runTime * 4) * 0.25
        runTime += dt
    }

    private func updateGameOver(_ dt: Float, _ t: TimeInterval) {
        if playerNode.position.y < 0 { playerNode.position.y = 0 }
        playerNode.position.z = 0
        if playerNode.position.y == 0, playerBody.velocity.y < 0 { playerBody.velocity.y = 0 }
        scarf.eulerAngles.z = sin(runTime * 3) * 0.2
        runTime += dt
        updateTorchLights()
    }

    private func moveWorld(_ dz: Float) {
        for (i, tile) in tiles.enumerated() {
            tile.position.z += dz
            if tile.position.z - tileLength / 2 > 12 {
                tile.position.z -= Float(tileCount) * tileLength
                decorateTile(tile, index: i, allowObstacles: phase == .running)
            }
        }
    }

    private func updateTorchLights() {
        guard !torchLights.isEmpty else { return }
        let sorted = torchLights.sorted { $0.position.z > $1.position.z }
        for (idx, ln) in sorted.enumerated() {
            if idx < 2 {
                ln.light?.intensity = 240 + CGFloat(sin(runTime * 25 + Float(idx) * 3) * 50)
            } else {
                ln.light?.intensity = 0
            }
        }
    }

    // MARK: - Death

    private func die() {
        guard !dead else { return }
        dead = true
        speed = 0
        physicsWorld.speed = 0.45
        playerBody.isAffectedByGravity = true
        playerBody.contactTestBitMask = 0
        playerBody.applyForce(SCNVector3(0, 6.2, -4), asImpulse: true)
        playerBody.applyTorque(SCNVector4(0.8, 0.2, 0.4, 7), asImpulse: true)

        // Swing the camera to a low side view IN FRONT of the runner, looking
        // back — so the boulder is seen approaching, rolling over the runner
        // and past the camera (classic crash shot).
        cameraNode.removeAction(forKey: "shake")
        lookTarget.position = SCNVector3(0, 0.7, 0)
        cameraNode.runAction(SCNAction.move(to: SCNVector3(-2.2, 1.5, -2.5), duration: 0.35))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.phase = .gameOver
            self.physicsWorld.speed = 1
            self.viewModel?.playerDied()
            // Restore the chase camera for the next run.
            self.lookTarget.position = SCNVector3(0, 1.15, -10)
            self.cameraNode.position = SCNVector3(0, 2.9, 5.4)
        }
    }

    private func cameraShake() {
        cameraNode.removeAction(forKey: "shake")
        var actions: [SCNAction] = []
        for i in 0..<14 {
            let r: Float = 0.16 * (1 - Float(i) / 14)
            let dx = Float.random(in: -r...r)
            let dy = Float.random(in: -r...r)
            actions.append(SCNAction.move(to: SCNVector3(dx, 2.9 + dy, 5.4), duration: 0.045))
        }
        actions.append(SCNAction.move(to: SCNVector3(0, 2.9, 5.4), duration: 0.25))
        cameraNode.runAction(SCNAction.sequence(actions), forKey: "shake")
    }

    private func collectCoin(_ coin: SCNNode) {
        viewModel?.addGem()

        let burst = SCNParticleSystem()
        burst.birthRate = 160
        burst.particleLifeSpan = 0.5
        burst.particleLifeSpanVariation = 0.2
        burst.particleSize = 0.07
        burst.particleSizeVariation = 0.03
        burst.particleVelocity = 2.2
        burst.particleVelocityVariation = 1.0
        burst.emitterShape = SCNSphere(radius: 0.12)
        burst.particleColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        burst.particleImage = GameScene.softParticleImage
        burst.isAffectedByGravity = true
        burst.blendMode = .additive
        burst.emissionDuration = 0.08
        burst.loops = false

        let n = SCNNode()
        n.position = coin.presentation.worldPosition
        n.addParticleSystem(burst)
        rootNode.addChildNode(n)
        n.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 1.2),
            SCNAction.removeFromParentNode(),
        ]))
        coin.removeFromParentNode()
    }

    // MARK: - Contacts

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let a = contact.nodeA
        let b = contact.nodeB
        guard a.name == "player" || b.name == "player" else { return }
        let player = a.name == "player" ? a : b
        let other = player === a ? b : a

        // Contacts arrive on SceneKit's physics thread; all game logic (and
        // the SwiftUI state it touches) must run on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch other.name {
            case "coin":
                guard self.phase == .running, !self.dead else { return }
                self.collectCoin(other)
            case "obstacle", "boulder":
                guard self.phase == .running, !self.dead else { return }
                self.die()
            default:
                break
            }
        }
    }
}
