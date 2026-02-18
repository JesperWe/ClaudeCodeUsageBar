import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let topProgress: Double
    let bottomProgress: Double
    var hasData: Bool = true

    @State private var pulseOpacity: Double = 1.0
    @State private var timer: Timer?

    private var topAlert: Bool { hasData && topProgress > 0.9 }
    private var bottomAlert: Bool { hasData && bottomProgress > 0.9 }
    private var anyAlert: Bool { topAlert || bottomAlert }

    var body: some View {
        Image(nsImage: renderIcon(pulseOpacity: pulseOpacity))
            .onChange(of: anyAlert) {
                updateTimer()
            }
            .onAppear {
                updateTimer()
            }
    }

    private func updateTimer() {
        timer?.invalidate()
        if anyAlert {
            pulseOpacity = 1.0
            let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                // Triangle wave: 1.5s cycle, range 0.1 to 1.0
                let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                let wave = phase < 0.5 ? 1.0 - phase * 2.0 : (phase - 0.5) * 2.0
                pulseOpacity = 0.1 + wave * 0.9
            }
            timer = t
        } else {
            timer = nil
            pulseOpacity = 1.0
        }
    }

    private func renderIcon(pulseOpacity: Double) -> NSImage {
        let width: CGFloat = 18
        let height: CGFloat = 18
        let barHeight: CGFloat = 6
        let barSpacing: CGFloat = 2
        let cornerRadius: CGFloat = 1.5

        let totalBarsHeight = barHeight * 2 + barSpacing
        let yOffset = (height - totalBarsHeight) / 2
        let useTemplate = !anyAlert

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let topBarY = yOffset + barHeight + barSpacing
            let bottomBarY = yOffset

            let bgColor: NSColor = useTemplate ? NSColor.white.withAlphaComponent(0.3) : NSColor.gray.withAlphaComponent(0.3)
            let fillColor: NSColor = useTemplate ? NSColor.white : NSColor.white

            // Top bar background
            let topBgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: topBarY, width: width, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
            bgColor.setFill()
            topBgPath.fill()

            // Top bar fill
            if hasData {
                let topFillWidth = width * CGFloat(topProgress)
                if topFillWidth > 0 {
                    let topFillPath = NSBezierPath(roundedRect: NSRect(x: 0, y: topBarY, width: topFillWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
                    if topAlert {
                        NSColor.orange.withAlphaComponent(CGFloat(pulseOpacity)).setFill()
                    } else {
                        fillColor.setFill()
                    }
                    topFillPath.fill()
                }
            }

            // Bottom bar background
            let bottomBgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: bottomBarY, width: width, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
            bgColor.setFill()
            bottomBgPath.fill()

            // Bottom bar fill
            if hasData {
                let bottomFillWidth = width * CGFloat(bottomProgress)
                if bottomFillWidth > 0 {
                    let bottomFillPath = NSBezierPath(roundedRect: NSRect(x: 0, y: bottomBarY, width: bottomFillWidth, height: barHeight), xRadius: cornerRadius, yRadius: cornerRadius)
                    if bottomAlert {
                        NSColor.orange.withAlphaComponent(CGFloat(pulseOpacity)).setFill()
                    } else {
                        fillColor.setFill()
                    }
                    bottomFillPath.fill()
                }
            }

            return true
        }

        image.isTemplate = useTemplate
        return image
    }
}
