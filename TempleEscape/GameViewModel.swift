import SwiftUI
import SceneKit

enum GamePhase {
    case menu
    case running
    case gameOver
}

/// UI-facing state for the game. The SceneKit scene pushes updates into this
/// object; SwiftUI views observe it for the HUD. All updates happen on the
/// main thread (SceneKit renderer + UIKit gestures), so no actor isolation is needed.
final class GameViewModel: ObservableObject {
    @Published var phase: GamePhase = .menu
    @Published var score: Int = 0
    @Published var gems: Int = 0
    @Published var bestScore: Int = UserDefaults.standard.integer(forKey: "templeEscape.best")
    @Published var isNewBest: Bool = false
    // Telemetry for the automated tests (kept invisible in the HUD).
    @Published var debugPlayerY: Float = 0
    @Published var debugJumpCount: Int = 0
    @Published var debugBoulderZ: Float = 0
    @Published var debugCameraZ: Float = 0

    weak var scene: GameScene?

    func attach(_ scene: GameScene) {
        self.scene = scene
    }

    func start() {
        score = 0
        gems = 0
        isNewBest = false
        phase = .running
        scene?.beginRun()
    }

    func updateScore(_ meters: Float) {
        let s = Int(meters)
        guard s != score else { return }
        score = s
        if s > bestScore {
            bestScore = s
            isNewBest = true
        }
    }

    func addGem() {
        gems += 1
    }

    func playerDied() {
        phase = .gameOver
        UserDefaults.standard.set(bestScore, forKey: "templeEscape.best")
    }
}
