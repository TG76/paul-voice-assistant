import SwiftUI

// MARK: - Chibi Paul Avatar (Tech Style)

struct ChibiAvatarView: View {
    let state: PaulState
    let audioLevel: Float

    // Animation States
    @State private var blinkPhase = false
    @State private var eyeOpenness: CGFloat = 1.0
    @State private var pupilOffsetX: CGFloat = 0
    @State private var pupilOffsetY: CGFloat = 0
    @State private var mouthOpenness: CGFloat = 0
    @State private var mouthSmile: CGFloat = 0.5
    @State private var headTilt: CGFloat = 0
    @State private var headBob: CGFloat = 0
    @State private var glowPulse: CGFloat = 0.5
    @State private var techGlow: CGFloat = 0.8
    @State private var hairWave: CGFloat = 0

    // Farben - Tech Style
    let hairColor = Color(red: 0.15, green: 0.2, blue: 0.35)
    let hairHighlight = Color(red: 0.3, green: 0.4, blue: 0.6)
    let hairDark = Color(red: 0.08, green: 0.1, blue: 0.2)
    let skinColor = Color(red: 0.98, green: 0.91, blue: 0.86)
    let skinShadow = Color(red: 0.9, green: 0.8, blue: 0.75)
    let skinHighlight = Color(red: 1.0, green: 0.95, blue: 0.92)
    let eyeColor = Color(red: 0.2, green: 0.5, blue: 0.95)
    let eyeHighlight = Color(red: 0.4, green: 0.7, blue: 1.0)
    let techBlue = Color(red: 0.3, green: 0.8, blue: 1.0)
    let techBlueBright = Color(red: 0.5, green: 0.9, blue: 1.0)
    let armorLight = Color(red: 0.9, green: 0.92, blue: 0.95)
    let armorDark = Color(red: 0.25, green: 0.3, blue: 0.4)
    let mouthColor = Color(red: 0.85, green: 0.4, blue: 0.4)
    let teethColor = Color(red: 1.0, green: 0.98, blue: 0.95)

