import SwiftUI

struct HUDView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .menu:
                MenuOverlay(viewModel: viewModel)
            case .running:
                RunningHUD(viewModel: viewModel)
            case .gameOver:
                GameOverOverlay(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.phase)
    }
}

// MARK: - In-game HUD

private struct RunningHUD: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                pill {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.yellow)
                    Text("\(viewModel.gems)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("hudGems")
                }
                Spacer()
                pill {
                    Image(systemName: "mountain.2.fill")
                        .foregroundStyle(.orange)
                    Text("\(viewModel.score) m")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("hudScore")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Test telemetry (invisible, tiny — see GameViewModel).
            Text(String(format: "%.2f", viewModel.debugPlayerY))
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("debugPlayerY")
                .frame(width: 1, height: 1)
            Text("\(viewModel.debugJumpCount)")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("debugJumpCount")
                .frame(width: 1, height: 1)
            Text("B\(String(format: "%.1f", viewModel.debugBoulderZ)) C\(String(format: "%.1f", viewModel.debugCameraZ))")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("debugPositions")
                .frame(width: 1, height: 1)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Menu

private struct MenuOverlay: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                Spacer()

                VStack(spacing: 10) {
                    Text("TEMPLE ESCAPE")
                        .font(.system(size: 44, weight: .heavy, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.8), radius: 4, y: 3)

                    Text("Outrun the boulder.\nFind the golden treasure.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.9), radius: 3, y: 2)

                    if viewModel.bestScore > 0 {
                        Text("BEST  \(viewModel.bestScore) m")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.9), radius: 3, y: 2)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

                Button {
                    viewModel.start()
                } label: {
                    Text("START RUN")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 46)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .shadow(color: .orange.opacity(0.5), radius: 10, y: 4)
                }
                .buttonStyle(.plain)

                Text("swipe ⇄ lanes · swipe ▲ jump · swipe ▼ slide\nor just tap to jump")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                Spacer()

                Text("made with Swift · SceneKit · questionable decisions")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Game over

private struct GameOverOverlay: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.6), radius: 8)

                Text("CRUSHED!")
                    .font(.system(size: 38, weight: .heavy, design: .serif))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                    )

                Text("The boulder finally caught you.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                HStack(spacing: 26) {
                    stat("DISTANCE", "\(viewModel.score) m")
                    stat("GEMS", "\(viewModel.gems)")
                    stat("BEST", "\(viewModel.bestScore) m")
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                if viewModel.isNewBest {
                    Text("🏆 NEW BEST!")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.yellow)
                }

                Button {
                    viewModel.start()
                } label: {
                    Text("RUN AGAIN")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 42)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .shadow(color: .orange.opacity(0.5), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
