import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Configuration
    /// Seconds without keyboard/mouse before we stop counting as "active",
    /// unless something is keeping the display awake (then we count as watching).
    private let inputIdleThreshold: TimeInterval = 60
    /// If idle this long, decay accumulated active time.
    private let resetIdleThreshold: TimeInterval = 5 * 60
    /// Available break intervals offered in the menu.
    private let intervalChoices: [Int] = [15, 20, 25, 30, 45, 60, 90]
    /// Sliding window for the thrash threshold.
    private let switchWindow: TimeInterval = 30
    /// Switches in `switchWindow` that trigger the "hold" prompt.
    private let switchAlertThreshold = 7
    /// Don't re-prompt for at least this long after dismissing.
    private let switchPromptCooldown: TimeInterval = 120
    /// Switches per minute above which the "focus!" alert fires.
    private let focusAlertThreshold = 4
    /// Don't re-fire the focus alert for at least this long.
    private let focusAlertCooldown: TimeInterval = 60
    /// Sparkline buckets: per-minute counts for the last 10 minutes.
    private let graphBuckets = 10
    private let graphBucketSeconds: TimeInterval = 60

    // MARK: State
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var activeSeconds: Int = 0
    private var breakIntervalSeconds: Int = 20 * 60
    private var lastState: ActivityState = .idle
    private var snoozedUntil: Date?

    private var switchTimestamps: [Date] = []
    private var lastSwitchPromptAt: Date?
    private var switchPromptShowing = false
    private var lastSwitchLevel: Int = 0
    private var lastFocusAlertAt: Date?
    private var focusAlertShowing = false

    // Menu items kept around so we can mutate their titles each tick.
    private var stateItem: NSMenuItem!
    private var rateItem: NSMenuItem!
    private var totalItem: NSMenuItem!
    private var sparklineView: SparklineView!

    // MARK: Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPrefs()
        requestNotificationPermissionIfPossible()
        buildStatusItem()
        subscribeToAppSwitches()
        startTicking()
        refresh(force: true)
    }

    private func subscribeToAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        // Ignore our own activations (e.g. opening the menu, showing the alert).
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        // Ignore the system finder/loginwindow activation noise.
        if let bid = app.bundleIdentifier, bid == "com.apple.loginwindow" { return }
        switchTimestamps.append(Date())
    }

    // MARK: Status item & menu
    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.imagePosition = .imageLeading
            btn.image = symbolImage(for: .idle)
            btn.image?.isTemplate = true
            // Always show a text label so the item has non-zero width and is
            // findable even if the SF Symbol fails to render on this OS build.
            btn.title = " 0m"
            btn.font = NSFont.menuBarFont(ofSize: 0)
            btn.toolTip = "BreakTimer"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateItem = NSMenuItem(title: "State: Idle", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        rateItem = NSMenuItem(title: "Switches/min: 0", action: nil, keyEquivalent: "")
        rateItem.isEnabled = false
        menu.addItem(rateItem)

        totalItem = NSMenuItem(title: "Last 10 min total: 0", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        menu.addItem(totalItem)

        // Sparkline: one bar per minute over the last 10 minutes.
        let graphItem = NSMenuItem()
        sparklineView = SparklineView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 44)
        )
        graphItem.view = sparklineView
        menu.addItem(graphItem)

        menu.addItem(.separator())

        let takeBreak = NSMenuItem(title: "Take a break now", action: #selector(takeBreakNow), keyEquivalent: "b")
        takeBreak.target = self
        menu.addItem(takeBreak)

        let resetItem = NSMenuItem(title: "Reset timer", action: #selector(resetTimer), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        let snoozeItem = NSMenuItem(title: "Snooze 5 min", action: #selector(snooze), keyEquivalent: "s")
        snoozeItem.target = self
        menu.addItem(snoozeItem)

        menu.addItem(.separator())

        let intervalParent = NSMenuItem(title: "Break interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for minutes in intervalChoices {
            let item = NSMenuItem(title: "\(minutes) min",
                                  action: #selector(setInterval(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.state = (minutes * 60 == breakIntervalSeconds) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalParent.submenu = intervalMenu
        menu.addItem(intervalParent)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About BreakTimer", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func symbolImage(for state: ActivityState, tint: NSColor? = nil) -> NSImage? {
        let base = NSImage(systemSymbolName: state.symbolName,
                           accessibilityDescription: state.label)
        guard let base else { return nil }
        if let tint {
            // Palette config renders the symbol in the given color regardless
            // of the menu bar's foreground color.
            let cfg = NSImage.SymbolConfiguration(paletteColors: [tint])
            let tinted = base.withSymbolConfiguration(cfg) ?? base
            tinted.isTemplate = false
            tinted.size = NSSize(width: 16, height: 16)
            return tinted
        }
        base.isTemplate = true
        base.size = NSSize(width: 16, height: 16)
        return base
    }

    /// 0 = calm, 1 = yellow, 2 = orange, 3 = red.
    private func switchLevel(for recent: Int) -> Int {
        switch recent {
        case ..<4:  return 0
        case 4...5: return 1
        case 6:     return 2
        default:    return 3
        }
    }

    private func tint(for level: Int) -> NSColor? {
        switch level {
        case 1: return .systemYellow
        case 2: return .systemOrange
        case 3: return .systemRed
        default: return nil
        }
    }

    // MARK: Tick
    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    private func refresh(force: Bool) {
        let state = ActivityMonitor.currentState(idleThreshold: inputIdleThreshold)
        let now = Date()

        if state.countsAsActive {
            activeSeconds += 1
        } else {
            let inputIdle = ActivityMonitor.secondsSinceAnyInput()
            if inputIdle > resetIdleThreshold && activeSeconds > 0 {
                activeSeconds = max(0, activeSeconds - 2)
            }
        }

        // Break reminder (silent — no time shown in the bar, just the nudge).
        if state.countsAsActive,
           activeSeconds >= breakIntervalSeconds,
           !isSnoozed() {
            fireBreakReminder()
            activeSeconds = 0
        }

        // Prune timestamps older than the graph window (10 min) and compute counters.
        let graphSpan = Double(graphBuckets) * graphBucketSeconds
        switchTimestamps.removeAll { now.timeIntervalSince($0) > graphSpan }

        let thrashCount = switchTimestamps.reduce(0) {
            $0 + (now.timeIntervalSince($1) <= switchWindow ? 1 : 0)
        }
        let perMinute = switchTimestamps.reduce(0) {
            $0 + (now.timeIntervalSince($1) <= 60 ? 1 : 0)
        }
        let totalRecent = switchTimestamps.count
        let level = switchLevel(for: thrashCount)

        // Icon: state, tinted by thrash level.
        if state != lastState || level != lastSwitchLevel || force {
            statusItem.button?.image = symbolImage(for: state, tint: tint(for: level))
            lastState = state
            lastSwitchLevel = level
        }

        // Title: only switches-per-minute, colored when elevated.
        if let btn = statusItem.button {
            var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
            if let tint = tint(for: level) {
                attrs[.foregroundColor] = tint
            }
            btn.attributedTitle = NSAttributedString(
                string: " \(perMinute)/min",
                attributes: attrs
            )
        }

        // Menu rows + sparkline.
        stateItem.title = "State: \(state.label)"
        rateItem.title = "Switches/min: \(perMinute)"
        totalItem.title = "Last 10 min total: \(totalRecent)"
        sparklineView.buckets = computeBuckets(now: now)

        if thrashCount >= switchAlertThreshold {
            maybePromptHold(count: thrashCount)
        }

        if perMinute > focusAlertThreshold {
            maybeShowFocusAlert(perMinute: perMinute)
        }
    }

    private func maybeShowFocusAlert(perMinute: Int) {
        if focusAlertShowing { return }
        if let last = lastFocusAlertAt,
           Date().timeIntervalSince(last) < focusAlertCooldown { return }
        focusAlertShowing = true
        lastFocusAlertAt = Date()

        NSSound(named: "Funk")?.play()

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "focus!"
            alert.informativeText = "You've switched apps \(perMinute) times in the last minute."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            _ = alert.runModal()
            self.focusAlertShowing = false
        }
    }

    private func computeBuckets(now: Date) -> [Int] {
        var buckets = [Int](repeating: 0, count: graphBuckets)
        for ts in switchTimestamps {
            let age = now.timeIntervalSince(ts)
            let idx = graphBuckets - 1 - Int(age / graphBucketSeconds)
            if idx >= 0 && idx < graphBuckets {
                buckets[idx] += 1
            }
        }
        return buckets
    }

    private func maybePromptHold(count: Int) {
        if switchPromptShowing { return }
        if let last = lastSwitchPromptAt,
           Date().timeIntervalSince(last) < switchPromptCooldown { return }
        switchPromptShowing = true
        lastSwitchPromptAt = Date()

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Hold up"
            alert.informativeText = """
            You've switched apps \(count) times in the last 30 seconds.
            Take a breath — pick one thing and stay with it for a minute.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK, focusing")
            alert.addButton(withTitle: "Snooze 2 min")
            NSApp.activate(ignoringOtherApps: true)
            _ = alert.runModal()
            // Clear the window so the user gets a fresh 30s budget.
            self.switchTimestamps.removeAll()
            self.switchPromptShowing = false
        }
    }

    private func isSnoozed() -> Bool {
        if let until = snoozedUntil, Date() < until { return true }
        snoozedUntil = nil
        return false
    }

    // MARK: Reminder
    private func fireBreakReminder() {
        let mins = breakIntervalSeconds / 60
        let title = "break!!"
        let body  = "You've been active for \(mins) minutes. Look away, stretch, breathe."

        // Loud audible cue.
        NSSound(named: "Glass")?.play()

        // Foreground popup so it can't be missed.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = body
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            _ = alert.runModal()
        }

        // Also drop a system notification for the notification center log.
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body  = body
                content.sound = .default
                let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
                center.add(req, withCompletionHandler: nil)
            } else {
                DispatchQueue.main.async { self.osascriptNotify(title: title, body: body) }
            }
        }

        DispatchQueue.main.async { self.flashIcon() }
    }

    private func osascriptNotify(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let safeBody  = body.replacingOccurrences(of: "\"", with: "'")
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\" sound name \"Glass\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }

    private func flashIcon() {
        guard let btn = statusItem.button else { return }
        let original = btn.image
        let alert = NSImage(systemSymbolName: "cup.and.saucer.fill",
                            accessibilityDescription: "Break time")
        alert?.isTemplate = true
        btn.image = alert
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            btn.image = original ?? self.symbolImage(for: self.lastState)
        }
    }

    // MARK: Actions
    @objc private func takeBreakNow() {
        fireBreakReminder()
        activeSeconds = 0
    }

    @objc private func resetTimer() {
        activeSeconds = 0
        refresh(force: true)
    }

    @objc private func snooze() {
        snoozedUntil = Date().addingTimeInterval(5 * 60)
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        breakIntervalSeconds = sender.tag * 60
        savePrefs()
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.tag == sender.tag) ? .on : .off
            }
        }
        refresh(force: true)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "BreakTimer"
        alert.informativeText = """
        Tracks keyboard, mouse and video activity. When you've been active long enough, \
        it reminds you to take a break.

        Icon legend:
          ⌨︎ Typing    ◎ Working    👁 Watching    💤 Idle
        """
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Notification permission
    private func requestNotificationPermissionIfPossible() {
        // Only meaningful when launched from a bundled .app — harmless otherwise.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Prefs
    private func loadPrefs() {
        let d = UserDefaults.standard
        let stored = d.integer(forKey: "breakIntervalSeconds")
        if stored > 0 { breakIntervalSeconds = stored }
    }

    private func savePrefs() {
        UserDefaults.standard.set(breakIntervalSeconds, forKey: "breakIntervalSeconds")
    }

    // MARK: Formatting
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s)s" }
        return "\(m)m \(s)s"
    }
}
