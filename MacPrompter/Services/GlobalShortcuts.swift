import Carbon.HIToolbox

@MainActor
final class GlobalShortcuts {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let action: (UInt32) -> Void
    private let ids: Set<UInt32>
    var registeredCount: Int { refs.count }

    static let prompterKeys = [(UInt32(1), kVK_ANSI_P), (2, kVK_ANSI_H), (3, kVK_UpArrow), (4, kVK_DownArrow)]
    /// Only registered while presenting, so ⌥⌘←/→ stay free for other apps.
    static let slideKeys = [(UInt32(5), kVK_LeftArrow), (6, kVK_RightArrow)]

    init(keys: [(UInt32, Int)] = prompterKeys, action: @escaping (UInt32) -> Void) {
        self.action = action
        ids = Set(keys.map(\.0))
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(pointer).takeUnretainedValue()
            // Several instances share the application target; pass on foreign keys.
            guard shortcuts.ids.contains(id.id) else { return OSStatus(eventNotHandledErr) }
            let value = id.id
            Task { @MainActor in shortcuts.action(value) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (id, key) in keys {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x4D505250, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { refs.append(ref) }
        }
    }
    isolated deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
