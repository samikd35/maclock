import Testing
@testable import StayPane

@Test func setupHealthMakesRequiredDependenciesBlockingAndRecoveryOptional() {
    #expect(
        SetupHealthSummary.resolve(
            accessibilityReady: false,
            browserTargetsSelected: false,
            browserReady: false,
            recoveryReady: true
        ).severity == .blocking
    )
    #expect(
        SetupHealthSummary.resolve(
            accessibilityReady: true,
            browserTargetsSelected: true,
            browserReady: false,
            recoveryReady: true
        ).severity == .blocking
    )
    #expect(
        SetupHealthSummary.resolve(
            accessibilityReady: true,
            browserTargetsSelected: false,
            browserReady: false,
            recoveryReady: false
        ).severity == .attention
    )
    #expect(
        SetupHealthSummary.resolve(
            accessibilityReady: true,
            browserTargetsSelected: false,
            browserReady: false,
            recoveryReady: true
        ).severity == .ready
    )
}
