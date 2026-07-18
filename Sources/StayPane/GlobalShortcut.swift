import Carbon.HIToolbox

enum GlobalShortcutAction: Equatable {
    case openPanel
}

struct GlobalShortcutDefinition: Equatable {
    let action: GlobalShortcutAction
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let registered: [GlobalShortcutDefinition] = [
        GlobalShortcutDefinition(
            action: .openPanel,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "⌃⌥⌘S"
        )
    ]
}

@MainActor
final class GlobalShortcutController {
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var hotKeys: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: GlobalShortcutAction] = [:]
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

        for (index, definition) in GlobalShortcutDefinition.registered.enumerated() {
            let identifier = UInt32(index + 1)
            var hotKey: EventHotKeyRef?
            let status = RegisterEventHotKey(
                definition.keyCode,
                definition.modifiers,
                EventHotKeyID(signature: Self.signature, id: identifier),
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            guard status == noErr, let hotKey else {
                return nil
            }
            actionsByID[identifier] = definition.action
            hotKeys.append(hotKey)
        }
    }

    deinit {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    fileprivate func performAction(identifier: UInt32) {
        guard let action = actionsByID[identifier] else {
            return
        }
        switch action {
        case .openPanel:
            onOpenPanel()
        }
    }

    private static let signature: OSType = 0x5354504E
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

    let controller = Unmanaged<GlobalShortcutController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.performAction(identifier: identifier.id)
    }
    return noErr
}
