import AppKit
import ApplicationServices
import StayPaneCore

enum AccessibilityWindowCatalogError: LocalizedError {
    case applicationUnavailable(String)
    case discoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case let .applicationUnavailable(applicationName):
            "\(applicationName) is not running, so its windows are unavailable."
        case let .discoveryFailed(applicationName):
            "StayPane could not inspect the windows belonging to \(applicationName)."
        }
    }
}

struct AccessibilityWindowDescriptor {
    let element: AXUIElement
    let title: String
    let role: String?
    let subrole: String?
    let isModal: Bool
    let isFocused: Bool
    let parentElement: AXUIElement?
    let frame: CGRect?
    let accessibilityIdentifier: String?

    init(
        element: AXUIElement,
        title: String,
        role: String?,
        subrole: String?,
        isModal: Bool,
        isFocused: Bool,
        parentElement: AXUIElement?,
        frame: CGRect?,
        accessibilityIdentifier: String? = nil
    ) {
        self.element = element
        self.title = title
        self.role = role
        self.subrole = subrole
        self.isModal = isModal
        self.isFocused = isFocused
        self.parentElement = parentElement
        self.frame = frame
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

@MainActor
protocol AccessibilityWindowProviding: AnyObject {
    func windows(processIdentifier: Int32) throws -> [AccessibilityWindowDescriptor]
}

@MainActor
final class SystemAccessibilityWindowProvider: AccessibilityWindowProviding {
    func windows(processIdentifier: Int32) throws -> [AccessibilityWindowDescriptor] {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        if result == .noValue || result == .attributeUnsupported {
            return []
        }
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            throw AccessibilityWindowCatalogError.discoveryFailed("the application")
        }

        let focusedWindow = elementValue(
            kAXFocusedWindowAttribute,
            of: applicationElement
        )
        return windows.map { window in
            AccessibilityWindowDescriptor(
                element: window,
                title: stringValue(kAXTitleAttribute, of: window)
                    .flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Untitled Window",
                role: stringValue(kAXRoleAttribute, of: window),
                subrole: stringValue(kAXSubroleAttribute, of: window),
                isModal: boolValue(kAXModalAttribute, of: window) ?? false,
                isFocused: focusedWindow.map { CFEqual($0, window) } ?? false,
                parentElement: elementValue(kAXParentAttribute, of: window),
                frame: frame(of: window),
                accessibilityIdentifier: stringValue(
                    kAXIdentifierAttribute,
                    of: window
                )
            )
        }
    }

    private func stringValue(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        copyValue(attribute, of: element) as? String
    }

    private func boolValue(
        _ attribute: String,
        of element: AXUIElement
    ) -> Bool? {
        copyValue(attribute, of: element) as? Bool
    }

    private func elementValue(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        guard
            let value = copyValue(attribute, of: element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyValue(
        _ attribute: String,
        of element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard
            let positionValue = copyValue(kAXPositionAttribute, of: element),
            let sizeValue = copyValue(kAXSizeAttribute, of: element),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        let positionAXValue = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue, to: AXValue.self)
        guard
            AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

struct CataloguedAccessibilityWindow {
    let target: WindowTarget
    let element: AXUIElement
    let observation: ObservedWindow
    let isFocused: Bool
    let exactReference: ExactWindowReference?
}

@MainActor
final class AccessibilityWindowCatalog {
    private struct PersistentIdentityKey: Hashable {
        let bundleIdentifier: String
        let processIdentifier: Int32
        let accessibilityIdentifier: String
    }

    private struct RegistryEntry {
        let identifier: WindowIdentifier
        let processIdentifier: Int32
        let element: AXUIElement
    }

    private let provider: any AccessibilityWindowProviding
    private var registry: [RegistryEntry] = []
    private var latestDescriptors: [WindowIdentifier: AccessibilityWindowDescriptor] = [:]
    private var latestProcessIdentifiers: [WindowIdentifier: Int32] = [:]
    private var reconnectedIdentifiers: [PersistentIdentityKey: WindowIdentifier]

    init(
        provider: any AccessibilityWindowProviding = SystemAccessibilityWindowProvider(),
        exactWindowReferences: [ExactWindowReference] = []
    ) {
        self.provider = provider
        reconnectedIdentifiers = [:]
        registerExactWindowReferences(exactWindowReferences)
    }

    func registerExactWindowReferences(
        _ references: [ExactWindowReference]
    ) {
        for reference in references {
            reconnectedIdentifiers[
                PersistentIdentityKey(
                    bundleIdentifier: reference.bundleIdentifier,
                    processIdentifier: reference.processIdentifier,
                    accessibilityIdentifier: reference.accessibilityIdentifier
                )
            ] = reference.windowIdentifier
        }
    }

    func loadWindows(
        for application: ApplicationTarget
    ) throws -> [WindowTarget] {
        try catalogueWindows(for: application).map(\.target)
    }

    func unavailableWindowTargets(in targets: [SessionTarget]) -> [WindowTarget] {
        targets.compactMap { target in
            guard case let .window(window) = target, !isAvailable(window) else {
                return nil
            }
            return window
        }
    }

    func catalogueWindows(
        for application: ApplicationTarget
    ) throws -> [CataloguedAccessibilityWindow] {
        guard let processIdentifier = processIdentifier(for: application) else {
            throw AccessibilityWindowCatalogError.applicationUnavailable(
                application.displayName
            )
        }
        let descriptors: [AccessibilityWindowDescriptor]
        do {
            descriptors = try provider.windows(processIdentifier: processIdentifier)
        } catch {
            throw AccessibilityWindowCatalogError.discoveryFailed(
                application.displayName
            )
        }

        latestProcessIdentifiers
            .filter { $0.value == processIdentifier }
            .map(\.key)
            .forEach {
                latestDescriptors.removeValue(forKey: $0)
                latestProcessIdentifiers.removeValue(forKey: $0)
            }

        let accessibilityIdentifierCounts = Dictionary(
            grouping: descriptors.compactMap(\.accessibilityIdentifier),
            by: { $0 }
        ).mapValues(\.count)
        let descriptorIdentifiers = descriptors.map { descriptor in
            identifier(
                for: descriptor,
                processIdentifier: processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                persistentIdentityIsUnique: descriptor.accessibilityIdentifier.map {
                    accessibilityIdentifierCounts[$0] == 1
                } ?? false
            )
        }
        for (identifier, descriptor) in zip(descriptorIdentifiers, descriptors) {
            latestDescriptors[identifier] = descriptor
            latestProcessIdentifiers[identifier] = processIdentifier
        }

        return zip(descriptorIdentifiers, descriptors)
            .map { identifier, descriptor in
                let target = WindowTarget(
                    id: identifier,
                    title: descriptor.title,
                    application: application
                )
                return CataloguedAccessibilityWindow(
                    target: target,
                    element: descriptor.element,
                    observation: ObservedWindow(
                        id: identifier,
                        bundleIdentifier: application.bundleIdentifier,
                        relationship: relationship(
                            for: descriptor,
                            in: descriptors,
                            identifiers: descriptorIdentifiers,
                            bundleIdentifier: application.bundleIdentifier
                        )
                    ),
                    isFocused: descriptor.isFocused,
                    exactReference: descriptor.accessibilityIdentifier.flatMap {
                        guard accessibilityIdentifierCounts[$0] == 1 else {
                            return nil
                        }
                        return ExactWindowReference(
                            windowIdentifier: identifier,
                            bundleIdentifier: application.bundleIdentifier,
                            processIdentifier: processIdentifier,
                            accessibilityIdentifier: $0
                        )
                    }
                )
            }
            .sorted {
                $0.target.title.localizedCaseInsensitiveCompare($1.target.title)
                    == .orderedAscending
            }
    }

    func isAvailable(_ target: WindowTarget) -> Bool {
        guard let windows = try? catalogueWindows(for: target.application) else {
            return false
        }
        return windows.contains { $0.target.id == target.id }
    }

    func element(for identifier: WindowIdentifier) -> AXUIElement? {
        latestDescriptors[identifier]?.element
    }

    func frame(for identifier: WindowIdentifier) -> CGRect? {
        latestDescriptors[identifier]?.frame
    }

    private func identifier(
        for descriptor: AccessibilityWindowDescriptor,
        processIdentifier: Int32,
        bundleIdentifier: String,
        persistentIdentityIsUnique: Bool
    ) -> WindowIdentifier {
        if let existing = registry.first(where: {
            $0.processIdentifier == processIdentifier
                && CFEqual($0.element, descriptor.element)
        }) {
            return existing.identifier
        }

        let reconnectedIdentifier: WindowIdentifier? = descriptor
            .accessibilityIdentifier.flatMap {
                guard persistentIdentityIsUnique else {
                    return nil
                }
                return reconnectedIdentifiers.removeValue(
                    forKey: PersistentIdentityKey(
                        bundleIdentifier: bundleIdentifier,
                        processIdentifier: processIdentifier,
                        accessibilityIdentifier: $0
                    )
                )
            }
        let identifier = reconnectedIdentifier ?? WindowIdentifier()
        registry.append(
            RegistryEntry(
                identifier: identifier,
                processIdentifier: processIdentifier,
                element: descriptor.element
            )
        )
        return identifier
    }

    private func relationship(
        for descriptor: AccessibilityWindowDescriptor,
        in descriptors: [AccessibilityWindowDescriptor],
        identifiers: [WindowIdentifier],
        bundleIdentifier: String
    ) -> WindowRelationship {
        if Self.essentialSystemBundleIdentifiers.contains(bundleIdentifier) {
            return .essentialSystemInterface
        }

        let ancestors = ancestorIdentifiers(
            startingAt: descriptor.parentElement,
            descriptors: descriptors,
            identifiers: identifiers
        )
        let isTransient = descriptor.role == "AXSheet"
            || descriptor.isModal
            || descriptor.subrole == "AXDialog"
            || descriptor.subrole == "AXFloatingWindow"
            || descriptor.subrole == "AXSystemFloatingWindow"
        if isTransient, !ancestors.isEmpty {
            return .transient(ancestorWindowIdentifiers: ancestors)
        }
        return .independent
    }

    private func ancestorIdentifiers(
        startingAt parentElement: AXUIElement?,
        descriptors: [AccessibilityWindowDescriptor],
        identifiers: [WindowIdentifier]
    ) -> [WindowIdentifier] {
        var ancestors: [WindowIdentifier] = []
        var currentParent = parentElement
        var visitedCount = 0

        while let parent = currentParent, visitedCount < 8 {
            visitedCount += 1
            guard let index = descriptors.firstIndex(where: {
                CFEqual($0.element, parent)
            }) else {
                break
            }
            ancestors.append(identifiers[index])
            currentParent = descriptors[index].parentElement
        }
        return ancestors
    }

    private func processIdentifier(for application: ApplicationTarget) -> Int32? {
        if let processIdentifier = application.processIdentifier {
            return processIdentifier
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: application.bundleIdentifier
        ).first(where: { !$0.isTerminated })?.processIdentifier
    }

    static func isEssentialSystemApplication(bundleIdentifier: String) -> Bool {
        essentialSystemBundleIdentifiers.contains(bundleIdentifier)
    }

    private static let essentialSystemBundleIdentifiers: Set<String> = [
        "com.apple.CoreServicesUIAgent",
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
        "com.apple.systemuiserver"
    ]
}
