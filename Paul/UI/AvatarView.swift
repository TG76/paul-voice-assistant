import SwiftUI

struct AvatarView: View {
    let state: PaulState
    let audioLevel: Float

    @State private var blinkPhase = false
    @State private var eyeOpenness: CGFloat = 0
    @State private var mouthOpen: CGFloat = 0
    @State private var mouthSmile: CGFloat = 0
    @State private var eyeOffsetX: CGFloat = 0
    @State private var eyeOffsetY: CGFloat = 0
    @State private var thinkingWobble: CGFloat = 0

    var body: some View {
        VStack(spacing: 120) {
            // Augen
            HStack(spacing: 180) {
                EyeShape(openness: blinkPhase ? 0 : eyeOpenness, offsetX: eyeOffsetX, offsetY: eyeOffsetY)
                EyeShape(openness: blinkPhase ? 0 : eyeOpenness, offsetX: eyeOffsetX, offsetY: eyeOffsetY)
            }

            // Mund
            SmileMouth(state: state, openAmount: mouthOpen, smile: mouthSmile)
        }
        .offset(x: state == .thinking ? thinkingWobble : 0)
        .onChange(of: state) { _, newState in
            withAnimation(.easeInOut(duration: 0.5)) {
                applyState(newState)
            }
        }
        .onChange(of: audioLevel) { _, level in
            if state == .speaking {
                withAnimation(.easeOut(duration: 0.05)) {
                    mouthOpen = CGFloat(min(1.0, level * 5 + 0.15))
                }
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.1)) { blinkPhase = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeInOut(duration: 0.1)) { blinkPhase = false }
                }
            }
            // Initialen State setzen (wichtig wenn View erst nach State-Wechsel erscheint)
            withAnimation(.easeInOut(duration: 0.3)) {
                applyState(state)
            }
        }
    }

    private func applyState(_ s: PaulState) {
        switch s {
        case .waking:
            eyeOpenness = 0.3
            mouthOpen = 0
            mouthSmile = 0.3
            eyeOffsetX = 0
            eyeOffsetY = 0
        case .listening:
            eyeOpenness = 1.0
            mouthOpen = 0.15
            mouthSmile = 0.6
            eyeOffsetX = 0
            eyeOffsetY = 0
        case .thinking:
            eyeOpenness = 0.6
            eyeOffsetX = -30
            eyeOffsetY = -20
            mouthOpen = 0
            mouthSmile = 0.15
            startThinkingAnimation()
        case .speaking:
            eyeOpenness = 0.9
            eyeOffsetX = 0
            eyeOffsetY = 0
            mouthSmile = 0.5
            thinkingWobble = 0
        default:
            eyeOpenness = 0
            mouthOpen = 0
            mouthSmile = 0
            thinkingWobble = 0
        }
    }

    private func startThinkingAnimation() {
        // Augen wandern hin und her
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            eyeOffsetX = 30
        }
        // Leichtes Wippen
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            thinkingWobble = 8
        }
    }
}

// MARK: - Auge

struct EyeShape: View {
    let openness: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 90, height: 90)
            .scaleEffect(y: max(0.04, openness))
            .offset(x: offsetX, y: offsetY)
    }
}

// MARK: - Mund

struct SmileMouth: View {
    let state: PaulState
    let openAmount: CGFloat
    let smile: CGFloat

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = size.height / 2
            let width: CGFloat = 360
            let curveDown = smile * 120

            var path = Path()
            path.move(to: CGPoint(x: midX - width / 2, y: midY - curveDown * 0.3))
            path.addQuadCurve(
                to: CGPoint(x: midX + width / 2, y: midY - curveDown * 0.3),
                control: CGPoint(x: midX, y: midY + curveDown)
            )

            if openAmount > 0.05 {
                let openHeight = openAmount * 160
                path.addQuadCurve(
                    to: CGPoint(x: midX - width / 2, y: midY - curveDown * 0.3),
                    control: CGPoint(x: midX, y: midY + curveDown + openHeight)
                )
                context.fill(path, with: .color(.white))
            } else {
                context.stroke(path, with: .color(.white), lineWidth: 14)
            }
        }
        .frame(width: 500, height: 260)
    }
}
