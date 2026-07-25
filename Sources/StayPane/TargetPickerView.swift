import AppKit
import StayPaneCore
import SwiftUI

extension Notification.Name {
    static let stayPaneFocusTargetSearch = Notification.Name(
        "StayPane.focusTargetSearch"
    )
}

struct TargetPickerView: View {
    @ObservedObject var model: StayPaneModel
    @Binding var searchText: String
    @State private var focusedApplicationID: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    applicationList
                        .frame(minWidth: 210, idealWidth: 230, maxWidth: 250)
                    Divider()
                        .padding(.horizontal, 12)
                    applicationDetail
                        .frame(minWidth: 340, maxWidth: .infinity)
                }
                .frame(minHeight: 350, maxHeight: 430)

                compactLayout
            }

            selectedTargetsSummary
        }
        .onAppear {
            chooseInitialApplication()
        }
        .onChange(of: visibleApplications.map(\.id)) { _, _ in
            chooseInitialApplication()
        }
        .onChange(of: searchText) { oldValue, newValue in
            let wasSearching = !oldValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            let isSearching = !newValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            if !wasSearching && isSearching {
                refreshSearchableWindowInventory()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .stayPaneFocusTargetSearch
            )
        ) { _ in
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            moveApplicationFocus(by: -1)
        }
        .onKeyPress(.downArrow) {
            moveApplicationFocus(by: 1)
        }
        .onKeyPress(.return) {
            guard let focusedApplication else {
                return .ignored
            }
            focusApplication(focusedApplication)
            return .handled
        }
        .onKeyPress(.space) {
            guard let focusedApplication,
                  focusedApplication.isAvailable
                    || model.selectedApplicationIDs.contains(
                        focusedApplication.id
                    )
            else {
                return .ignored
            }
            model.setApplication(
                id: focusedApplication.id,
                isSelected: !model.selectedApplicationIDs.contains(
                    focusedApplication.id
                )
            )
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Target picker")
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if focusedApplicationID == nil {
                applicationList
            } else {
                Button {
                    focusedApplicationID = nil
                } label: {
                    Label("Applications", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                applicationDetail
            }
        }
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Applications")
                    .font(.headline)
                Spacer()
                Button {
                    model.refreshApplications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh applications and windows")
                .accessibilityLabel("Refresh applications and windows")
            }

            TextField("Find apps, windows, tabs, or websites", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onExitCommand {
                    if !searchText.isEmpty {
                        searchText = ""
                    } else {
                        isSearchFocused = false
                    }
                }

            if visibleApplications.isEmpty {
                ContentUnavailableView(
                    "No Targets Found",
                    systemImage: "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Open an application or add an installed application."
                            : "Try a different application, window, tab, or website."
                    )
                )
                .frame(minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleApplications, id: \.id) { application in
                            applicationRow(application)
                        }
                    }
                }
                .frame(minHeight: 170)
            }

            Button {
                model.addInstalledApplication()
            } label: {
                Label("Add Installed Application…", systemImage: "plus.app")
            }
            .buttonStyle(.bordered)
        }
    }

    private func applicationRow(
        _ application: ApplicationCatalogItem
    ) -> some View {
        let isFocused = focusedApplicationID == application.id
        let selectionCount = selectedTargetCount(
            forApplicationID: application.id
        )
        return Button {
            focusApplication(application)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: application.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(application.target.displayName)
                        .lineLimit(1)
                    if !application.isAvailable {
                        Text("Unavailable")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if !application.isRunning {
                        Text("Installed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectionCount > 0 {
                    Text("\(selectionCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.16), in: Capsule())
                        .accessibilityLabel(
                            "\(selectionCount) selected Target\(selectionCount == 1 ? "" : "s")"
                        )
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                isFocused ? Color.accentColor.opacity(0.16) : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(application.target.displayName)
        .accessibilityValue(
            selectionCount == 0
                ? "No Targets selected"
                : "\(selectionCount) Targets selected"
        )
        .accessibilityHint("Shows available target scopes without selecting the application")
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if let application = focusedApplication {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(nsImage: application.icon)
                            .resizable()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(application.target.displayName)
                                .font(.title3.weight(.semibold))
                            Text("Choose exactly what stays available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(
                        isOn: Binding(
                            get: {
                                model.selectedApplicationIDs.contains(
                                    application.id
                                )
                            },
                            set: {
                                model.setApplication(
                                    id: application.id,
                                    isSelected: $0
                                )
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow entire application")
                                .font(.headline)
                            Text("Includes every current and future window and all content.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        !application.isAvailable
                            && !model.selectedApplicationIDs.contains(
                                application.id
                            )
                    )
                    .padding(10)
                    .background(
                        model.selectedApplicationIDs.contains(application.id)
                            ? Color.orange.opacity(0.12)
                            : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                    nativeWindowSection(application)

                    if model.isChromeApplication(application.id) {
                        browserSection(application)
                    }
                }
                .padding(.trailing, 6)
            }
        } else {
            ContentUnavailableView(
                "Choose an Application",
                systemImage: "macwindow",
                description: Text(
                    "Inspect its application, window, and browser Target options."
                )
            )
            .frame(maxWidth: .infinity, minHeight: 250)
        }
    }

    private func nativeWindowSection(
        _ application: ApplicationCatalogItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Individual windows", systemImage: "macwindow.on.rectangle")
                .font(.headline)

            let windows = filteredNativeWindows(for: application.id)
            if windows.isEmpty {
                Text(
                    searchText.isEmpty
                        ? "No current macOS windows."
                        : "No windows match the search."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(windows, id: \.id) { window in
                    Toggle(
                        isOn: Binding(
                            get: {
                                model.selectedWindowIDs.contains(window.id)
                            },
                            set: {
                                model.setWindow(
                                    id: window.id,
                                    isSelected: $0
                                )
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(window.title)
                                .lineLimit(2)
                            Text("\(application.target.displayName) › Window")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        model.selectedApplicationIDs.contains(application.id)
                            || model.selectedBrowserApplicationIDs.contains(
                                application.id
                            )
                    )
                    .onHover {
                        model.highlightWindow(
                            id: window.id,
                            isHighlighted: $0
                        )
                    }
                }
            }
        }
    }

    private func browserSection(
        _ application: ApplicationCatalogItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label(
                "Chrome windows and tabs",
                systemImage: "rectangle.stack"
            )
            .font(.headline)

            if model.browserProfiles.isEmpty {
                Label(
                    "Chrome companion setup is required for window and tab Targets.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            let windows = filteredBrowserWindows(for: application.id)
            if windows.isEmpty {
                Text(
                    searchText.isEmpty
                        ? "No eligible Chrome windows are available."
                        : "No Chrome windows or tabs match the search."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(windows, id: \.targetIdentifier) { window in
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle(
                            isOn: Binding(
                                get: {
                                    model.selectedBrowserWindowIDs.contains(
                                        window.targetIdentifier
                                    )
                                },
                                set: {
                                    model.setBrowserWindow(
                                        id: window.targetIdentifier,
                                        isSelected: $0
                                    )
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(window.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    "\(model.browserProfileLabel(window.profileIdentifier)) › Browser Window"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(
                            model.selectedApplicationIDs.contains(application.id)
                        )
                        .onHover {
                            model.highlightBrowserWindow(
                                window,
                                isHighlighted: $0
                            )
                        }

                        ForEach(
                            filteredTabs(
                                for: application.id,
                                in: window
                            ),
                            id: \.targetIdentifier
                        ) { tab in
                            tabToggle(
                                tab,
                                applicationID: application.id,
                                parentWindowID: window.targetIdentifier
                            )
                            .padding(.leading, 18)
                        }
                    }
                    .padding(10)
                    .background(
                        Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
            }
        }
    }

    private func tabToggle(
        _ tab: BrowserTabTarget,
        applicationID: String,
        parentWindowID: TargetIdentifier
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                isOn: Binding(
                    get: {
                        model.selectedBrowserTabIDs.contains(
                            tab.targetIdentifier
                        )
                    },
                    set: {
                        model.setBrowserTab(
                            id: tab.targetIdentifier,
                            isSelected: $0
                        )
                    }
                )
            ) {
                HStack(spacing: 7) {
                    if let faviconPNGData = tab.faviconPNGData,
                       let favicon = NSImage(data: faviconPNGData) {
                        Image(nsImage: favicon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "globe")
                            .frame(width: 16, height: 16)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.title)
                            .lineLimit(1)
                        Text(
                            "\(tab.url.host ?? tab.url.absoluteString) › Tab"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            .toggleStyle(.checkbox)

            if model.selectedBrowserTabIDs.contains(tab.targetIdentifier) {
                Picker(
                    "Navigation scope",
                    selection: Binding(
                        get: {
                            model.browserNavigationScope(
                                for: tab.targetIdentifier
                            )
                        },
                        set: {
                            model.setBrowserNavigationScope(
                                $0,
                                for: tab.targetIdentifier
                            )
                        }
                    )
                ) {
                    Text("Current Website")
                        .tag(BrowserNavigationScope.currentWebsite)
                    Text("Exact Page")
                        .tag(BrowserNavigationScope.exactPage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.leading, 23)
            }
        }
        .disabled(
            model.selectedApplicationIDs.contains(applicationID)
                || model.selectedBrowserWindowIDs.contains(parentWindowID)
        )
    }

    private var selectedTargetsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Selected Targets", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.configuredTargets.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.configuredTargets.isEmpty {
                Text("Nothing selected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.configuredTargets, id: \.id) { target in
                            Label(
                                shortLabel(for: target),
                                systemImage: icon(for: target)
                            )
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: Capsule()
                            )
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private var focusedApplication: ApplicationCatalogItem? {
        guard let focusedApplicationID else {
            return nil
        }
        return model.applications.first { $0.id == focusedApplicationID }
    }

    private var visibleApplications: [ApplicationCatalogItem] {
        let trimmed = normalizedSearch
        return model.applications
            .filter { application in
                trimmed.isEmpty
                    || applicationMatchesSearch(application, search: trimmed)
            }
            .sorted { first, second in
                let firstHasSelection =
                    selectedTargetCount(forApplicationID: first.id) > 0
                let secondHasSelection =
                    selectedTargetCount(forApplicationID: second.id) > 0
                if firstHasSelection != secondHasSelection {
                    return firstHasSelection
                }
                return first.target.displayName.localizedCaseInsensitiveCompare(
                    second.target.displayName
                ) == .orderedAscending
            }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applicationMatchesSearch(
        _ application: ApplicationCatalogItem,
        search: String
    ) -> Bool {
        application.target.displayName.localizedCaseInsensitiveContains(search)
            || model.windows(for: application.id).contains {
                $0.title.localizedCaseInsensitiveContains(search)
            }
            || model.browserWindows(for: application.id).contains {
                $0.title.localizedCaseInsensitiveContains(search)
            }
            || model.browserTabs(for: application.id).contains {
                $0.title.localizedCaseInsensitiveContains(search)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(
                        search
                    )
            }
    }

    private func filteredNativeWindows(
        for applicationID: String
    ) -> [WindowTarget] {
        guard !normalizedSearch.isEmpty else {
            return model.windows(for: applicationID)
        }
        return model.windows(for: applicationID).filter {
            $0.title.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }

    private func filteredBrowserWindows(
        for applicationID: String
    ) -> [BrowserWindowTarget] {
        guard !normalizedSearch.isEmpty else {
            return model.browserWindows(for: applicationID)
        }
        return model.browserWindows(for: applicationID).filter { window in
            window.title.localizedCaseInsensitiveContains(normalizedSearch)
                || model.browserTabs(for: applicationID).contains { tab in
                    tab.profileIdentifier == window.profileIdentifier
                        && tab.windowIdentifier == window.windowIdentifier
                        && (
                            tab.title.localizedCaseInsensitiveContains(
                                normalizedSearch
                            )
                                || tab.url.absoluteString
                                    .localizedCaseInsensitiveContains(
                                        normalizedSearch
                                    )
                        )
                }
        }
    }

    private func filteredTabs(
        for applicationID: String,
        in window: BrowserWindowTarget
    ) -> [BrowserTabTarget] {
        model.browserTabs(for: applicationID).filter { tab in
            tab.profileIdentifier == window.profileIdentifier
                && tab.windowIdentifier == window.windowIdentifier
                && (
                    normalizedSearch.isEmpty
                        || tab.title.localizedCaseInsensitiveContains(
                            normalizedSearch
                        )
                        || tab.url.absoluteString
                            .localizedCaseInsensitiveContains(normalizedSearch)
                )
        }
    }

    private func selectedTargetCount(
        forApplicationID applicationID: String
    ) -> Int {
        model.configuredTargets.count {
            $0.bundleIdentifier == applicationID
        }
    }

    private func chooseInitialApplication() {
        guard focusedApplication == nil
                || !visibleApplications.contains(where: {
                    $0.id == focusedApplicationID
                })
        else {
            return
        }
        let selectedApplicationID = visibleApplications.first {
            selectedTargetCount(forApplicationID: $0.id) > 0
        }?.id
        let nextApplicationID = selectedApplicationID
            ?? visibleApplications.first?.id
        focusedApplicationID = nextApplicationID
        if let application = model.applications.first(where: {
            $0.id == nextApplicationID
        }) {
            refreshWindowInventory(for: application)
        }
    }

    private func focusApplication(_ application: ApplicationCatalogItem) {
        focusedApplicationID = application.id
        refreshWindowInventory(for: application)
    }

    private func refreshWindowInventory(
        for application: ApplicationCatalogItem
    ) {
        guard application.isRunning else {
            return
        }
        model.refreshWindows(for: application.id)
    }

    private func refreshSearchableWindowInventory() {
        for application in model.applications where application.isRunning {
            model.refreshWindows(for: application.id)
        }
    }

    private func moveApplicationFocus(
        by offset: Int
    ) -> KeyPress.Result {
        guard !visibleApplications.isEmpty else {
            return .ignored
        }
        let currentIndex = visibleApplications.firstIndex {
            $0.id == focusedApplicationID
        } ?? (offset > 0 ? -1 : visibleApplications.count)
        let nextIndex = min(
            max(currentIndex + offset, 0),
            visibleApplications.count - 1
        )
        focusApplication(visibleApplications[nextIndex])
        return .handled
    }

    private func shortLabel(for target: SessionTarget) -> String {
        switch target {
        case let .application(application):
            application.displayName
        case let .window(window):
            window.title
        case let .browserWindow(window):
            window.title
        case let .browserTab(tab):
            tab.title
        }
    }

    private func icon(for target: SessionTarget) -> String {
        switch target {
        case .application:
            "app"
        case .window:
            "macwindow"
        case .browserWindow:
            "macwindow.on.rectangle"
        case .browserTab:
            "rectangle.stack"
        }
    }
}
