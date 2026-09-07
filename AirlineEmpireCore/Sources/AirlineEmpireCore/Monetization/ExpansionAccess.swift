/// Runtime expansion checks shared by previews and the command boundary.
/// A lapsed subscription never deletes assets or stops existing operations.
public enum ExpansionAccess {
    public static func rejection(for command: any Command, state: GameState,
                                 catalog: ContentCatalog, ceiling: Era) -> CommandRejection? {
        guard ceiling < .empire, let player = state.playerAirline else { return nil }
        var acquisition: (AirlineID, AircraftTypeCode)?
        switch command {
        case let c as BuyNewAircraftCommand: acquisition = (c.buyer, c.type)
        case let c as BuyUsedAircraftCommand: acquisition = (c.buyer, c.type)
        case let c as LeaseAircraftCommand: acquisition = (c.lessee, c.type)
        case let c as StartCapabilityProgramCommand:
            if c.airline == player.id, ceiling < CapabilityProgram.unlockEra {
                return locked("New capability programs require Pro. Your existing programs continue.")
            }
        case let c as OpenRouteCommand where c.airline == player.id:
            let airports = ContentAccess.free.servableAirports(home: player.homeAirport, catalog: catalog)
            if !airports.contains(c.origin) || !airports.contains(c.destination) {
                return locked("This airport requires Pro. Your existing routes keep flying.")
            }
        default: break
        }
        if let (owner, type) = acquisition, owner == player.id,
           let spec = catalog.aircraftTypes[type],
           !ceiling.allowedCategories.contains(spec.category) {
            return locked("Acquiring this aircraft class requires Pro. Your existing fleet keeps flying.")
        }
        return nil
    }

    private static func locked(_ message: String) -> CommandRejection {
        CommandRejection(code: "access.proRequired", message: message)
    }
}
