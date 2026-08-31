import Testing
@testable import AirlineEmpireCore

/// `Money.compact` — the rendering Core's own rejection messages use.
///
/// BUG-037: the market showed "Need 110000000 for this aircraft" under a
/// blocked offer, because Core interpolated `cents / 100` into the message.
/// It survived every existing check — the code was right, the copy mapped,
/// the tests passed — and was caught by a screenshot. This pins the fix, and
/// pins that no rejection message can regress to raw cents.
@Suite("Money formatting")
struct MoneyFormattingTests {

    @Test func compactMatchesTheAppsScale() {
        #expect(Money.dollars(110_000_000).compact == "$110.0M")
        #expect(Money.dollars(53_700_000).compact == "$53.7M")
        #expect(Money.dollars(790_000).compact == "$790k")
        #expect(Money.dollars(9_999).compact == "$9,999")
        #expect(Money.dollars(1_234).compact == "$1,234")
        #expect(Money.dollars(0).compact == "$0")
        #expect(Money.dollars(2_500_000_000).compact == "$2.50B")
        #expect(Money.dollars(-53_700_000).compact == "−$53.7M")
    }

    /// No rejection a blocked market command emits may contain a run of raw
    /// digits long enough to be an unformatted balance. Seven digits starts
    /// at 1,000,000 — nothing below that appears unformatted, because
    /// `compact` groups from four digits up.
    @Test func rejectionMessagesCarryNoRawBalances() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(10))
        let typeCode = catalog.aircraftTypes.keys.sorted { $0.raw < $1.raw }.first!
        let commands: [any Command] = [
            BuyNewAircraftCommand(buyer: airline, type: typeCode),
            BuyUsedAircraftCommand(buyer: airline, type: typeCode, ageYears: 8),
            LeaseAircraftCommand(lessee: airline, type: typeCode, termMonths: 60),
        ]
        for command in commands {
            guard case .rejected(let rejection) = engine.applyNow(command) else {
                Issue.record("Expected \(command.self) to be refused on $10 cash")
                continue
            }
            let digits = rejection.message.filter(\.isNumber)
            let longestRun = rejection.message
                .split(whereSeparator: { !$0.isNumber })
                .map(\.count).max() ?? 0
            #expect(longestRun < 7,
                    "\(rejection.code): \"\(rejection.message)\" carries a raw number (\(digits))")
        }
    }
}
