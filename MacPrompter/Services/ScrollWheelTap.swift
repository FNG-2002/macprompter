import AppKit

/// Listen-only event tap for scroll events anywhere on screen. Unlike a global
/// NSEvent monitor it also sees scrolling over areas that do not scroll and
/// over this app's own windows. Needs Input Monitoring and never alters events.
@MainActor
final class ScrollWheelTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: (NSEvent) -> Void
    /// False without Input Monitoring; recreate the tap once access is granted.
    var isActive: Bool { tap != nil }

    init(handler: @escaping (NSEvent) -> Void) {
        self.handler = handler
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, refcon in
                if let refcon {
                    let owner = Unmanaged<ScrollWheelTap>.fromOpaque(refcon).takeUnretainedValue()
                    // The source runs on the main run loop.
                    MainActor.assumeIsolated { owner.receive(type, event) }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .scrollWheel, let event = NSEvent(cgEvent: event) else { return }
        handler(event)
    }

    /// Must run before release: the tap holds an unretained pointer to self.
    func invalidate() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil; source = nil
    }

    isolated deinit { invalidate() }
}
