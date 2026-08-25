/// Competitor personality (docs/AI.md). Parameters derive from the
/// archetype so content/balance can reason about five behaviors, not fifty
/// knobs. AI airlines play by the exact same rules as the player — every
/// action goes through the same commands and validators.
public struct AIProfile: Equatable, Codable, Sendable {
    public let archetype: AIArchetype

    public init(archetype: AIArchetype) {
        self.archetype = archetype
    }

    /// Fare multiplier vs. the market reference fare.
    public var priceFactor: Double {
        switch archetype {
        case .lowCost: 0.85
        case .premium: 1.25
        case .regional: 1.0
        case .conservative: 1.05
        case .expansionist: 0.95
        }
    }

    public var serviceTier: ServiceTier {
        switch archetype {
        case .lowCost: .basic
        case .premium: .premium
        case .regional, .conservative, .expansionist: .standard
        }
    }

    /// Aircraft categories this airline shops in, in preference order.
    public var preferredCategories: [AircraftCategory] {
        switch archetype {
        case .lowCost: [.narrowbody, .largeNarrowbody]
        case .premium: [.largeNarrowbody, .widebody, .narrowbody]
        case .regional: [.turboprop, .regionalJet]
        case .conservative: [.narrowbody, .regionalJet]
        case .expansionist: [.narrowbody, .regionalJet, .largeNarrowbody]
        }
    }

    /// Prefers leasing (flexibility) over buying used (cost).
    public var prefersLeasing: Bool {
        switch archetype {
        case .lowCost, .expansionist: true
        case .premium, .regional, .conservative: false
        }
    }

    /// Used-market age it shops at (younger = pricier, more reliable).
    public var usedAgeYears: Int {
        switch archetype {
        case .premium: 3
        case .conservative: 8
        case .lowCost, .regional: 12
        case .expansionist: 14
        }
    }

    /// Months of cost coverage required before expanding.
    public var expandRunwayMonths: Double {
        switch archetype {
        case .expansionist: 2.5
        case .lowCost: 3
        case .regional, .premium: 4
        case .conservative: 6
        }
    }

    /// Willingness to borrow: ceiling on debt ratio for expansion loans.
    public var maxComfortableDebtRatio: Double {
        switch archetype {
        case .expansionist: 0.7
        case .lowCost: 0.55
        case .premium, .regional: 0.4
        case .conservative: 0.2
        }
    }

    /// Stays inside the home region (regional specialist behavior).
    public var homeRegionOnly: Bool {
        archetype == .regional
    }

    /// How it answers a competitor undercutting its route.
    /// Returns the new fare given (own ref fare, competitor's fare).
    public func priceResponse(referenceFare: Double, competitorFare: Double) -> Double {
        switch archetype {
        case .lowCost:
            // Undercut back, but never below 60% of reference.
            max(referenceFare * 0.6, competitorFare * 0.97)
        case .premium:
            // Holds its premium floor; cedes the bottom of the market.
            max(referenceFare * 1.1, competitorFare * 1.15)
        case .regional, .conservative:
            max(referenceFare * 0.8, competitorFare * 1.02)
        case .expansionist:
            max(referenceFare * 0.7, competitorFare * 0.99)
        }
    }
}

public enum AIArchetype: String, Codable, Sendable, CaseIterable {
    case lowCost
    case premium
    case regional
    case conservative
    case expansionist
}
