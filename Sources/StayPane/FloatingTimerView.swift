import SwiftUI

struct FloatingTimerView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var preferences: FloatingTimerPreferenceModel

    var body: some View {
        let metrics = FloatingTimerLayoutMetrics.resolve(
            size: preferences.value.size,
            isCollapsed: preferences.value.isCollapsed
        )
        return HStack(spacing: metrics.spacing) {
            dragHandle(fontSize: metrics.iconFontSize)

            if preferences.value.isCollapsed {
                Text(model.formattedRemainingTime)
                    .font(
                        .system(
                            size: metrics.timeFontSize,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: metrics.iconFontSize))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(model.formattedRemainingTime)
                        .font(
                            .system(
                                size: metrics.timeFontSize,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                sizeControls
            }

            Button {
                preferences.toggleCollapsed()
            } label: {
                Image(
                    systemName: preferences.value.isCollapsed
                        ? "arrow.up.left.and.arrow.down.right"
                        : "arrow.down.right.and.arrow.up.left"
                )
            }
            .buttonStyle(.plain)
            .help(
                preferences.value.isCollapsed
                    ? "Expand Floating Timer"
                    : "Collapse Floating Timer"
            )
            .accessibilityLabel(
                preferences.value.isCollapsed
                    ? "Expand Floating Timer"
                    : "Collapse Floating Timer"
            )

            Button {
                preferences.setVisible(false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide Floating Timer")
            .accessibilityLabel("Hide Floating Timer")
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(
            width: metrics.contentSize.width,
            height: metrics.contentSize.height
        )
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("StayPane Floating Timer")
        .accessibilityHint(
            "Drag the handle to move. Use the Move Floating Timer to Top Right action for keyboard or VoiceOver placement."
        )
        .accessibilityAction(
            named: Text("Move Floating Timer to Top Right")
        ) {
            preferences.resetPosition()
        }
    }

    private var sizeControls: some View {
        HStack(spacing: 5) {
            Button {
                preferences.decreaseSize()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .disabled(!preferences.canDecreaseSize)
            .help("Decrease Floating Timer Size")
            .accessibilityLabel("Decrease Floating Timer Size")

            Button {
                preferences.increaseSize()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(!preferences.canIncreaseSize)
            .help("Increase Floating Timer Size")
            .accessibilityLabel("Increase Floating Timer Size")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Floating Timer size: \(preferences.value.size.displayName)"
        )
    }

    private func dragHandle(fontSize: CGFloat) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: fontSize))
            .foregroundStyle(.secondary)
            .help("Drag to Move Floating Timer")
            .accessibilityHidden(true)
    }
}
