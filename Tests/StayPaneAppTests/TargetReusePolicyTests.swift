import Testing
@testable import StayPane

@Test func targetReusePolicyRetainsOnlyTargetsThatStillExist() {
    let result = TargetReusePolicy.partition(
        previousIDs: ["app", "window", "tab"],
        availableIDs: ["app", "tab", "new-window"]
    )

    #expect(result.retained == ["app", "tab"])
    #expect(result.dropped == ["window"])
}
