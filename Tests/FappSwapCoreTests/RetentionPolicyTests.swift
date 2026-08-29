import Testing
@testable import FappSwapCore

@Test func retentionDaysCarryTheirDayCountAsRawValue() {
    #expect(RetentionDays.one.rawValue == 1)
    #expect(RetentionDays.seven.rawValue == 7)
    #expect(RetentionDays.thirty.rawValue == 30)
    #expect(RetentionDays.ninety.rawValue == 90)
    #expect(RetentionDays.year.rawValue == 365)
    #expect(RetentionDays.allCases.count == 5)
    #expect(RetentionDays(rawValue: 12) == nil)
}

@Test func retentionDaysHaveLabels() {
    #expect(RetentionDays.one.label == "1 day")
    #expect(RetentionDays.seven.label == "7 days")
    #expect(RetentionDays.year.label == "1 year")
}

@Test func retentionPolicyDefaultsToTheDocumentedCaps() {
    let policy = RetentionPolicy(days: .thirty)
    #expect(policy.maxItems == 1_000)
    #expect(policy.maxImageBytes == 250 * 1_024 * 1_024)
    #expect(RetentionPolicy.maxTextBytes == 1_024 * 1_024)
}
