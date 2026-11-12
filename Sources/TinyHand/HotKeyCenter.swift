import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var releaseHandlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        // Both the press and the release of a shortcut's key, so a shortcut can be held.
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    HotKeyCenter.shared.releaseHandlers[hkID.id]?()
                } else {
                    HotKeyCenter.shared.handlers[hkID.id]?()
                }
                return noErr
            },
            specs.count,
            &specs,
            nil,
            &eventHandler
        )
    }

    /// Registers a global shortcut. `action` runs when it is pressed; `onRelease`, if given,
    /// runs when its key is let go.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void,
                  onRelease: (() -> Void)? = nil) -> UInt32? {
        let id = nextID
        nextID += 1
        handlers[id] = action
        releaseHandlers[id] = onRelease

        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x54484B59), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref = ref else {
            handlers[id] = nil
            releaseHandlers[id] = nil
            return nil
        }
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
        releaseHandlers[id] = nil
    }
}
