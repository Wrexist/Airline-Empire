import Foundation

/// Versioned save format (docs/PERSISTENCE_ARCHITECTURE.md). Phase 3 ships
/// the codec + envelope so save-safe state transitions are testable from the
/// first kernel build; stores, slots, backups, and migrations land in
/// Phase 13 behind this same format.
public enum SaveFormat {
    public static let magic = "AESAVE"
    /// Bumps on ANY change to the encoded shape of `GameState` (D-004).
    /// History: v1 kernel-only (Phase 3); v2 added `world` (Phase 4);
    /// v3 added `airlines`/`aircraft`/`ledger` (Phase 5); v4 added
    /// `routes`/`flights` + Aircraft.activeFlight + world fuel price (Phase 6);
    /// v5 added route demand/load fields + world economicIndex (Phase 7);
    /// v6 added loans/status, finance statements, route economics, world
    /// cycle fields (Phase 8); v7 added reputation/serviceTier/opsToday
    /// (Phase 9).
    /// v8–v10 added progression; v11 added `Airline.livery` (the identity
    /// beat GAME_DESIGN §4.1 always specified and the client never had).
    /// Pre-release policy (docs/PERSISTENCE_ARCHITECTURE.md §5): superseded
    /// pre-release versions are refused, not migrated, until first TestFlight.
    /// v10 shipped to TestFlight, so it migrates rather than refuses.
    /// v12 added `world.marketMoves` (AE-037: who entered and left which
    /// city pair, the record competition needs and the event log cannot keep).
    /// v13 adds the persistent rescue decision and optional contract kinds.
    /// v14 adds `progression.record`: the bounded, dated log of completed
    /// work (milestones, achievements, capability programs, missions, era
    /// advances) an older save never kept.
    /// v15 adds hub buildings: the hangar and crew base levels, buildings
    /// under construction, earned hub statuses, and the events and record
    /// entries for openings — all optional, so v14 needs no rewriting, but an
    /// older build must refuse a save that may hold them.
    /// v16 adds the per-airline windows of TD-032 — the player's feed ring in
    /// the event log and each airline's ledger day totals — and the airline
    /// on `aircraftSold`/`leaseReturned` events. All optional again: a v15
    /// save decodes as is and the windows start recording on its first tick.
    public static let currentVersion = 16
}

public struct SaveEnvelope: Codable, Sendable {
    public let magic: String
    public let formatVersion: Int
    public let contentVersion: String
    public let savedAtTick: Int64
    public let checksum: UInt64
    public let payload: Data

    init(formatVersion: Int, contentVersion: String, savedAtTick: Int64, payload: Data) {
        self.magic = SaveFormat.magic
        self.formatVersion = formatVersion
        self.contentVersion = contentVersion
        self.savedAtTick = savedAtTick
        self.checksum = StableHash.fnv1a(payload)
        self.payload = payload
    }
}

public enum SaveError: Error, Equatable, Sendable, LocalizedError {
    case badMagic
    case checksumMismatch
    case unsupportedVersion(Int)
    case corruptPayload(String)
    /// The save names aircraft types or airports the running content does
    /// not have (a renamed or removed code). Refused at load so the
    /// simulation never meets a code its catalog lookups cannot resolve.
    case missingContent([String])

    public var errorDescription: String? {
        switch self {
        case .badMagic: "This is not an Airline Empire save."
        case .checksumMismatch: "This save is damaged or incomplete. Try another backup."
        case .unsupportedVersion: "This save uses an unsupported format. Update the app or choose a compatible backup."
        case .corruptPayload(let reason): reason
        case .missingContent(let codes):
            "This save refers to aircraft or airports this version of the game does not have (\(codes.prefix(4).joined(separator: ", "))). Update the app or choose another backup."
        }
    }
}

/// JSON codec with deterministic output (sorted keys) — same bytes for the
/// same state, which the state-hash determinism tests rely on.
/// Older formats are lifted through the migration chain before decoding.
public struct JSONSaveCodec: Sendable {
    public let migrations: MigrationChain
    /// The content saves are written against and checked against.
    ///
    /// A save refers to content by code (an aircraft type, an airport), and
    /// some twenty simulation paths force-unwrap the catalog lookup for a
    /// code they assume exists. Nothing at load checked that it did, so a
    /// content update that renamed one code would have crashed every old
    /// save that used it on its first tick. With a catalog, `decode` refuses
    /// such a save with `SaveError.missingContent` — an honest "cannot open"
    /// on the menu instead of a crash in the game — and `encode` records the
    /// catalog's version in the envelope instead of "0". Nil (the default)
    /// skips both, for tools and tests that run on synthetic content.
    public let catalog: ContentCatalog?

    public init(migrations: MigrationChain = .standard, catalog: ContentCatalog? = nil) {
        self.migrations = migrations
        self.catalog = catalog
    }

