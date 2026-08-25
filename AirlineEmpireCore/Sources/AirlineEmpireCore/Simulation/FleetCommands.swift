/// Fleet & airline commands (Phase 5). AI airlines issue these same
/// commands through the same validators (docs/DOMAIN_MODEL.md §5).

public struct FoundAirlineCommand: Command, Equatable {
    public static let name = "foundAirline"

    public let airlineName: String
    public let kind: AirlineKind
    public let homeAirport: AirportCode
    public let startingCash: Money
    /// Personality for AI airlines; must be nil for the player.
    public let aiProfile: AIProfile?

    public init(airlineName: String, kind: AirlineKind,
                homeAirport: AirportCode, startingCash: Money,
                aiProfile: AIProfile? = nil) {
        self.airlineName = airlineName
        self.kind = kind
        self.homeAirport = homeAirport
        self.startingCash = startingCash
        self.aiProfile = aiProfile
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        let trimmed = airlineName.trimmed()
        if trimmed.isEmpty || trimmed.count > 40 {
            return CommandRejection(code: "airline.badName",
                                    message: "Airline name must be 1–40 characters")
        }
        if state.airlines.values.contains(where: { $0.name == trimmed }) {
            return CommandRejection(code: "airline.nameTaken",
                                    message: "An airline named \(trimmed) already exists")
        }
        if catalog.airport(homeAirport) == nil {
            return CommandRejection(code: "airline.unknownHome",
                                    message: "Unknown home airport \(homeAirport)")
        }
        if startingCash.isNegative {
            return CommandRejection(code: "airline.negativeCapital",
                                    message: "Starting capital cannot be negative")
        }
        if kind == .player && state.airlines.values.contains(where: { $0.kind == .player }) {
            return CommandRejection(code: "airline.playerExists",
                                    message: "This world already has a player airline")
        }
        if kind == .player && aiProfile != nil {
            return CommandRejection(code: "airline.playerWithProfile",
                                    message: "The player airline cannot carry an AI profile")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let id = state.meta.idAllocator.allocateAirlineID()
        var airline = Airline(id: id, name: airlineName.trimmed(), kind: kind,
                              homeAirport: homeAirport, foundedAt: context.current)
        if kind == .ai, let profile = aiProfile {
            airline.aiProfile = profile
            airline.serviceTier = profile.serviceTier
        }
        state.airlines[id] = airline
        state.ledger.post(airline: id, category: .initialCapital,
                          amount: startingCash, at: context.current)
        context.emit(.airlineFounded(id: id, name: airlineName.trimmed()))
    }
}

public struct BuyNewAircraftCommand: Command, Equatable {
    public static let name = "buyNewAircraft"

    public let buyer: AirlineID
    public let type: AircraftTypeCode

    public init(buyer: AirlineID, type: AircraftTypeCode) {
        self.buyer = buyer
        self.type = type
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard state.airlines[buyer] != nil else {
            return CommandRejection(code: "fleet.unknownAirline", message: "Unknown airline")
        }
        guard let spec = catalog.aircraftType(type) else {
            return CommandRejection(code: "fleet.unknownType",
                                    message: "Unknown aircraft type \(type)")
        }
        if state.isPlayer(buyer),
           !state.progression.era.allowedCategories.contains(spec.category) {
            return CommandRejection(code: "progression.lockedCategory",
                                    message: "\(spec.category.rawValue) aircraft unlock in a later era")
        }
        if state.ledger.balance(of: buyer) < spec.listPrice {
            return CommandRejection(code: "fleet.insufficientFunds",
                                    message: "Need \(spec.listPrice.cents / 100) for this aircraft")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let spec = context.catalog.aircraftType(type)!
        let airline = state.airlines[buyer]!
        let id = state.meta.idAllocator.allocateAircraftID()
        let deliveryAt = context.current + .days(Int64(spec.deliveryLeadDays))
        state.ledger.post(airline: buyer, category: .aircraftPurchase,
                          amount: -spec.listPrice, at: context.current,
                          memo: "New \(spec.model)")
        state.aircraft[id] = Aircraft(
            id: id, typeCode: type, owner: buyer,
            ownership: .owned(bookValue: spec.listPrice),
            status: .ordered(deliveryAt: deliveryAt),
            location: airline.homeAirport, ageDays: 0, condition: 1.0)
        context.emit(.aircraftOrdered(id: id, type: type, deliveryAt: deliveryAt))
    }
}

public struct BuyUsedAircraftCommand: Command, Equatable {
    public static let name = "buyUsedAircraft"

