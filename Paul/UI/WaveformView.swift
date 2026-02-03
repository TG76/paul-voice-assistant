import SwiftUI

struct WaveformView: View {
    let audioLevel: Float
    @State private var phase: Double = 0

    private let barCount = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    let normalizedLevel = CGFloat(max(0.05, min(1.0, audioLevel * 50)))
                    let offset = Double(index) / Double(barCount) * .pi * 2
                    let wave = sin(phase + offset)
                    let height = 10 + normalizedLevel * 120 * CGFloat(0.5 + 0.5 * wave)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: height)
                }
            }
            .onChange(of: timeline.date) { _, _ in
                phase += 0.15
            }
        }
        .frame(height: 140)
    }
}