    /// Encodes a save. `contentVersion` defaults to the catalog's version,
    /// or "0" without a catalog.
    public func encode(_ state: GameState, contentVersion: String? = nil) throws -> Data {
        let payloadEncoder = JSONEncoder()
        payloadEncoder.outputFormatting = [.sortedKeys]
        let payload = try payloadEncoder.encode(state)
        let envelope = SaveEnvelope(
            formatVersion: SaveFormat.currentVersion,
            contentVersion: contentVersion ?? catalog?.version ?? "0",
            savedAtTick: state.clock.tickCount,
            payload: payload)
        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.outputFormatting = [.sortedKeys]
        return try envelopeEncoder.encode(envelope)
    }

    public func decode(_ data: Data) throws -> GameState {
        let envelope: SaveEnvelope
        do {
            envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        } catch {
            throw SaveError.corruptPayload("Envelope undecodable: \(error)")
        }
        guard envelope.magic == SaveFormat.magic else { throw SaveError.badMagic }
        guard envelope.checksum == StableHash.fnv1a(envelope.payload) else {
            throw SaveError.checksumMismatch
        }
        var payload = envelope.payload
        if envelope.formatVersion != SaveFormat.currentVersion {
            guard envelope.formatVersion < SaveFormat.currentVersion else {
                // Future formats (a newer app wrote this) refuse honestly.
                throw SaveError.unsupportedVersion(envelope.formatVersion)
            }
            do {
                guard var tree = try JSONSerialization.jsonObject(with: payload)
                    as? [String: Any] else {
                    throw SaveError.corruptPayload("Payload is not an object")
                }
                tree = try migrations.migrate(payload: tree, from: envelope.formatVersion)
                payload = try JSONSerialization.data(withJSONObject: tree)
            } catch let error as SaveError {
                throw error
            } catch {
                throw SaveError.corruptPayload("Migration failed: \(error)")
            }
        }
        do {
            let state = try JSONDecoder().decode(GameState.self, from: payload)
            // Synthesized Decodable bypasses GameMeta's initializer checks.
            // Reject malformed imports before the simulation can divide by zero.
            guard state.isLoadable else {
                throw SaveError.corruptPayload("This save contains an invalid game state. Choose another backup.")
            }
            if let catalog {
                let missing = state.unknownContentCodes(in: catalog)
                guard missing.isEmpty else { throw SaveError.missingContent(missing) }
            }
            return state
        } catch let error as SaveError {
            throw error
        } catch {
            throw SaveError.corruptPayload("State undecodable: \(error)")
        }
    }
}

extension GameState {
    /// Every content code the live state refers to that `catalog` does not
    /// define, labelled and sorted ("aircraft type MR999", "airport XYZ").
    ///
    /// Covers the references the simulation resolves through the catalog:
    /// aircraft types and positions, airline homes and stations, routes,
    /// flights, airport runtimes and airport closures. History — market
    /// moves, records, the event log — only ever names a code for display,
    /// so an old name there is harmless and not reported.
    public func unknownContentCodes(in catalog: ContentCatalog) -> [String] {
        var missing = Set<String>()
        func check(_ code: AirportCode) {
            if catalog.airport(code) == nil { missing.insert("airport \(code.raw)") }
        }
        for plane in self.aircraft.values {
            if catalog.aircraftType(plane.typeCode) == nil {
                missing.insert("aircraft type \(plane.typeCode.raw)")
            }
            check(plane.location)
        }
        for airline in self.airlines.values {
            check(airline.homeAirport)
            for code in (airline.airportFacilities ?? [:]).keys { check(code) }
            for code in (airline.hubStatuses ?? [:]).keys { check(code) }
            for build in airline.facilityConstructions ?? [] { check(build.airport) }
        }
        for route in self.routes.values {
            check(route.origin)
            check(route.destination)
        }
        for flight in self.flights.values {
            check(flight.from)
            check(flight.to)
        }
        for code in world.airportRuntimes.keys { check(code) }
        for event in world.activeEvents {
            if case .airportClosure(let code) = event.kind { check(code) }
        }
        return missing.sorted()
    }

    /// Everything `JSONSaveCodec.decode` demands of a decoded state: a tick
    /// that divides the day, a clock with headroom, and no integrity
    /// violation. `SaveManager.save` asks the same question, so a state the
    /// loader would refuse is never written over the saves it would load.
    var isLoadable: Bool {
        guard meta.tickMinutes > 0,
              meta.tickMinutes <= GameCalendar.minutesPerDay,
              GameCalendar.minutesPerDay % meta.tickMinutes == 0,
              clock.tickCount >= 0,
              clock.now.rawMinutes <= Int64.max - 2 * GameCalendar.minutesPerDay
        else { return false }
        return integrityViolations().isEmpty
    }

    /// Stable content hash of the full state — the determinism oracle used
    /// by dual-run and save/restore tests.
    public func stateHash() throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return StableHash.fnv1a(try encoder.encode(self))
    }
}
