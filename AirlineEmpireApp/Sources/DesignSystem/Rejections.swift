import Foundation
import AirlineEmpireCore

/// Turning a refusal into something a player can act on (MASTER PROMPT 4 §24).
///
/// Core refuses commands with a typed `CommandRejection` — a stable `code` and
/// a message written for whoever is reading the simulation. Those two audiences
/// are not the same person. The app was showing the Core message verbatim, so a
/// player who assigned the wrong aeroplane to a long route was told:
///
///     MR180 range 2750 km < route 4100 km
///
/// which is an inequality, not an explanation. Others — "Unknown airline",
/// "No such route" — are internal invariants that a player can neither cause
/// nor fix, and seeing one is a bug report, not information.
///
/// This maps the `code` (the contract) rather than the message (the prose), so
/// Core stays free to reword itself without breaking the player-facing copy,
/// and an unmapped code still falls back to something rather than nothing.
///
/// Each mapping answers §24's three questions: what happened, why, and what
/// the player can do about it. The third is the one that was missing.
struct RejectionPresentation: Equatable {
    /// A short phrase naming what was refused. Never "Error".
    let title: String
    /// Why, in the game's own terms.
    let explanation: String
    /// The next thing to try. Nil when there genuinely is nothing to suggest.
    let suggestion: String?

    /// The full body an alert shows.
    var body: String {
        guard let suggestion else { return explanation }
        return "\(explanation)\n\n\(suggestion)"
    }
}

