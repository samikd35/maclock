import SwiftUI

struct FloatingTimerView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var preferences: FloatingTimerPreferenceModel

    var body: some View {
        HStack(spacing: preferences.value.isCollapsed ? 8 : 12) {
            Image(systemName: "timer")
                .foregroundStyle(.tint)

            if preferences.value.isCollapsed {
                Text(model.formattedRemainingTime)
                    .font(.headline.monospacedDigit())
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus session")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(model.formattedRemainingTime)
                        .font(.title2.bold().monospacedDigit())
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
            .help(preferences.value.isCollapsed ? "Expand timer" : "Collapse timer")
            .accessibilityLabel(
                preferences.value.isCollapsed ? "Expand timer" : "Collapse timer"
            )

            Button {
                preferences.setVisible(false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide floating timer")
            .accessibilityLabel("Hide floating timer")
        }
        .padding(.horizontal, preferences.value.isCollapsed ? 10 : 14)
        .padding(.vertical, preferences.value.isCollapsed ? 8 : 10)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("StayPane floating focus timer")
    }
}
