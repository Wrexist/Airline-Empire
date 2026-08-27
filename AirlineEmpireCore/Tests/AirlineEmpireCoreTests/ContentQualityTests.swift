import Testing
@testable import AirlineEmpireCore

/// Content quality guards (V3 prompt §18). `ContentCatalog` already rejects
/// *invalid* content on load; these tests defend against content that loads
/// fine but is bad game design — dead SKUs, unreachable places, orphaned
/// references — so a future content edit cannot quietly introduce them.
@Suite("Content quality")
struct ContentQualityTests {
    private func catalog() throws -> ContentCatalog { try ContentCatalog.loadBundled() }

    /// No aircraft may be strictly dominated: for every pair, one must beat
    /// the other on something a player can care about. A dominated type is
    /// dead content — it would never be worth buying.
    @Test func noAircraftIsStrictlyDominated() throws {
        let catalog = try catalog()
        let types = catalog.orderedAircraftTypeCodes.compactMap { catalog.aircraftType($0) }
        #expect(types.count >= 10)

        // Higher is better; lower is better. Delivery lead, price, burn and
        // upkeep are costs; seats, range, comfort, reliability, speed are not.
        func dominates(_ a: AircraftTypeSpec, _ b: AircraftTypeSpec) -> Bool {
            let benefitsAtLeastEqual =
                a.seats >= b.seats && a.rangeKm >= b.rangeKm
                && a.comfortBaseline >= b.comfortBaseline
                && a.reliabilityBaseline >= b.reliabilityBaseline
                && a.cruiseSpeedKmh >= b.cruiseSpeedKmh
            let costsAtMostEqual =
                a.fuelBurnKgPerKm <= b.fuelBurnKgPerKm
                && a.listPrice <= b.listPrice && a.leaseMonthly <= b.leaseMonthly
                && a.maintenancePerFlightHour <= b.maintenancePerFlightHour
                && a.deliveryLeadDays <= b.deliveryLeadDays
                && a.turnaroundMinutes <= b.turnaroundMinutes
            let strictlyBetterSomewhere =
                a.seats > b.seats || a.rangeKm > b.rangeKm
                || a.comfortBaseline > b.comfortBaseline
                || a.fuelBurnKgPerKm < b.fuelBurnKgPerKm
                || a.listPrice < b.listPrice
            return benefitsAtLeastEqual && costsAtMostEqual && strictlyBetterSomewhere
        }

        for a in types {
            for b in types where a.code != b.code {
                #expect(!dominates(a, b),
                        "\(b.code.raw) is strictly dominated by \(a.code.raw) — dead content")
            }
        }
    }

    /// Every aircraft category must be acquirable in some era, or the type
    /// exists but can never be bought.
    @Test func everyAircraftCategoryIsReachable() throws {
        let catalog = try catalog()
        let categories = Set(catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0)?.category })
        let reachable = Set(Era.allCases.flatMap(\.allowedCategories))
        #expect(categories.subtracting(reachable).isEmpty)
        // And the first era must allow enough to actually start a game.
        #expect(!Era.startup.allowedCategories.isEmpty)
        let starterTypes = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .filter { Era.startup.allowedCategories.contains($0.category) }
        #expect(starterTypes.count >= 3)
    }

    /// Every airport must be servable by at least one aircraft type from at
    /// least one other airport — no decorative pins on the map.
    @Test func everyAirportIsReachableAndUsable() throws {
        let catalog = try catalog()
        let codes = catalog.orderedAirportCodes
        let types = codes.isEmpty ? [] : catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
        for code in codes {
            let spec = try #require(catalog.airport(code))
            #expect(spec.slotCapacityPerDay > 0)
            #expect(spec.demographics.populationThousands > 0)
            let servable = codes.contains { other in
                other != code && types.contains { type in
                    catalog.routeEligibility(from: code, to: other,
                                             aircraftRangeKm: type.rangeKm,
                                             aircraftRunwayRequirement: type.runwayRequirement)
                        .isEmpty
                }
            }
            #expect(servable, "\(code.raw) can host no route with any aircraft")
        }
    }

    /// Identity must be unique and references must resolve: duplicate names
    /// or an orphaned seasonality profile are content rot.
    @Test func identityIsUniqueAndReferencesResolve() throws {
        let catalog = try catalog()
        let airports = catalog.orderedAirportCodes.compactMap { catalog.airport($0) }
        #expect(Set(airports.map(\.code)).count == airports.count)
        #expect(Set(airports.map(\.name)).count == airports.count)
        #expect(Set(airports.map(\.city)).count == airports.count)

        // Every referenced seasonality profile exists, and none is orphaned.
        let referenced = Set(airports.map(\.seasonality))
        let defined = Set(catalog.seasonality.keys)
        #expect(referenced.subtracting(defined).isEmpty, "dangling seasonality reference")
        #expect(defined.subtracting(referenced).isEmpty, "unused seasonality profile")

        let types = catalog.orderedAircraftTypeCodes.compactMap { catalog.aircraftType($0) }
        #expect(Set(types.map(\.code)).count == types.count)
        #expect(Set(types.map { "\($0.manufacturer) \($0.model)" }).count == types.count)
    }

    /// Every region must carry enough airports to host a network, so no
    /// region is a dead corner of the map.
    @Test func everyRegionIsPlayable() throws {
        let catalog = try catalog()
        for region in WorldRegion.allCases {
            let inRegion = catalog.airports(in: region)
            #expect(inRegion.count >= 3, "\(region) has too few airports to matter")
        }
    }

    /// Value sanity beyond schema validation: no impossible economics.
    @Test func economicValuesAreSane() throws {
        let catalog = try catalog()
        for code in catalog.orderedAircraftTypeCodes {
            let type = try #require(catalog.aircraftType(code))
            #expect(type.seats > 0)
            #expect(type.rangeKm > 0)
            #expect(type.fuelBurnKgPerKm > 0)
            #expect(type.listPrice > .zero)
            #expect(type.leaseMonthly > .zero)
            #expect(type.turnaroundMinutes > 0)
            #expect(type.comfortBaseline > 0 && type.comfortBaseline <= 1)
            #expect(type.reliabilityBaseline > 0.5 && type.reliabilityBaseline <= 1)
            // A lease must be a fraction of ownership, never a bargain buy.
            #expect(type.leaseMonthly.cents * 12 < type.listPrice.cents)
            // Bigger aircraft must burn more in absolute terms.
            #expect(type.fuelBurnKgPerKm < Double(type.seats))
        }
        // Scenario presets must be ordered by difficulty, not just distinct.
        let founder = try #require(catalog.scenario("founder"))
        let entrepreneur = try #require(catalog.scenario("entrepreneur"))
        let magnate = try #require(catalog.scenario("magnate"))
        #expect(founder.playerStartingCash > entrepreneur.playerStartingCash)
        #expect(entrepreneur.playerStartingCash > magnate.playerStartingCash)
        #expect(founder.competitorCount <= entrepreneur.competitorCount)
        #expect(entrepreneur.competitorCount <= magnate.competitorCount)
    }
}
