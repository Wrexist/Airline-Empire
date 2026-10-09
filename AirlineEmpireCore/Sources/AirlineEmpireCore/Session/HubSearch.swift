import Foundation

// The Hub View's search field (docs/HUB_VIEW_3D.md §1, top bar): stands,
// flights, aircraft, routes and places at the hub, each answering with
// where to take the camera. A pure read of a `HubSnapshot` and its layout.

public struct HubSearchResult: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case gate, flight, aircraft, route, place
    }

    /// What choosing the result does.
    public enum Target: Equatable, Sendable {
        /// Focus the stand and cut to its gate shot.
        case stand(Int)
        /// Light the route in the route fan.
        case route(RouteID)
        /// Cut to a shot.
        case shot(HubCameraShot)
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let target: Target
}

extension HubSnapshot {
    /// Up to `limit` results for `query`, best first: an exact gate number,
    /// then matches at the start of a word, then anywhere. Case and
    /// accents are ignored.
    public func search(_ query: String, layout: HubLayout, limit: Int = 8) -> [HubSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var scored: [(score: Int, order: Int, result: HubSearchResult)] = []
        func consider(_ result: HubSearchResult, _ haystacks: [String], bonus: Int = 0) {
            var best = 0
            for h in haystacks {
                guard let r = h.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let atWord = r.lowerBound == h.startIndex
                    || !h[h.index(before: r.lowerBound)].isLetter && !h[h.index(before: r.lowerBound)].isNumber
                let whole = r.lowerBound == h.startIndex && r.upperBound == h.endIndex
                best = max(best, whole ? 3 : atWord ? 2 : 1)
            }
            guard best > 0 else { return }
            scored.append((best * 10 + bonus, scored.count, result))
        }

        // Gates, with what is on them.
        for stand in layout.stands {
            let occupant = occupant(atStand: stand.index)
            let detail = occupant.map { o in
                [o.flight?.code, o.typeName, o.stage?.title].compactMap { $0 }.joined(separator: " · ")
            } ?? "Free"
            consider(HubSearchResult(id: "gate-\(stand.index)", kind: .gate, title: "Gate \(stand.gate)",
                                     detail: detail, target: .stand(stand.index)),
                     ["\(stand.gate)", "Gate \(stand.gate)", "Stand \(stand.gate)"], bonus: 2)
        }
        // Flights and aircraft at the stands.
        for o in occupants {
            if let f = o.flight {
                let towards = f.from == airport ? "to" : "from"
                consider(HubSearchResult(id: "flight-\(f.code)", kind: .flight, title: f.code,
                                         detail: "\(towards.capitalized) \(f.destinationCity) · Gate \(o.gate) · \(f.time)",
                                         target: .stand(o.standIndex)),
                         [f.code, f.destinationCity, (f.from == airport ? f.to : f.from).raw], bonus: 1)
            }
            if !o.registration.isEmpty || !o.typeName.isEmpty {
                consider(HubSearchResult(id: "aircraft-\(o.standIndex)", kind: .aircraft,
                                         title: o.registration.isEmpty ? o.typeName : o.registration,
                                         detail: "\(o.typeName) · Gate \(o.gate)", target: .stand(o.standIndex)),
                         [o.registration, o.typeName])
            }
        }
        // Flights on the board that are not at a stand: their route.
        let atStands = Set(occupants.compactMap { $0.flight?.code })
        for row in departures + arrivals where !atStands.contains(row.code) {
            guard let link = insights.routes.first(where: { $0.other == row.airport }) else { continue }
            consider(HubSearchResult(id: "flight-\(row.code)", kind: .flight, title: row.code,
                                     detail: "\(row.isDeparture ? "To" : "From") \(row.city) · \(row.time) · \(row.status.title)",
                                     target: .route(link.routeID)),
                     [row.code, row.city, row.airport.raw])
        }
        // Routes.
        for link in insights.routes {
            let load = link.loadFactor.map { " · \(Int(($0 * 100).rounded()))% full" } ?? ""
            consider(HubSearchResult(id: "route-\(link.routeID.raw)", kind: .route,
                                     title: "\(airport.raw)–\(link.other.raw) \(link.city)",
                                     detail: "\(link.dailyRoundTrips) a day · \(link.distanceKm) km\(load)",
                                     target: .route(link.routeID)),
                     [link.other.raw, link.city, "route"])
        }
        // Places.
        let places: [(String, String, HubCameraShot, [String])] = [
            ("Airport", "The whole airfield", .overview, ["airport", "overview", "apron", "runway"]),
            ("Terminal", "Check-in, security and retail", .terminal,
             ["terminal", "check-in", "security", "retail", "shops", "hall"]),
            ("District", "Maintenance, crew and waste pickups", .district,
             ["district", "maintenance", "crew", "waste", "city"]),
        ]
        for (title, detail, shot, words) in places {
            consider(HubSearchResult(id: "place-\(title)", kind: .place, title: title, detail: detail,
                                     target: .shot(shot)), words)
        }

        // Each result once, at its best score.
        var seen = Set<String>()
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.result)
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }
}
