import Foundation

/// Gameplay tuning and rules for the runner — kept separate from the scene
/// code so they're easy to read and tweak.
enum TempleRules {

    /// Base speed of the world, ramping with distance (m/s). Capped at 15.5.
    static func speed(forDistance d: Float) -> Float {
        min(7.2 + d * 0.032, 15.5)
    }

    /// Where the boulder waits during play: **behind the chase camera**
    /// (camera sits at z ≈ 5.4), so it stays out of frame until the moment
    /// you crash. On death it rolls forward over the runner (see
    /// `boulderSmashZ`).
    static let boulderChaseZ: Float = 9.0

    /// Where the boulder ends up after running the player over (well in front
    /// of the runner, past the camera).
    static let boulderSmashZ: Float = -3.0

    /// The boulder's rolling radius (used for its spin rate).
    static let boulderRadius: Float = 0.9

    /// Score in meters (integer part of the distance).
    static func score(forDistance d: Float) -> Int {
        Int(d)
    }

    /// Jump impulse (N·s) — chosen so the apex is ~1.7 m under Earth gravity.
    static let jumpImpulse: Float = 5.9

    /// Decide whether the player should snap back to the ground.
    /// The velocity check is what makes jumping robust: right after a jump the
    /// body still sits at y = 0 for a frame, but its upward velocity must not
    /// be treated as "landing".
    static func shouldLand(playerY: Float, velocityY: Float) -> Bool {
        playerY <= 0.02 && velocityY <= 0.1
    }

    // MARK: Jump motion

    /// Kinematic jump state. The runner's vertical motion is integrated
    /// manually (not via the physics engine) so it is deterministic and
    /// independent of SceneKit's physics-thread timing.
    struct JumpMotion: Equatable {
        var y: Float = 0
        var vy: Float = 0
        var grounded: Bool = true
    }

    /// Advance the jump for one frame under gravity.
    static func advanceJump(_ m: JumpMotion, dt: Float) -> JumpMotion {
        guard !m.grounded else { return m }
        var y = m.y + m.vy * dt
        var vy = m.vy + gravity * dt
        if y <= 0 {
            y = 0
            vy = 0
            return JumpMotion(y: 0, vy: 0, grounded: true)
        }
        return JumpMotion(y: y, vy: vy, grounded: false)
    }

    /// Physics gravity used by the scene (m/s²).
    static let gravity: Float = -9.8

    /// Lane positions (x), center-out: left / middle / right.
    static let lanes: [Float] = [-1.25, 0, 1.25]

    /// Clamp a lane index into the valid range.
    static func clampedLane(_ lane: Int) -> Int {
        min(2, max(0, lane))
    }
}
