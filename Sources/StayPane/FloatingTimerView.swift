import SwiftUI

struct FloatingTimerView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var preferences: FloatingTimerPreferenceModel
    @State private var isHovering = false

    var body: some View {
        let metrics = FloatingTimerLayoutMetrics.resolve(
            scale: preferences.value.scale,
            isCollapsed: preferences.value.isCollapsed
        )
        return styledTimer(metrics: metrics)
    }

    private func styledTimer(
        metrics: FloatingTimerLayoutMetrics
    ) -> some View {
        timerContents(metrics: metrics)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        timerBorderColor,
                        lineWidth: isHovering ? 1.5 : 1
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                resizeAffordance(metrics: metrics)
            }
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("StayPane Floating Timer")
            .accessibilityValue(
                "\(model.formattedRemainingTime) remaining, \(preferences.sizeDescription) size"
            )
            .accessibilityHint(
                "Drag the handle to move or resize from an edge. Use adjustable actions to change size."
            )
            .accessibilityAdjustableAction { direction in
                adjustSize(direction)
            }
            .accessibilityAction(
                named: Text("Move Floating Timer to Top Right")
            ) {
                preferences.resetPosition()
            }
    }

    private func timerContents(
        metrics: FloatingTimerLayoutMetrics
    ) -> some View {
        HStack(spacing: metrics.spacing) {
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
    }

    @ViewBuilder
    private func resizeAffordance(
        metrics: FloatingTimerLayoutMetrics
    ) -> some View {
        if isHovering {
            Image(systemName: "arrow.down.right")
                .font(.system(size: max(8, metrics.iconFontSize * 0.55)))
                .foregroundStyle(.secondary)
                .padding(max(5, metrics.verticalPadding * 0.7))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var timerBorderColor: Color {
        isHovering
            ? Color.accentColor.opacity(0.7)
            : Color(nsColor: .separatorColor).opacity(0.45)
    }

    private func adjustSize(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            preferences.increaseSize()
        case .decrement:
            preferences.decreaseSize()
        @unknown default:
            break
        }
    }

    private func dragHandle(fontSize: CGFloat) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: fontSize))
            .foregroundStyle(.secondary)
            .help("Drag to Move Floating Timer")
            .accessibilityHidden(true)
    }
}
