import Cocoa

/// Full-screen overlay shown when it's time for a break.
/// Phase 1: Accept / Decline prompt over a calm gradient.
/// Phase 2 (after Accept): the same wallpaper with a large countdown timer.
final class BreakWindow: NSWindowController {

    private let breakDurationSeconds: Int
    private let onDecline: () -> Void
    private let onFinish: () -> Void

    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0
    private var countdownLabel: NSTextField?
    private var gradientLayer: CAGradientLayer?

    init(breakDurationSeconds: Int,
         onDecline: @escaping () -> Void,
         onFinish: @escaping () -> Void)
    {
        self.breakDurationSeconds = breakDurationSeconds
        self.onDecline = onDecline
        self.onFinish = onFinish

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)

        super.init(window: window)

        let content = NSView(frame: screen.frame)
        content.wantsLayer = true
        let gradient = BreakWindow.makeRelaxingGradient(frame: screen.frame)
        content.layer = gradient
        self.gradientLayer = gradient
        window.contentView = content

        installCountdownUI(on: content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Background

    private static func makeRelaxingGradient(frame: NSRect) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.frame = frame
        // Soft dusk: deep indigo at top, warm peach near the horizon.
        g.colors = [
            NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.22, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.46, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.55, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.45, alpha: 1.0).cgColor,
        ]
        g.locations = [0.0, 0.45, 0.78, 1.0]
        g.startPoint = CGPoint(x: 0.5, y: 1.0)
        g.endPoint   = CGPoint(x: 0.5, y: 0.0)
        return g
    }

    // MARK: - Countdown

    private func installCountdownUI(on content: NSView) {
        remainingSeconds = breakDurationSeconds

        let title = label(text: "Break time",
                          size: 28, weight: .regular, alpha: 0.85)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let timeLabel = NSTextField(labelWithString: formatTime(remainingSeconds))
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 180, weight: .ultraLight)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(timeLabel)
        countdownLabel = timeLabel

        let hint = label(text: "Look away. Stretch. Breathe.",
                         size: 18, weight: .regular, alpha: 0.7)
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        let declineBtn = bigButton(title: "Decline", filled: false)
        declineBtn.target = self
        declineBtn.action = #selector(declineTapped)
        declineBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(declineBtn)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            title.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -8),

            timeLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -30),

            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hint.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 24),

            declineBtn.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            declineBtn.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 56),
            declineBtn.widthAnchor.constraint(equalToConstant: 240),
            declineBtn.heightAnchor.constraint(equalToConstant: 44),
        ])

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            countdownLabel?.stringValue = formatTime(0)
            finishBreak()
            return
        }
        countdownLabel?.stringValue = formatTime(remainingSeconds)
    }

    // MARK: - Actions

    @objc private func declineTapped() {
        teardown()
        onDecline()
    }

    private func finishBreak() {
        teardown()
        onFinish()
    }

    private func teardown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        window?.orderOut(nil)
    }

    // MARK: - Show

    func show() {
        window?.alphaValue = 0
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            window?.animator().alphaValue = 1
        }
    }

    // MARK: - UI helpers

    private func label(text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor.white.withAlphaComponent(alpha)
        l.alignment = .center
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        return l
    }

    private func bigButton(title: String, filled: Bool) -> NSButton {
        let b = HoverButton(title: title, target: nil, action: nil)
        b.isBordered = false
        b.wantsLayer = true
        b.contentTintColor = .white

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        b.attributedTitle = NSAttributedString(string: title, attributes: attrs)

        let layer = b.layer!
        layer.cornerRadius = 26
        layer.borderWidth = 1.5
        layer.borderColor = NSColor.white.withAlphaComponent(filled ? 0 : 0.7).cgColor
        layer.backgroundColor = filled
            ? NSColor.white.withAlphaComponent(0.22).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        b.filledStyle = filled
        return b
    }

    private func formatTime(_ s: Int) -> String {
        let m = max(0, s) / 60
        let sec = max(0, s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

/// Subtle hover highlight for the overlay buttons.
private final class HoverButton: NSButton {
    var filledStyle: Bool = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self,
                               userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white
            .withAlphaComponent(filledStyle ? 0.34 : 0.16).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white
            .withAlphaComponent(filledStyle ? 0.22 : 0.06).cgColor
    }
}
