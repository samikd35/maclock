import Testing
@testable import StayPane

@Test func durationComponentsConvertBetweenClockFieldsAndSeconds() {
    let components = DurationComponents(seconds: 5_425)

    #expect(components.hours == 1)
    #expect(components.minutes == 30)
    #expect(components.seconds == 25)
    #expect(components.totalSeconds == 5_425)
}

@Test func durationComponentsEnforceTheSessionDurationContract() {
    #expect(DurationComponents(hours: 0, minutes: 0, seconds: 10).validationError == nil)
    #expect(DurationComponents(hours: 24, minutes: 0, seconds: 0).validationError == nil)
    #expect(DurationComponents(hours: 0, minutes: 0, seconds: 9).validationError != nil)
    #expect(DurationComponents(hours: 24, minutes: 0, seconds: 1).validationError != nil)
    #expect(DurationComponents(hours: 1, minutes: 60, seconds: 0).validationError != nil)
    #expect(DurationComponents(hours: 1, minutes: 0, seconds: 60).validationError != nil)
}