enum Rejections {
    /// Player-facing copy for a refusal.
    ///
    /// The Core message is used as the explanation wherever it already reads as
    /// a sentence a player would understand — several of them do, and rewriting
    /// those here would only create a second thing to keep in sync. What is
    /// added is the suggestion, and a rewrite of the ones that leaked
    /// implementation.
    static func present(_ rejection: CommandRejection) -> RejectionPresentation {
        switch rejection.code {

        // MARK: Money

        case "fleet.insufficientFunds", "finance.insufficientFunds",
             "progression.insufficientFunds":
            return .init(title: "Not enough cash",
                         explanation: rejection.message,
                         suggestion: "Sell or return an aircraft you are not "
                            + "flying, or take a loan from Finance.")

        case "finance.overLeveraged":
            return .init(title: "Too much debt",
                         explanation: rejection.message,
                         suggestion: "Repay part of an existing loan before "
                            + "borrowing again.")

        case "finance.tooManyLoans":
            return .init(title: "Too many loans",
                         explanation: rejection.message,
                         suggestion: "Clear one before opening another.")

        // MARK: Aircraft and range

        case "route.beyondRange", "fleet.beyondRange":
            // The Core message is the inequality. This is the same fact as a
            // decision: the aeroplane cannot reach, so pick a different one or
            // a nearer city.
            return .init(title: "Aircraft cannot reach",
                         explanation: "This aircraft does not have the range "
                            + "for that distance.",
                         suggestion: "Assign a longer-range aircraft, or open "
                            + "the route to a nearer airport.")

        // Core emits `route.runwayTooSmall`. This case used to read
        // `route.runway`/`route.runwayTooShort` — neither of which any
        // command has ever returned — so the copy below was unreachable and
        // every runway refusal fell through to the generic branch.
        case "route.runwayTooSmall":
            return .init(title: "Runway too short",
                         explanation: rejection.message,
                         suggestion: "Use a smaller aircraft, or choose an "
                            + "airport that can take this one.")

        case "fleet.alreadyAssigned", "fleet.assigned":
            return .init(title: "Aircraft already flying",
                         explanation: "This aircraft is assigned to another "
                            + "route.",
                         suggestion: "Unassign it there first, or use an idle "
                            + "aircraft.")

        case "fleet.inFlight":
            return .init(title: "Aircraft is in the air",
                         explanation: "This aircraft is mid-flight.",
                         suggestion: "Wait for it to land, then try again.")

        case "fleet.notDelivered":
            return .init(title: "Not delivered yet",
                         explanation: "This aircraft is still on order.",
                         suggestion: "It can fly once it arrives — the "
                            + "delivery date is on its detail screen.")

        case "fleet.cannotSellLeased":
            return .init(title: "Leased aircraft",
                         explanation: "You do not own this aircraft, so it "
                            + "cannot be sold.",
                         suggestion: "Return it to the lessor instead.")

        case "fleet.notSellableNow", "fleet.notReturnableNow":
            return .init(title: "Not right now",
                         explanation: rejection.message,
                         suggestion: "Unassign it from its route and wait for "
                            + "it to be on the ground.")

        // MARK: Slots and airports

        case "route.noSlots", "route.originSlots", "route.destinationSlots":
            return .init(title: "No free slots",
                         explanation: rejection.message,
                         suggestion: "Lower the frequency, or fly from a less "
                            + "congested airport.")

        // MARK: The route itself

        case "route.duplicate":
            return .init(title: "Already flying this",
                         explanation: "You already serve this city pair.",
                         suggestion: "Raise the frequency on the existing "
                            + "route instead of opening a second one.")

        case "route.sameAirport":
            return .init(title: "Same airport",
                         explanation: "A route needs two different airports.",
                         suggestion: nil)

        case "route.tooShort":
            return .init(title: "Too short to fly",
                         explanation: rejection.message,
                         suggestion: "Pick a destination further away — nobody "
                            + "flies this one.")

        case "route.badPrice":
            return .init(title: "Fare not valid",
                         explanation: "A ticket price must be above zero.",
                         suggestion: nil)

        case "route.badFrequency":
            return .init(title: "Frequency not valid",
                         explanation: rejection.message,
                         suggestion: nil)

        // Likewise: Core emits `route.flightsAirborne`, not
        // `route.hasAirborneFlights`.
        case "route.flightsAirborne":
            return .init(title: "Flights still out",
                         explanation: "This route has aircraft in the air.",
                         suggestion: "Wait for them to land, then close it.")

        case "fleet.notLeased":
            return .init(title: "Not a leased aircraft",
                         explanation: "You own this aircraft outright, so "
                            + "there is no lessor to return it to.",
                         suggestion: "Sell it instead.")

        case "fleet.notAssigned":
            return .init(title: "Not on a route",
                         explanation: "This aircraft is not assigned to "
                            + "anything, so there is nothing to unassign.",
                         suggestion: nil)

        case "fleet.badUsedAge":
            return .init(title: "No aircraft at that age",
                         explanation: rejection.message,
                         suggestion: "Choose an age inside the range the used "
                            + "market offers.")

        case "fleet.badLeaseTerm":
            return .init(title: "Lease term not valid",
                         explanation: rejection.message,
                         suggestion: "Pick a term inside the range the lessor "
                            + "will write.")

        // MARK: Progression

        case "progression.lockedCategory":
            // The refusal a player meets most often in the aircraft market,
            // and it had no mapping at all — so the one purchase they cannot
            // yet make explained itself in the same voice as a broken
            // invariant.
            return .init(title: "Not available in this era",
                         explanation: rejection.message,
                         suggestion: "Grow the airline to reach the era that "
                            + "unlocks this class of aircraft.")


        case "progression.eraLocked":
            return .init(title: "Not available yet",
                         explanation: rejection.message,
                         suggestion: "Grow the airline to reach the next era.")

        case "progression.tooManyPrograms":
            return .init(title: "Too many programmes",
                         explanation: rejection.message,
                         suggestion: "Wait for one to finish before starting "
                            + "another.")

        case "progression.alreadyRunning", "progression.alreadyCompleted":
            return .init(title: "Already under way",
                         explanation: rejection.message,
                         suggestion: nil)

        // MARK: Founding

        case "airline.nameTaken":
            return .init(title: "Name taken",
                         explanation: "Another airline already flies under "
                            + "that name.",
                         suggestion: "Choose a different one.")

        case "airline.badName":
            return .init(title: "Name not valid",
                         explanation: rejection.message,
                         suggestion: nil)

        default:
            // Two families end up here on purpose.
            //
            // Anything beginning `unknown`/`notYours`/`noSuch` is an internal
            // invariant: the player cannot cause it and cannot fix it, so
            // repeating "Unknown airline" at them is noise. Say that something
            // went wrong, plainly.
            if isInternal(rejection.code) {
                return .init(title: "Something went wrong",
                             explanation: "That action could not be completed.",
                             suggestion: "If it keeps happening, reloading your "
                                + "save usually clears it.")
            }
            // Everything else: Core's own sentence, which for most codes is
            // already written for a person.
            return .init(title: "Not possible",
                         explanation: rejection.message,
                         suggestion: nil)
        }
    }

    /// Codes describing a broken invariant rather than a player mistake.
    static func isInternal(_ code: String) -> Bool {
        let tail = code.split(separator: ".").last.map(String.init) ?? code
        return tail.hasPrefix("unknown")
            || tail.hasPrefix("noSuch")
            || tail == "notYours"
            || tail == "notYourAircraft"
            || tail == "playerOnly"
    }
}
