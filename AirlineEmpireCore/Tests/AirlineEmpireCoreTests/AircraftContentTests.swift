import Testing
@testable import AirlineEmpireCore

/// Aircraft roles, seat efficiency, and what the shipped catalog actually
/// contains (MASTER PROMPT 5 §10, §38, §39).
///
/// §38 asks for a content audit and §39 asks whether each type occupies a
/// real strategic niche — and explicitly says to document rather than rebalance
/// without evidence. Two of these tests are therefore characterization tests:
/// they pin what the catalog is like today, so that a retune is a deliberate,
/// visible change rather than something that quietly makes a document wrong.
/// `docs/AIRCRAFT.md` had already drifted that way before they existed.
@Suite("Aircraft roles and content")
struct AircraftContentTests {

    private func specs() throws -> [AircraftTypeSpec] {
        let catalog = try ContentCatalog.loadBundled()
        return catalog.orderedAircraftTypeCodes.compactMap { catalog.aircraftType($0) }
    }

    @Test("Every type has a role, and every role is reachable")
    func rolesCoverTheCatalog() throws {
        let all = try specs()
        #expect(!all.isEmpty)
        let used = Set(all.map(\.role))
        // A role no aircraft has is a label the player will never see and a
        // branch nothing tests.
        #expect(used == Set(AircraftRole.allCases),
                "unused roles: \(Set(AircraftRole.allCases).subtracting(used))")
    }

    @Test("Role follows from category alone, which is the honest claim")
    func roleIsAFunctionOfCategory() throws {
        // Stated as a test rather than left implicit, because the doc comment
        // on `AircraftRole` admits the mapping is one-to-one. If a later
        // catalog splits a category into two uses this fails, which is the
        // right moment to revisit both the enum and that comment.
        var seen: [AircraftCategory: AircraftRole] = [:]
        for spec in try specs() {
            if let existing = seen[spec.category] {
                #expect(existing == spec.role,
                        "\(spec.code.raw) breaks the one-role-per-category assumption")
            }
            seen[spec.category] = spec.role
        }
    }

    @Test("Seat efficiency bands land where the fuel figures say they should")
    func efficiencyBandsMatchTheNumbers() throws {
        let catalog = try ContentCatalog.loadBundled()
        let all = try specs()
        let best = try #require(catalog.bestFuelBurnPerSeatKm)

        for spec in all {
            let band = try #require(catalog.seatEfficiency(of: spec))
            let ratio = spec.fuelBurnPerSeatKm / best
            switch band {
            case .best: #expect(ratio < 1.15)
            case .strong: #expect(ratio >= 1.15 && ratio < 1.35)
            case .moderate: #expect(ratio >= 1.35 && ratio < 1.6)
            case .thirsty: #expect(ratio >= 1.6)
            }
        }
        // At least one type must define the floor, or the band is measuring
        // against something no aircraft achieves.
        #expect(all.contains { catalog.seatEfficiency(of: $0) == .best })
    }

    @Test("Small aircraft are the thirsty ones per seat, not the big ones")
    func regionalAircraftAreThirstiestPerSeat() throws {
        let catalog = try ContentCatalog.loadBundled()
        let all = try specs()
        func mean(_ category: AircraftCategory) -> Double {
            let values = all.filter { $0.category == category }.map(\.fuelBurnPerSeatKm)
            return values.reduce(0, +) / Double(max(1, values.count))
        }
        // The fact the market now leans on. It is counter-intuitive enough
        // that it is worth a test: a player reading raw `fuelBurnKgPerKm`
        // would conclude the opposite, because a widebody's total burn is
        // several times a turboprop's.
        #expect(mean(.turboprop) > mean(.largeNarrowbody))
        #expect(mean(.regionalJet) > mean(.narrowbody))
        #expect(mean(.turboprop) / mean(.largeNarrowbody) > 1.5,
                "the cross-category gap is the whole basis for the efficiency band")
    }

    // MARK: Characterization — what the catalog is, so drift is visible

    @Test("Within a category, types differ by size and reach, not by economy")
    func withinCategoryEconomySpreadIsSmall() throws {
        let all = try specs()
        var worst = 0.0
        var worstCategory = AircraftCategory.turboprop
        for category in AircraftCategory.allCases {
            let burns = all.filter { $0.category == category }.map(\.fuelBurnPerSeatKm)
            guard let low = burns.min(), let high = burns.max(), low > 0,
                  burns.count > 1 else { continue }
            let spread = high / low - 1
            if spread > worst { worst = spread; worstCategory = category }
        }
        // docs/AIRCRAFT.md described "±15% per-type personality
        // (cheaper-thirstier vs pricier-frugal)". The catalog does not have
        // that: the largest within-category spread is about 4.5%, and most
        // are under 2%. Types are separated by seats and range, and are near
        // enough identical in economic character.
        //
        // This is pinned at 10% — comfortably above what ships, comfortably
        // below what was documented — so that genuinely introducing the
        // intended personality fails here and prompts the doc to be corrected
        // with it, instead of the two silently disagreeing again.
        #expect(worst < 0.10,
                """
                within-category burn/seat spread reached \(Int(worst * 100))% \
                (worst: \(worstCategory)). If this is intentional, update \
                docs/AIRCRAFT.md — it previously claimed ±15% when the catalog \
                had under 5%.
                """)
    }

    @Test("NA160 is beaten by MR180 on economics and saved only by its price")
    func na160IsCheapToBuyAndNothingElse() throws {
        let catalog = try ContentCatalog.loadBundled()
        let na160 = try #require(catalog.aircraftType("NA160"))
        let mr180 = try #require(catalog.aircraftType("MR180"))

        // The one type in the catalog a peer beats on every efficiency
        // measure: MR180 has more seats, more range, a lower cost per seat
        // and a lower burn per seat. Recorded rather than rebalanced — §38
        // says not to retune casually, and NA160 is not pointless: it is
        // materially cheaper to *buy*, which is exactly the constraint a new
        // airline is under. That is a real reason to own one, and it is the
        // only one.
        #expect(mr180.seats > na160.seats)
        #expect(mr180.rangeKm > na160.rangeKm)
        #expect(mr180.fuelBurnPerSeatKm < na160.fuelBurnPerSeatKm)
        #expect(mr180.listPrice.cents / Int64(mr180.seats)
                < na160.listPrice.cents / Int64(na160.seats))
        // ...and the saving grace.
        #expect(na160.listPrice.cents < mr180.listPrice.cents,
                "if NA160 stops being the cheaper aircraft it has no remaining niche")
    }
}