    public let buyer: AirlineID
    public let type: AircraftTypeCode
    public let ageYears: Int

    public init(buyer: AirlineID, type: AircraftTypeCode, ageYears: Int) {
        self.buyer = buyer
        self.type = type
        self.ageYears = ageYears
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard state.airlines[buyer] != nil else {
            return CommandRejection(code: "fleet.unknownAirline", message: "Unknown airline")
        }
        guard let spec = catalog.aircraftType(type) else {
            return CommandRejection(code: "fleet.unknownType",
                                    message: "Unknown aircraft type \(type)")
        }
        if state.isPlayer(buyer),
           !state.progression.era.allowedCategories.contains(spec.category) {
            return CommandRejection(code: "progression.lockedCategory",
                                    message: "\(spec.category.rawValue) aircraft unlock in a later era")
        }
        let tuning = catalog.tuning.fleet
        if !(1...tuning.maxUsedPurchaseAgeYears).contains(ageYears) {
            return CommandRejection(code: "fleet.badUsedAge",
                                    message: "Used airframes are 1–\(tuning.maxUsedPurchaseAgeYears) years old")
        }
        let price = FleetEconomics.usedPrice(
            type: spec, ageYears: Double(ageYears),
            condition: FleetEconomics.usedMarketCondition(ageYears: Double(ageYears), tuning: tuning),
            tuning: tuning)
        if state.ledger.balance(of: buyer) < price {
            return CommandRejection(code: "fleet.insufficientFunds",
                                    message: "Need \(price.cents / 100) for this aircraft")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let spec = context.catalog.aircraftType(type)!
        let tuning = context.catalog.tuning.fleet
        let airline = state.airlines[buyer]!
        let condition = FleetEconomics.usedMarketCondition(ageYears: Double(ageYears), tuning: tuning)
        let price = FleetEconomics.usedPrice(type: spec, ageYears: Double(ageYears),
                                             condition: condition, tuning: tuning)
        let id = state.meta.idAllocator.allocateAircraftID()
        state.ledger.post(airline: buyer, category: .aircraftPurchase,
                          amount: -price, at: context.current,
                          memo: "Used \(spec.model), \(ageYears)y")
        state.aircraft[id] = Aircraft(
            id: id, typeCode: type, owner: buyer,
            ownership: .owned(bookValue: price), status: .active,
            location: airline.homeAirport,
            ageDays: ageYears * Int(GameCalendar.daysPerYear), condition: condition)
        context.emit(.aircraftDelivered(id: id))
    }
}

public struct LeaseAircraftCommand: Command, Equatable {
    public static let name = "leaseAircraft"

    public let lessee: AirlineID
    public let type: AircraftTypeCode
    public let termMonths: Int

    public init(lessee: AirlineID, type: AircraftTypeCode, termMonths: Int) {
        self.lessee = lessee
        self.type = type
        self.termMonths = termMonths
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard state.airlines[lessee] != nil else {
            return CommandRejection(code: "fleet.unknownAirline", message: "Unknown airline")
        }
        guard let spec = catalog.aircraftType(type) else {
            return CommandRejection(code: "fleet.unknownType",
                                    message: "Unknown aircraft type \(type)")
        }
        if state.isPlayer(lessee),
           !state.progression.era.allowedCategories.contains(spec.category) {
            return CommandRejection(code: "progression.lockedCategory",
                                    message: "\(spec.category.rawValue) aircraft unlock in a later era")
        }
        let tuning = catalog.tuning.fleet
        if !(tuning.minLeaseTermMonths...tuning.maxLeaseTermMonths).contains(termMonths) {
            return CommandRejection(code: "fleet.badLeaseTerm",
                                    message: "Lease terms run \(tuning.minLeaseTermMonths)–\(tuning.maxLeaseTermMonths) months")
        }
        // First month is due on signing.
        if state.ledger.balance(of: lessee) < spec.leaseMonthly {
            return CommandRejection(code: "fleet.insufficientFunds",
                                    message: "First lease payment of \(spec.leaseMonthly.cents / 100) required")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let spec = context.catalog.aircraftType(type)!
        let airline = state.airlines[lessee]!
        let id = state.meta.idAllocator.allocateAircraftID()
        state.ledger.post(airline: lessee, category: .leasePayment,
                          amount: -spec.leaseMonthly, at: context.current,
                          memo: "Lease signing, \(spec.model)")
        state.aircraft[id] = Aircraft(
            id: id, typeCode: type, owner: lessee,
            ownership: .leased(monthlyRate: spec.leaseMonthly, termMonthsRemaining: termMonths),
            status: .active, location: airline.homeAirport,
            ageDays: 0, condition: 1.0)
        context.emit(.aircraftDelivered(id: id))
    }
}

public struct SellAircraftCommand: Command, Equatable {
    public static let name = "sellAircraft"

