import CoreGraphics

struct FloatingTimerLayoutMetrics: Equatable {
    let contentSize: CGSize
    let timeFontSize: CGFloat
    let iconFontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat

    static func resolve(
        scale: Double,
        isCollapsed: Bool
    ) -> FloatingTimerLayoutMetrics {
        let clampedScale = min(max(scale, 0), 1)
        let anchors = isCollapsed
            ? collapsedAnchors
            : expandedAnchors
        return interpolate(anchors, at: clampedScale)
    }

    private struct Anchors {
        let minimum: FloatingTimerLayoutMetrics
        let medium: FloatingTimerLayoutMetrics
        let maximum: FloatingTimerLayoutMetrics
    }

    private static let expandedAnchors = Anchors(
        minimum: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 280, height: 58),
            timeFontSize: 22,
            iconFontSize: 14,
            horizontalPadding: 10,
            verticalPadding: 7,
            spacing: 8
        ),
        medium: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 330, height: 70),
            timeFontSize: 28,
            iconFontSize: 17,
            horizontalPadding: 14,
            verticalPadding: 9,
            spacing: 10
        ),
        maximum: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 520, height: 116),
            timeFontSize: 52,
            iconFontSize: 27,
            horizontalPadding: 26,
            verticalPadding: 15,
            spacing: 16
        )
    )

    private static let collapsedAnchors = Anchors(
        minimum: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 220, height: 38),
            timeFontSize: 16,
            iconFontSize: 11,
            horizontalPadding: 9,
            verticalPadding: 6,
            spacing: 7
        ),
        medium: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 250, height: 46),
            timeFontSize: 19,
            iconFontSize: 13,
            horizontalPadding: 10,
            verticalPadding: 7,
            spacing: 8
        ),
        maximum: FloatingTimerLayoutMetrics(
            contentSize: CGSize(width: 390, height: 76),
            timeFontSize: 34,
            iconFontSize: 20,
            horizontalPadding: 18,
            verticalPadding: 11,
            spacing: 12
        )
    )

    private static func interpolate(
        _ anchors: Anchors,
        at scale: Double
    ) -> FloatingTimerLayoutMetrics {
        if scale <= 0.5 {
            return interpolate(
                from: anchors.minimum,
                to: anchors.medium,
                progress: scale / 0.5
            )
        }
        return interpolate(
            from: anchors.medium,
            to: anchors.maximum,
            progress: (scale - 0.5) / 0.5
        )
    }

    private static func interpolate(
        from start: FloatingTimerLayoutMetrics,
        to end: FloatingTimerLayoutMetrics,
        progress: Double
    ) -> FloatingTimerLayoutMetrics {
        let amount = CGFloat(progress)
        return FloatingTimerLayoutMetrics(
            contentSize: CGSize(
                width: mix(
                    start.contentSize.width,
                    end.contentSize.width,
                    amount
                ),
                height: mix(
                    start.contentSize.height,
                    end.contentSize.height,
                    amount
                )
            ),
            timeFontSize: mix(start.timeFontSize, end.timeFontSize, amount),
            iconFontSize: mix(start.iconFontSize, end.iconFontSize, amount),
            horizontalPadding: mix(
                start.horizontalPadding,
                end.horizontalPadding,
                amount
            ),
            verticalPadding: mix(
                start.verticalPadding,
                end.verticalPadding,
                amount
            ),
            spacing: mix(start.spacing, end.spacing, amount)
        )
    }

    private static func mix(
        _ start: CGFloat,
        _ end: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        start + ((end - start) * progress)
    }
}

enum FloatingTimerResizeGeometry {
    static func scale(
        forProposedSize proposedSize: CGSize,
        currentSize: CGSize,
        currentScale: Double,
        isCollapsed: Bool
    ) -> Double {
        let minimum = FloatingTimerLayoutMetrics.resolve(
            scale: 0,
            isCollapsed: isCollapsed
        ).contentSize
        let medium = FloatingTimerLayoutMetrics.resolve(
            scale: 0.5,
            isCollapsed: isCollapsed
        ).contentSize
        let maximum = FloatingTimerLayoutMetrics.resolve(
            scale: 1,
            isCollapsed: isCollapsed
        ).contentSize

        let widthRange = max(1, maximum.width - minimum.width)
        let heightRange = max(1, maximum.height - minimum.height)
        let normalizedWidthDelta =
            abs(proposedSize.width - currentSize.width) / widthRange
        let normalizedHeightDelta =
            abs(proposedSize.height - currentSize.height) / heightRange

        if normalizedWidthDelta < 0.0001,
           normalizedHeightDelta < 0.0001
        {
            return min(max(currentScale, 0), 1)
        }

        if normalizedWidthDelta >= normalizedHeightDelta {
            return inverseInterpolate(
                proposedSize.width,
                minimum: minimum.width,
                medium: medium.width,
                maximum: maximum.width
            )
        }
        return inverseInterpolate(
            proposedSize.height,
            minimum: minimum.height,
            medium: medium.height,
            maximum: maximum.height
        )
    }

    private static func inverseInterpolate(
        _ value: CGFloat,
        minimum: CGFloat,
        medium: CGFloat,
        maximum: CGFloat
    ) -> Double {
        let scale: CGFloat
        if value <= medium {
            scale = 0.5 * ((value - minimum) / max(1, medium - minimum))
        } else {
            scale = 0.5
                + 0.5 * ((value - medium) / max(1, maximum - medium))
        }
        return Double(min(max(scale, 0), 1))
    }
}
