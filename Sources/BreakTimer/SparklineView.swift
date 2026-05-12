import Cocoa

/// Tiny bar-chart inside the menu. One bar per minute, oldest on the left.
final class SparklineView: NSView {

    var buckets: [Int] = [] {
        didSet {
            if buckets != oldValue { needsDisplay = true }
        }
    }

    private let leftPad: CGFloat = 14
    private let rightPad: CGFloat = 14
    private let topPad: CGFloat = 6
    private let bottomPad: CGFloat = 14

    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background mirrors the menu's, so don't fill.
        let chartRect = NSRect(
            x: leftPad,
            y: bottomPad,
            width: bounds.width - leftPad - rightPad,
            height: bounds.height - topPad - bottomPad
        )

        // Baseline.
        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: chartRect.minX, y: chartRect.minY))
        baseline.line(to: NSPoint(x: chartRect.maxX, y: chartRect.minY))
        baseline.lineWidth = 0.5
        baseline.stroke()

        guard !buckets.isEmpty else { return }

        let peak = max(7, buckets.max() ?? 1) // scale so the red threshold is visible
        let n = CGFloat(buckets.count)
        let gap: CGFloat = 2
        let barW = (chartRect.width - gap * (n - 1)) / n

        for (i, count) in buckets.enumerated() {
            let h = CGFloat(count) / CGFloat(peak) * chartRect.height
            guard h > 0 else { continue }
            let x = chartRect.minX + CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: chartRect.minY, width: barW, height: max(2, h))
            colorFor(count: count).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        // X-axis label: "10m ago" … "now".
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let leftLabel = NSAttributedString(string: "10m", attributes: labelAttrs)
        let rightLabel = NSAttributedString(string: "now", attributes: labelAttrs)
        leftLabel.draw(at: NSPoint(x: chartRect.minX,
                                   y: chartRect.minY - 12))
        let rsize = rightLabel.size()
        rightLabel.draw(at: NSPoint(x: chartRect.maxX - rsize.width,
                                    y: chartRect.minY - 12))
    }

    private func colorFor(count: Int) -> NSColor {
        switch count {
        case ..<4:  return .systemGreen
        case 4...5: return .systemYellow
        case 6:     return .systemOrange
        default:    return .systemRed
        }
    }
}
