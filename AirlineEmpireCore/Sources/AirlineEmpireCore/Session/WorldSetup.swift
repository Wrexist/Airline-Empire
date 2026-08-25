/// Standard world population: founds a deterministic cast of AI competitors
/// through the ordinary command pipeline (no back-door state construction).
/// Called at new-game time after the player's airline is founded.
public enum WorldSetup {
    /// Fictional-but-plausible carrier names, paired with archetypes in
    /// rotation. Names must not collide with player choices — validators
    /// reject duplicates, so collisions just skip a competitor.
    static let competitorNames = [
        "PacificBlue", "Aurora Atlantic", "SwiftJet", "Crown Meridian",
        "TerraLink", "Borealis Air", "Solaria Airways", "Windward Express",
    ]

    /// Founds up to `count` AI airlines at the busiest airports (skipping
    /// the player's home), seeds each with capital and a starter aircraft,
    /// and lets CompetitorAISystem take it from there.
    public static func createCompetitors(engine: SimulationEngine, count: Int,
                                         playerHome: AirportCode,
                                         startingCash: Money = Money.dollars(120_000_000)) {
        let catalog = engine.catalog
        let archetypes = AIArchetype.allCases
        // Busiest airports first, deterministically.
        let homes = catalog.orderedAirportCodes
            .compactMap { catalog.airports[$0] }
            .filter { $0.code != playerHome && $0.runwayClass >= .large }
            .sorted { ($0.demographics.populationThousands, $0.code)
                > ($1.demographics.populationThousands, $1.code) }
            .prefix(count)

        for (index, home) in homes.enumerated() {
            guard index < competitorNames.count else { break }
            let profile = AIProfile(archetype: archetypes[index % archetypes.count])
            let result = engine.applyNow(FoundAirlineCommand(
                airlineName: competitorNames[index], kind: .ai,
                homeAirport: home.code, startingCash: startingCash,
                aiProfile: profile))
            guard result == .applied,
                  let airline = engine.state.airlines.values.first(where: {
                      $0.name == competitorNames[index]
                  }) else { continue }
            // Starter aircraft in the archetype's preferred class; the AI
            // system employs it on its first decision day.
            let types = catalog.orderedAircraftTypeCodes
                .compactMap { catalog.aircraftTypes[$0] }
                .filter { profile.preferredCategories.contains($0.category) }
                .sorted { ($0.listPrice, $0.code) < ($1.listPrice, $1.code) }
            if let starter = types.first {
                if profile.prefersLeasing {
                    _ = engine.applyNow(LeaseAircraftCommand(
                        lessee: airline.id, type: starter.code, termMonths: 60))
                } else {
                    _ = engine.applyNow(BuyUsedAircraftCommand(
                        buyer: airline.id, type: starter.code,
                        ageYears: profile.usedAgeYears))
                }
            }
        }
    }
}
