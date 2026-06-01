import Cocoa
import IOKit
import IOKit.pwr_mgt

enum ActivityState: String {
    case typing
    case clicking
    case watching
    case idle

    var symbolName: String {
        switch self {
        case .typing:   return "keyboard"
        case .clicking: return "cursorarrow"
        case .watching: return "eye"
        case .idle:     return "moon.zzz"
        }
    }

    var label: String {
        switch self {
        case .typing:   return "Typing"
        case .clicking: return "Working"
        case .watching: return "Watching"
        case .idle:     return "Idle"
        }
    }

    var countsAsActive: Bool { self != .idle }
}

enum ActivityMonitor {
    /// Seconds since the last keyboard event from any source.
    static func secondsSinceKey() -> TimeInterval {
        let key = CGEventType(rawValue: 10)! // kCGEventKeyDown
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: key)
    }

    /// Seconds since the last mouse movement from any source.
    static func secondsSinceMouse() -> TimeInterval {
        let move = CGEventType.mouseMoved
        let click = CGEventType.leftMouseDown
        let scroll = CGEventType.scrollWheel
        let a = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: move)
        let b = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: click)
        let c = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: scroll)
        return min(a, b, c)
    }

    /// Seconds since any HID input event.
    static func secondsSinceAnyInput() -> TimeInterval {
        // CGEventType raw value ~0 means "any event type".
        let any = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    /// True when some process is asking the display to stay awake — typical of
    /// video playback (Safari/Chrome/QuickTime/VLC/Music with visualizer/etc.).
    static func isDisplaySleepPrevented() -> Bool {
        var assertionsRef: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsRef)
        guard result == kIOReturnSuccess,
              let dict = assertionsRef?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }

        let interesting: Set<String> = [
            kIOPMAssertionTypeNoDisplaySleep as String,
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        ]
        for (_, assertions) in dict {
            for a in assertions {
                if let type = a[kIOPMAssertionTypeKey as String] as? String,
                   interesting.contains(type) {
                    return true
                }
            }
        }
        return false
    }

    static func currentState(idleThreshold: TimeInterval) -> ActivityState {
        let keyIdle = secondsSinceKey()
        let mouseIdle = secondsSinceMouse()

        if keyIdle < 2 { return .typing }
        if mouseIdle < idleThreshold { return .clicking }
        // No recent input: are we passively watching?
        if isDisplaySleepPrevented() { return .watching }
        return .idle
    }
}
