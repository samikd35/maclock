import Carbon.HIToolbox

struct OpenPanelShortcutDefinition: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let registered = OpenPanelShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘S"
    )
}

@MainActor
final class OpenPanelShortcutController {
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    private let onOpenPanel: () -> Void

    init?(onOpenPanel: @escaping () -> Void) {
        self.onOpenPanel = onOpenPanel

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            stayPaneHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else {
            return nil
        }

        let definition = OpenPanelShortcutDefinition.registered
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers,
            EventHotKeyID(signature: Self.signature, id: Self.identifier),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr, hotKey != nil else {
            return nil
        }
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    fileprivate func openPanel() {
        onOpenPanel()
    }

    nonisolated fileprivate static let signature: OSType = 0x5354504E
    nonisolated fileprivate static let identifier: UInt32 = 1
}

private func stayPaneHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else {
        return status
    }

    guard identifier.signature == OpenPanelShortcutController.signature,
          identifier.id == OpenPanelShortcutController.identifier
    else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<OpenPanelShortcutController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.openPanel()
    }
    return noErr
}