    var body: some View {
        ZStack {
            // Hintergrund-Glow
            backgroundGlow

            // Hauptcharakter
            VStack(spacing: 0) {
                chibiCharacter
                    .rotationEffect(.degrees(Double(headTilt)))
                    .offset(y: headBob)
            }
        }
        .onAppear {
            setupAnimations()
            applyState(state)
        }
        .onChange(of: state) { _, newState in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                applyState(newState)
            }
        }
        .onChange(of: audioLevel) { _, level in
            if state == .speaking {
                withAnimation(.easeOut(duration: 0.05)) {
                    mouthOpenness = CGFloat(min(1.0, level * 4 + 0.15))
                }
            }
        }
    }

    // MARK: - Background Glow

    var backgroundGlow: some View {
        ZStack {
            // Outer tech glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            techBlue.opacity(glowPulse * 0.25),
                            techBlue.opacity(0)
                        ],
                        center: .center,
                        startRadius: 100,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)

            // Inner glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(glowPulse * 0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 500)
        }
    }

    // MARK: - Chibi Character

    var chibiCharacter: some View {
        ZStack {
            // Schultern/Anzug
            shoulders

            // Hals
            neck

            // Haare hinten
            hairBack

            // Kopf/Gesicht
            face

            // Haare vorne
            hairFront

            // Gesichtsdetails
            faceDetails
        }
        .frame(width: 450, height: 550)
    }

    // MARK: - Shoulders / Armor

    var shoulders: some View {
        ZStack {
            // Schulter-Basis
            ShoulderShape()
                .fill(
                    LinearGradient(
                        colors: [armorLight, armorDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 320, height: 120)
                .offset(y: 200)

            // Schulter-Highlights
            ShoulderShape()
                .fill(
                    LinearGradient(
                        colors: [armorLight.opacity(0.8), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 310, height: 100)
                .offset(y: 200)

            // Blaue Linien auf Schultern
            HStack(spacing: 180) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(techBlue.opacity(techGlow))
                    .frame(width: 6, height: 40)
                    .shadow(color: techBlue, radius: 8)

                RoundedRectangle(cornerRadius: 3)
                    .fill(techBlue.opacity(techGlow))
                    .frame(width: 6, height: 40)
                    .shadow(color: techBlue, radius: 8)
            }
            .offset(y: 195)

            // Kragen
            CollarShape()
                .fill(
                    LinearGradient(
                        colors: [armorDark, hairDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 140, height: 60)
                .offset(y: 160)
        }
    }

    // MARK: - Neck

    var neck: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [skinColor, skinShadow],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 80, height: 50)
            .offset(y: 135)
    }

    // MARK: - Hair Back

    var hairBack: some View {
        ZStack {
            // Haupt-Haarmasse hinten
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [hairDark, hairColor],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 300, height: 320)
                .offset(y: -30)

            // Haarsträhnen hinten
            ForEach(0..<7, id: \.self) { i in
                BackHairSpike(index: i, waveOffset: hairWave)
                    .fill(
                        LinearGradient(
                            colors: [hairDark, hairColor],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 35, height: 80 + CGFloat(i % 3) * 20)
                    .offset(
                        x: CGFloat(i - 3) * 35,
                        y: 90 + CGFloat(abs(i - 3)) * 10
                    )
            }
        }
    }

    // MARK: - Face

    var face: some View {
        ZStack {
            // Gesichts-Grundform (herzförmig/markant)
            FaceShape()
                .fill(
                    LinearGradient(
                        colors: [skinHighlight, skinColor, skinShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 220, height: 260)

            // Gesichtsschatten links
            FaceShape()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, skinShadow.opacity(0.3)],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .frame(width: 220, height: 260)

            // Wangen-Highlight
            Ellipse()
                .fill(skinHighlight.opacity(0.5))
                .frame(width: 60, height: 40)
                .offset(x: -50, y: 20)
                .blur(radius: 15)

            Ellipse()
                .fill(skinHighlight.opacity(0.5))
                .frame(width: 60, height: 40)
                .offset(x: 50, y: 20)
                .blur(radius: 15)
        }
    }

    // MARK: - Hair Front

    var hairFront: some View {
        ZStack {
            // Pony - dynamische Strähnen
            ForEach(0..<9, id: \.self) { i in
                FrontHairSpike(index: i, waveOffset: hairWave)
                    .fill(
                        LinearGradient(
                            colors: [hairHighlight, hairColor, hairDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 28 + CGFloat(i % 2) * 8, height: 70 + CGFloat(i % 3) * 25)
                    .offset(
                        x: CGFloat(i - 4) * 28,
                        y: -100 - CGFloat(abs(i - 4)) * 8
                    )
            }

            // Obere Haarspitzen
            ForEach(0..<5, id: \.self) { i in
                TopHairSpike(index: i, waveOffset: hairWave)
                    .fill(
                        LinearGradient(
                            colors: [hairHighlight, hairColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 30, height: 50 + CGFloat(i % 2) * 30)
                    .offset(
                        x: CGFloat(i - 2) * 40,
                        y: -175 - CGFloat(i % 2) * 15
                    )
                    .rotationEffect(.degrees(Double(i - 2) * 12))
            }

            // Haar-Highlights (Glanz)
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(hairHighlight.opacity(0.6))
                    .frame(width: 8, height: 30)
                    .offset(
                        x: CGFloat(i - 1) * 50 - 20,
                        y: -130 + CGFloat(i) * 10
                    )
                    .rotationEffect(.degrees(Double(i - 1) * 15 - 10))
                    .blur(radius: 2)
            }
        }
    }

    // MARK: - Face Details

    var faceDetails: some View {
        ZStack {
            // Augenbrauen
            eyebrows

            // Augen
            eyes

            // Nase
            nose

            // Mund
            mouth
        }
    }

    // MARK: - Eyebrows

    var eyebrows: some View {
        HStack(spacing: 70) {
            // Linke Augenbraue
            EyebrowShape(raised: state == .listening, worried: state == .thinking)
                .fill(hairDark)
                .frame(width: 45, height: 8)
                .rotationEffect(.degrees(state == .thinking ? 8 : -5))

            // Rechte Augenbraue
            EyebrowShape(raised: state == .listening, worried: state == .thinking)
                .fill(hairDark)
                .frame(width: 45, height: 8)
                .rotationEffect(.degrees(state == .thinking ? -8 : 5))
                .scaleEffect(x: -1)
        }
        .offset(y: -50)
    }

    // MARK: - Eyes

    var eyes: some View {
        HStack(spacing: 60) {
            TechEye(
                openness: blinkPhase ? 0.05 : eyeOpenness,
                pupilOffsetX: pupilOffsetX,
                pupilOffsetY: pupilOffsetY,
                eyeColor: eyeColor,
                highlightColor: eyeHighlight,
                isLeft: true
            )

            TechEye(
                openness: blinkPhase ? 0.05 : eyeOpenness,
                pupilOffsetX: pupilOffsetX,
                pupilOffsetY: pupilOffsetY,
                eyeColor: eyeColor,
                highlightColor: eyeHighlight,
                isLeft: false
            )
        }
        .offset(y: -15)
    }

    // MARK: - Nose

    var nose: some View {
        // Kleine dezente Nase
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: 8, y: 15),
                control: CGPoint(x: 10, y: 8)
            )
        }
        .stroke(skinShadow, lineWidth: 2)
        .frame(width: 10, height: 15)
        .offset(y: 25)
    }

    // MARK: - Mouth

    var mouth: some View {
        TechMouth(
            openness: mouthOpenness,
            smile: mouthSmile,
            lipColor: mouthColor,
            teethColor: teethColor
        )
        .offset(y: 60)
    }

    // MARK: - Animations

    private func setupAnimations() {
        // Blinzeln
        Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.08)) { blinkPhase = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.08)) { blinkPhase = false }
            }
        }

        // Haar-Wellen (subtil)
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            hairWave = 1.0
        }

        // Glow-Puls
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowPulse = 0.8
        }

        // Tech-Glow
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            techGlow = 1.0
        }
    }

    private func applyState(_ s: PaulState) {
        switch s {
        case .sleep:
            eyeOpenness = 0.05
            mouthOpenness = 0
            mouthSmile = 0.3
            pupilOffsetX = 0
            pupilOffsetY = 0
            headTilt = 5

        case .waking:
            eyeOpenness = 0.5
            mouthOpenness = 0.1
            mouthSmile = 0.5
            pupilOffsetX = 0
            pupilOffsetY = 0
            headTilt = 0

        case .listening:
            eyeOpenness = 1.0
            mouthOpenness = 0.05
            mouthSmile = 0.6
            pupilOffsetX = 0
            pupilOffsetY = 0
            headTilt = -2
            startHeadBob()

        case .thinking:
            eyeOpenness = 0.8
            mouthOpenness = 0
            mouthSmile = 0.3
            startThinkingAnimation()

        case .speaking:
            eyeOpenness = 0.95
            mouthSmile = 0.7
            pupilOffsetX = 0
            pupilOffsetY = 0
            headTilt = 0
            stopHeadAnimations()

        case .idle:
            eyeOpenness = 0.9
            mouthOpenness = 0
            mouthSmile = 0.5
            pupilOffsetX = 0
            pupilOffsetY = 0
            headTilt = 0
        }
    }

    private func startThinkingAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pupilOffsetX = 12
            pupilOffsetY = -6
        }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            headTilt = 6
        }
    }

    private func startHeadBob() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            headBob = -5
        }
    }

    private func stopHeadAnimations() {
        headTilt = 0
        headBob = 0
        pupilOffsetX = 0
        pupilOffsetY = 0
    }
}

