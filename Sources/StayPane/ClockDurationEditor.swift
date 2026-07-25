import AppKit
import SwiftUI

struct ClockDurationEditor: View {
    @Binding var totalSeconds: Int
    @Binding var validationMessage: String?

    @State private var hoursText: String
    @State private var minutesText: String
    @State private var secondsText: String

    init(
        totalSeconds: Binding<Int>,
        validationMessage: Binding<String?>
    ) {
        _totalSeconds = totalSeconds
        _validationMessage = validationMessage
        let components = DurationComponents(seconds: totalSeconds.wrappedValue)
        _hoursText = State(initialValue: Self.format(components.hours))
        _minutesText = State(initialValue: Self.format(components.minutes))
        _secondsText = State(initialValue: Self.format(components.seconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                component(
                    label: "hr",
                    text: $hoursText,
                    range: 0...24
                )
                separator
                component(
                    label: "min",
                    text: $minutesText,
                    range: 0...59
                )
                separator
                component(
                    label: "sec",
                    text: $secondsText,
                    range: 0...59
                )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach([600, 1_500, 1_800, 3_600], id: \.self) { seconds in
                    Button(StayPaneModel.formatPreset(seconds: seconds)) {
                        apply(seconds: seconds)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Sets the Session duration")
                }
                Spacer()
                Button("Reset to 30m") {
                    apply(seconds: 1_800)
                }
                .buttonStyle(.link)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid duration. \(validationMessage)")
            } else {
                Text("Choose from 00:00:10 through 24:00:00.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: hoursText) { _, _ in validateDraft() }
        .onChange(of: minutesText) { _, _ in validateDraft() }
        .onChange(of: secondsText) { _, _ in validateDraft() }
        .onChange(of: totalSeconds) { _, newValue in
            guard draftComponents?.validTotalSeconds != newValue else {
                return
            }
            let components = DurationComponents(seconds: newValue)
            hoursText = Self.format(components.hours)
            minutesText = Self.format(components.minutes)
            secondsText = Self.format(components.seconds)
            validationMessage = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session duration")
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 38, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.bottom, 7)
            .accessibilityHidden(true)
    }

    private func component(
        label: String,
        text: Binding<String>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            DurationComponentField(
                label: label,
                text: text,
                range: range
            )
            .frame(width: 82, height: 54)
            .accessibilityLabel(label)
            .accessibilityValue(text.wrappedValue)
            .accessibilityAdjustableAction { direction in
                let offset: Int
                switch direction {
                case .increment:
                    offset = 1
                case .decrement:
                    offset = -1
                @unknown default:
                    return
                }
                let current = Int(text.wrappedValue) ?? range.lowerBound
                let adjusted = min(
                    max(current + offset, range.lowerBound),
                    range.upperBound
                )
                text.wrappedValue = Self.format(adjusted)
            }
        }
    }

    private var draftComponents: DurationComponents? {
        guard let hours = Int(hoursText),
              let minutes = Int(minutesText),
              let seconds = Int(secondsText)
        else {
            return nil
        }
        return DurationComponents(
            hours: hours,
            minutes: minutes,
            seconds: seconds
        )
    }

    private func validateDraft() {
        guard let components = draftComponents else {
            validationMessage = "Enter hours, minutes, and seconds."
            return
        }
        validationMessage = components.validationError
        if let seconds = components.validTotalSeconds {
            totalSeconds = seconds
        }
    }

    private func apply(seconds: Int) {
        let components = DurationComponents(seconds: seconds)
        hoursText = Self.format(components.hours)
        minutesText = Self.format(components.minutes)
        secondsText = Self.format(components.seconds)
        validationMessage = nil
        totalSeconds = seconds
    }

    private static func format(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

private struct DurationComponentField: NSViewRepresentable {
    let label: String
    @Binding var text: String
    let range: ClosedRange<Int>

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClockSegmentTextField {
        let field = ClockSegmentTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(
            ofSize: 36,
            weight: .regular
        )
        field.focusRingType = .exterior
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.backgroundColor = .controlBackgroundColor
        field.setAccessibilityLabel(label)
        field.onStep = { [weak coordinator = context.coordinator] offset in
            coordinator?.step(by: offset)
        }
        return field
    }

    func updateNSView(
        _ nsView: ClockSegmentTextField,
        context: Context
    ) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DurationComponentField

        init(parent: DurationComponentField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            field.currentEditor()?.selectedRange = NSRange(
                location: 0,
                length: field.stringValue.utf16.count
            )
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            let digits = field.stringValue.filter(\.isNumber)
            let limited = String(digits.prefix(2))
            if field.stringValue != limited {
                field.stringValue = limited
            }
            parent.text = limited
            if limited.count == 2 {
                DispatchQueue.main.async {
                    field.window?.selectNextKeyView(field)
                }
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let value = Int(field.stringValue)
            else {
                return
            }
            let normalized = String(
                format: "%02d",
                min(max(value, parent.range.lowerBound), parent.range.upperBound)
            )
            field.stringValue = normalized
            parent.text = normalized
        }

        func step(by offset: Int) {
            let current = Int(parent.text) ?? parent.range.lowerBound
            let adjusted = min(
                max(current + offset, parent.range.lowerBound),
                parent.range.upperBound
            )
            parent.text = String(format: "%02d", adjusted)
        }
    }
}

private final class ClockSegmentTextField: NSTextField {
    var onStep: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            onStep?(1)
        case 125:
            onStep?(-1)
        default:
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= 0.5 else {
            super.scrollWheel(with: event)
            return
        }
        onStep?(event.scrollingDeltaY > 0 ? 1 : -1)
    }
}
