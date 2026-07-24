import CoreGraphics

struct FloatingTimerLayoutMetrics: Equatable {
    let contentSize: CGSize
    let timeFontSize: CGFloat
    let iconFontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat

    static func resolve(
        size: FloatingTimerSize,
        isCollapsed: Bool
    ) -> FloatingTimerLayoutMetrics {
        switch (size, isCollapsed) {
        case (.small, false):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 280, height: 58),
                timeFontSize: 22,
                iconFontSize: 14,
                horizontalPadding: 10,
                verticalPadding: 7,
                spacing: 8
            )
        case (.medium, false):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 330, height: 70),
                timeFontSize: 28,
                iconFontSize: 17,
                horizontalPadding: 14,
                verticalPadding: 9,
                spacing: 10
            )
        case (.large, false):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 400, height: 88),
                timeFontSize: 38,
                iconFontSize: 21,
                horizontalPadding: 18,
                verticalPadding: 11,
                spacing: 12
            )
        case (.small, true):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 220, height: 38),
                timeFontSize: 16,
                iconFontSize: 11,
                horizontalPadding: 9,
                verticalPadding: 6,
                spacing: 7
            )
        case (.medium, true):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 250, height: 46),
                timeFontSize: 19,
                iconFontSize: 13,
                horizontalPadding: 10,
                verticalPadding: 7,
                spacing: 8
            )
        case (.large, true):
            FloatingTimerLayoutMetrics(
                contentSize: CGSize(width: 300, height: 58),
                timeFontSize: 25,
                iconFontSize: 16,
                horizontalPadding: 13,
                verticalPadding: 9,
                spacing: 10
            )
        }
    }
}