// MARK: - Face Shape (Heart-shaped / Angular)

struct FaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Herzförmiges Gesicht mit markantem Kinn
        path.move(to: CGPoint(x: w * 0.5, y: 0))

        // Linke Stirn-Seite
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.35),
            control1: CGPoint(x: w * 0.15, y: 0),
            control2: CGPoint(x: 0, y: h * 0.15)
        )

        // Linke Wange
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.75),
            control1: CGPoint(x: 0, y: h * 0.55),
            control2: CGPoint(x: w * 0.05, y: h * 0.65)
        )

        // Kinn links
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * 0.25, y: h * 0.9),
            control2: CGPoint(x: w * 0.4, y: h * 0.98)
        )

        // Kinn rechts
        path.addCurve(
            to: CGPoint(x: w * 0.85, y: h * 0.75),
            control1: CGPoint(x: w * 0.6, y: h * 0.98),
            control2: CGPoint(x: w * 0.75, y: h * 0.9)
        )

        // Rechte Wange
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.35),
            control1: CGPoint(x: w * 0.95, y: h * 0.65),
            control2: CGPoint(x: w, y: h * 0.55)
        )

        // Rechte Stirn-Seite
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w, y: h * 0.15),
            control2: CGPoint(x: w * 0.85, y: 0)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Tech Eye