/// Narrowing a large fleet (MASTER PROMPT 5 §17, §37).
///
/// The screen has to work at one aircraft and at two hundred. These test the
/// property that matters at scale — that a filter partitions the fleet rather
/// than losing rows — because "filters dropping aircraft" is on §46's list of
/// things to hunt for, and it is the kind of bug that only shows up when the
/// fleet is too big to count by eye.
@Suite("Fleet filtering")
struct FleetFilterTests {

    private func fleet(seed: UInt64 = 3131, aircraft: Int = 24) async throws
        -> ([FleetCardModel], ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Filter Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(4_000_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: 1)

        // A mixed fleet: several types, some leased, some still on order, and
        // some flying — so every branch of the filter has something to match.
        let codes = catalog.orderedAircraftTypeCodes.filter { code in
            guard let spec = catalog.aircraftType(code) else { return false }
            return [.turboprop, .regionalJet, .narrowbody].contains(spec.category)
        }
        for index in 0..<aircraft {
            let code = codes[index % codes.count]
            if index % 3 == 0 {
                _ = await session.submit(LeaseAircraftCommand(
                    lessee: player, type: code, termMonths: 48))
            } else if index % 3 == 1 {
                _ = await session.submit(BuyNewAircraftCommand(buyer: player, type: code))
            } else {
                _ = await session.submit(BuyUsedAircraftCommand(
                    buyer: player, type: code, ageYears: 6))
            }
        }
        var state = await session.snapshot
        // Fly a few of them.
        let idle = state.fleet(of: player).filter { $0.status.isActive }.prefix(4)
        for (index, market) in state.marketOpportunities(catalog: catalog, limit: 4).enumerated()
        where index < idle.count {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 2,
                ticketPrice: market.referenceFare))
            state = await session.snapshot
            if let route = state.routes(of: player).last {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id,
                    aircraftID: Array(idle)[index].id))
            }
        }
        state = await session.snapshot
        return (state.fleetCards(for: player, catalog: catalog), catalog)
    }

    @Test("The status filters partition the fleet exactly once")
    func statusFiltersPartitionTheFleet() async throws {
        let (cards, _) = try await fleet()
        try #require(cards.count > 10, "fixture too small to be evidence")

        // Every aircraft is in exactly one of the four status buckets. A gap
        // means a filter loses rows; an overlap means a count double-reports.
        var counted = 0
        for status in FleetFilter.Status.allCases where status != .all {
            counted += cards.matching(FleetFilter(status: status)).count
        }
        #expect(counted == cards.count,
                "status buckets summed to \(counted) of \(cards.count) aircraft")
    }

    @Test("Ownership splits the fleet in two, with nothing left over")
    func ownershipPartitions() async throws {
        let (cards, _) = try await fleet()
        let owned = cards.matching(FleetFilter(ownership: .owned)).count
        let leased = cards.matching(FleetFilter(ownership: .leased)).count
        #expect(owned + leased == cards.count)
        #expect(owned > 0 && leased > 0, "fixture must contain both to be evidence")
    }

    @Test("Category filters only offer categories the player actually owns")
    func categoriesPresentAreTheOnesOffered() async throws {
        let (cards, _) = try await fleet()
        let present = cards.presentCategories
        #expect(!present.isEmpty)
        for category in present {
            #expect(!cards.matching(FleetFilter(category: category)).isEmpty,
                    "\(category) is offered but matches nothing")
        }
        for category in AircraftCategory.allCases where !present.contains(category) {
            #expect(cards.matching(FleetFilter(category: category)).isEmpty)
        }
    }

    @Test("Combining filters narrows, and never invents a row")
    func combinedFiltersAreASubset() async throws {
        let (cards, _) = try await fleet()
        for status in FleetFilter.Status.allCases {
            for ownership in FleetFilter.Ownership.allCases {
                let combined = cards.matching(
                    FleetFilter(status: status, ownership: ownership))
                let byStatus = Set(cards.matching(FleetFilter(status: status)).map(\.id))
                #expect(combined.allSatisfy { byStatus.contains($0.id) })
                // Order is the caller's, and must survive filtering — the
                // fleet list sorts before it filters.
                #expect(combined.map(\.id) == cards.filter { combined.map(\.id).contains($0.id) }.map(\.id))
            }
        }
    }

    @Test("An unnarrowed filter returns the fleet untouched")
    func emptyFilterIsIdentity() async throws {
        let (cards, _) = try await fleet()
        let filter = FleetFilter()
        #expect(!filter.isNarrowed)
        #expect(cards.matching(filter).map(\.id) == cards.map(\.id))
    }
}