    public let seller: AirlineID
    public let aircraftID: AircraftID

    public init(seller: AirlineID, aircraftID: AircraftID) {
        self.seller = seller
        self.aircraftID = aircraftID
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let aircraft = state.aircraft[aircraftID], aircraft.owner == seller else {
            return CommandRejection(code: "fleet.notYourAircraft",
                                    message: "No such aircraft in your fleet")
        }
        if aircraft.ownership.isLeased {
            return CommandRejection(code: "fleet.cannotSellLeased",
                                    message: "Leased aircraft are returned, not sold")
        }
        guard aircraft.isOperational else {
            return CommandRejection(code: "fleet.notSellableNow",
                                    message: "Aircraft is not available for sale right now")
        }
        if aircraft.assignedRoute != nil {
            return CommandRejection(code: "fleet.assigned",
                                    message: "Unassign the aircraft from its route first")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let aircraft = state.aircraft[aircraftID]!
        let spec = context.catalog.aircraftType(aircraft.typeCode)!
        let proceeds = FleetEconomics.saleValue(
            type: spec, ageYears: aircraft.ageYears, condition: aircraft.condition,
            tuning: context.catalog.tuning.fleet)
        state.ledger.post(airline: seller, category: .aircraftSale,
                          amount: proceeds, at: context.current,
                          memo: "Sold \(spec.model)")
        state.aircraft[aircraftID] = nil
        context.emit(.aircraftSold(id: aircraftID, proceeds: proceeds))
    }
}

public struct ReturnLeasedAircraftCommand: Command, Equatable {
    public static let name = "returnLeasedAircraft"

    public let lessee: AirlineID
    public let aircraftID: AircraftID

    public init(lessee: AirlineID, aircraftID: AircraftID) {
        self.lessee = lessee
        self.aircraftID = aircraftID
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let aircraft = state.aircraft[aircraftID], aircraft.owner == lessee else {
            return CommandRejection(code: "fleet.notYourAircraft",
                                    message: "No such aircraft in your fleet")
        }
        guard aircraft.ownership.isLeased else {
            return CommandRejection(code: "fleet.notLeased",
                                    message: "This aircraft is owned; sell it instead")
        }
        guard aircraft.isOperational else {
            return CommandRejection(code: "fleet.notReturnableNow",
                                    message: "Aircraft is not available to return right now")
        }
        if aircraft.assignedRoute != nil {
            return CommandRejection(code: "fleet.assigned",
                                    message: "Unassign the aircraft from its route first")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let aircraft = state.aircraft[aircraftID]!
        guard case .leased(let monthlyRate, let remaining) = aircraft.ownership else {
            preconditionFailure("Validated as leased")
        }
        var penalty = Money.zero
        if remaining > 0 {
            let months = Int64(context.catalog.tuning.fleet.earlyLeaseReturnPenaltyMonths)
            penalty = monthlyRate * months
            state.ledger.post(airline: lessee, category: .leasePenalty,
                              amount: -penalty, at: context.current,
                              memo: "Early lease return")
        }
        state.aircraft[aircraftID] = nil
        context.emit(.leaseReturned(id: aircraftID, penalty: penalty))
    }
}

public struct SetServiceTierCommand: Command, Equatable {
    public static let name = "setServiceTier"

    public let airline: AirlineID
    public let tier: ServiceTier

    public init(airline: AirlineID, tier: ServiceTier) {
        self.airline = airline
        self.tier = tier
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let a = state.airlines[airline], a.status == .active else {
            return CommandRejection(code: "airline.unknown", message: "Unknown airline")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        state.airlines[airline]!.serviceTier = tier
    }
}

extension String {
    func trimmed() -> String {
        var result = Substring(self)
        while result.first?.isWhitespace == true { result.removeFirst() }
        while result.last?.isWhitespace == true { result.removeLast() }
        return String(result)
    }
}