struct TechEye: View {
    let openness: CGFloat
    let pupilOffsetX: CGFloat
    let pupilOffsetY: CGFloat
    let eyeColor: Color
    let highlightColor: Color
    let isLeft: Bool

    var body: some View {
        ZStack {
            // Augenweiß
            EyeWhiteShape()
                .fill(Color.white)
                .frame(width: 55, height: 60 * max(0.05, openness))

            // Oberer Lidschatten
            EyeWhiteShape()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.1), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 55, height: 60 * max(0.05, openness))

            if openness > 0.2 {
                // Iris
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [highlightColor, eyeColor, eyeColor.opacity(0.8)],
                            center: .init(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 35, height: 35)
                    .offset(x: pupilOffsetX, y: pupilOffsetY + 3)

                // Pupille
                Circle()
                    .fill(Color.black)
                    .frame(width: 18, height: 18)
                    .offset(x: pupilOffsetX, y: pupilOffsetY + 3)

                // Großes Glanzlicht
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .offset(x: pupilOffsetX - 8, y: pupilOffsetY - 6)

                // Kleines Glanzlicht
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 6, height: 6)
                    .offset(x: pupilOffsetX + 8, y: pupilOffsetY + 8)
            }
        }
        .clipShape(EyeWhiteShape().size(width: 55, height: 60 * max(0.05, openness)))
    }
}

struct EyeWhiteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Mandelförmiges Auge
        path.move(to: CGPoint(x: 0, y: h * 0.5))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control: CGPoint(x: w * 0.15, y: 0)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control: CGPoint(x: w * 0.85, y: 0)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control: CGPoint(x: w * 0.85, y: h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.5),
            control: CGPoint(x: w * 0.15, y: h)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Tech Mouth

struct TechMouth: View {
    let openness: CGFloat
    let smile: CGFloat
    let lipColor: Color
    let teethColor: Color

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = size.height / 2
            let baseWidth: CGFloat = 30 + smile * 15

            if openness > 0.1 {
                // Offener Mund - ovale Form
                let mouthWidth = baseWidth + openness * 8
                let mouthHeight = 6 + openness * 20

                // Mund-Inneres (dunkel)
                var innerPath = Path()
                innerPath.addEllipse(in: CGRect(
                    x: midX - mouthWidth / 2,
                    y: midY - mouthHeight / 2,
                    width: mouthWidth,
                    height: mouthHeight
                ))
                context.fill(innerPath, with: .color(Color(red: 0.2, green: 0.08, blue: 0.1)))

                // Zähne (oben) - nur bei weiter offenem Mund
                if openness > 0.3 {
                    let teethWidth = mouthWidth * 0.75
                    let teethHeight = min(mouthHeight * 0.25, 6)
                    var teethPath = Path()
                    teethPath.addRoundedRect(
                        in: CGRect(
                            x: midX - teethWidth / 2,
                            y: midY - mouthHeight / 2 + 2,
                            width: teethWidth,
                            height: teethHeight
                        ),
                        cornerSize: CGSize(width: 2, height: 2)
                    )
                    context.fill(teethPath, with: .color(teethColor))
                }

                // Zunge - bei sehr offenem Mund
                if openness > 0.5 {
                    let tongueWidth = mouthWidth * 0.5
                    let tongueHeight = mouthHeight * 0.4
                    var tonguePath = Path()
                    tonguePath.addEllipse(in: CGRect(
                        x: midX - tongueWidth / 2,
                        y: midY,
                        width: tongueWidth,
                        height: tongueHeight
                    ))
                    context.fill(tonguePath, with: .color(Color(red: 0.9, green: 0.5, blue: 0.5)))
                }

                // Lippen-Umrandung
                var lipPath = Path()
                lipPath.addEllipse(in: CGRect(
                    x: midX - mouthWidth / 2,
                    y: midY - mouthHeight / 2,
                    width: mouthWidth,
                    height: mouthHeight
                ))
                context.stroke(lipPath, with: .color(lipColor), lineWidth: 2)

            } else {
                // Geschlossener lächelnder Mund
                let curveDown = smile * 10

                var path = Path()
                path.move(to: CGPoint(x: midX - baseWidth / 2, y: midY))
                path.addQuadCurve(
                    to: CGPoint(x: midX + baseWidth / 2, y: midY),
                    control: CGPoint(x: midX, y: midY + curveDown)
                )
                context.stroke(path, with: .color(lipColor), lineWidth: 2.5)

                // Kleine Mundwinkel-Akzente
                if smile > 0.4 {
                    var leftCorner = Path()
                    leftCorner.move(to: CGPoint(x: midX - baseWidth / 2, y: midY))
                    leftCorner.addQuadCurve(
                        to: CGPoint(x: midX - baseWidth / 2 - 3, y: midY - 2),
                        control: CGPoint(x: midX - baseWidth / 2 - 2, y: midY)
                    )
                    context.stroke(leftCorner, with: .color(lipColor), lineWidth: 2)

                    var rightCorner = Path()
                    rightCorner.move(to: CGPoint(x: midX + baseWidth / 2, y: midY))
                    rightCorner.addQuadCurve(
                        to: CGPoint(x: midX + baseWidth / 2 + 3, y: midY - 2),
                        control: CGPoint(x: midX + baseWidth / 2 + 2, y: midY)
                    )
                    context.stroke(rightCorner, with: .color(lipColor), lineWidth: 2)
                }
            }
        }
        .frame(width: 80, height: 50)
    }
}

