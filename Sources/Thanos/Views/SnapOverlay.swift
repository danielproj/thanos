import SwiftUI

/// The payoff: a burst of dust drifting away, and how much space came back.
struct SnapOverlay: View {
    let report: SnapReport
    let dismiss: () -> Void
    @State private var start = Date()
    @State private var particles: [Particle] = (0..<520).map { _ in Particle() }
    @State private var shown = false

    struct Particle {
        let angle = Double.random(in: 0..<(2 * .pi))
        let speed = Double.random(in: 40...300)
        let drift = Double.random(in: -60...20)
        let size = Double.random(in: 1.5...5)
        let life = Double.random(in: 1.2...2.6)
        let delay = Double.random(in: 0...0.35)
        let hue = [Color.purple, .pink, .orange, .yellow, .indigo].randomElement()!
        let ox = Double.random(in: -150...150)
        let oy = Double.random(in: -50...50)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.18 : 0).ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    for p in particles {
                        let lt = t - p.delay
                        guard lt > 0, lt < p.life else { continue }
                        let k = lt / p.life
                        let ease = 1 - pow(1 - k, 3)
                        let x = c.x + p.ox + cos(p.angle) * p.speed * ease + p.drift * k * 2
                        let y = c.y + p.oy + sin(p.angle) * p.speed * ease - 80 * k * k
                        let r = p.size * (1 - k * 0.6)
                        ctx.opacity = 1 - k
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(p.hue))
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "hand.raised.fingers.spread.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: shown)
                Text(report.freed.bytes)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text(report.items == 1 ? "1 item snapped away" : "\(report.items) items snapped away")
                    .foregroundStyle(.secondary)
                if !report.failures.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(report.failures.count) couldn't be removed").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        ForEach(report.failures.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .padding(.top, 4)
                }
                Button("Done", action: dismiss)
                    .buttonStyle(.glassProminent).tint(.purple)
                    .padding(.top, 8)
            }
            .padding(34)
            .frame(width: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            start = Date()
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.15)) { shown = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(report.failures.isEmpty ? 3.5 : 8))
            dismiss()
        }
    }
}