// MARK: - Eyebrow Shape

struct EyebrowShape: Shape {
    var raised: Bool
    var worried: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: h * 0.8))
        path.addQuadCurve(
            to: CGPoint(x: w, y: raised ? h * 0.2 : h * 0.5),
            control: CGPoint(x: w * 0.5, y: worried ? h * 0.3 : 0)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h),
            control: CGPoint(x: w * 0.5, y: h * 0.6)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Hair Spike Shapes

struct FrontHairSpike: Shape {
    let index: Int
    var waveOffset: CGFloat

    var animatableData: CGFloat {
        get { waveOffset }
        set { waveOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let wave = sin(CGFloat(index) + waveOffset * .pi) * 3

        // Spitze Haarsträhne
        path.move(to: CGPoint(x: w * 0.2, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.5 + wave, y: h),
            control1: CGPoint(x: w * 0.1, y: h * 0.4),
            control2: CGPoint(x: w * 0.3, y: h * 0.7)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.8, y: 0),
            control1: CGPoint(x: w * 0.7, y: h * 0.7),
            control2: CGPoint(x: w * 0.9, y: h * 0.4)
        )
        path.closeSubpath()

        return path
    }
}

struct TopHairSpike: Shape {
    let index: Int
    var waveOffset: CGFloat

    var animatableData: CGFloat {
        get { waveOffset }
        set { waveOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let wave = sin(CGFloat(index) * 1.5 + waveOffset * .pi) * 4

        path.move(to: CGPoint(x: w * 0.3, y: h))
        path.addCurve(
            to: CGPoint(x: w * 0.5 + wave, y: 0),
            control1: CGPoint(x: w * 0.2, y: h * 0.5),
            control2: CGPoint(x: w * 0.4, y: h * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.7, y: h),
            control1: CGPoint(x: w * 0.6, y: h * 0.2),
            control2: CGPoint(x: w * 0.8, y: h * 0.5)
        )
        path.closeSubpath()

        return path
    }
}

struct BackHairSpike: Shape {
    let index: Int
    var waveOffset: CGFloat

    var animatableData: CGFloat {
        get { waveOffset }
        set { waveOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let wave = sin(CGFloat(index) + waveOffset * .pi * 0.5) * 5

        path.move(to: CGPoint(x: w * 0.2, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5 + wave, y: h),
            control: CGPoint(x: w * 0.1, y: h * 0.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.8, y: 0),
            control: CGPoint(x: w * 0.9, y: h * 0.6)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Shoulder Shape

struct ShoulderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.3, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h),
            control: CGPoint(x: w * 0.1, y: h * 0.3)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.7, y: 0),
            control: CGPoint(x: w * 0.9, y: h * 0.3)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Collar Shape

struct CollarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.8),
            control: CGPoint(x: w * 0.2, y: h * 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w * 0.8, y: h * 0.5)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()

        return path
    }
}
