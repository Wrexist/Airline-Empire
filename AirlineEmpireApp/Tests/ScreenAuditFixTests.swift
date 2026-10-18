import XCTest
import GameKit
import SwiftUI
import AirlineEmpireCore
@testable import AirlineEmpire

/// The pure decisions behind the 18 October screen fixes
/// (docs/GAME_AUDIT_2026-10-18.md §3 and the Screens polish line). Each one
/// was a wrong answer that no screen could show was wrong until a player hit
/// it, so each is pinned here where it is cheap to check.
final class ScreenAuditFixTests: XCTestCase {

    /// A dismissed sheet or an absent account is "signed out", which tells
    /// the player how to sign in; only a real failure is "unavailable".
    @MainActor
    func testGameCenterCancelAndNoAccountReadAsSignedOut() {
        XCTAssertEqual(GameCenter.status(afterSignInError: nil), .signedOut)
        XCTAssertEqual(GameCenter.status(afterSignInError: GKError(.cancelled)), .signedOut)
        XCTAssertEqual(GameCenter.status(afterSignInError: GKError(.notAuthenticated)), .signedOut)
        XCTAssertEqual(GameCenter.status(afterSignInError: GKError(.communicationsFailure)),
                       .unavailable)
        XCTAssertEqual(GameCenter.status(afterSignInError: URLError(.notConnectedToInternet)),
                       .unavailable)
    }

    /// Never smaller than standard, larger with the text, capped — and the
    /// standard boxes are exactly the ones the placer always used.
    func testMapLabelsGrowWithTextSizeWithinTheCap() {
        XCTAssertEqual(MapLabelLayout.scale(for: .xSmall), 1)
        XCTAssertEqual(MapLabelLayout.scale(for: .large), 1)
        XCTAssertGreaterThan(MapLabelLayout.scale(for: .xxxLarge),
                             MapLabelLayout.scale(for: .xLarge))
        XCTAssertEqual(MapLabelLayout.scale(for: .accessibility1), 1.4)
        XCTAssertEqual(MapLabelLayout.scale(for: .accessibility5), 1.4)
        XCTAssertEqual(MapLabelLayout.labelBox(centre: .zero, textWidth: 40).height, 16)
        XCTAssertEqual(MapLabelLayout.countryBox(centre: .zero, width: 40).height, 16)
        XCTAssertGreaterThan(
            MapLabelLayout.labelBox(centre: .zero, textWidth: 40, scale: 1.4).height, 16)
    }

    /// The card promises the loan Core writes, not a copy of it typed by hand.
    @MainActor
    func testRescueTermsAreCoresTerms() {
        XCTAssertEqual(RescueOfferCard.rate,
                       Format.percent(Double(RescueOffer.annualRateBasisPoints) / 10_000))
        XCTAssertTrue(RescueOfferCard.terms.contains("\(RescueOffer.termMonths) months"),
                      RescueOfferCard.terms)
    }

    /// Only bad rival news is filed under "Needs you now".
    @MainActor
    func testOnlyBadRivalNewsIsUrgent() {
        XCTAssertTrue(RivalPressureCard.needsAction(.trailing(routes: 1, contested: 2)))
        XCTAssertFalse(RivalPressureCard.needsAction(.leading(contested: 2)))
        XCTAssertFalse(RivalPressureCard.needsAction(.fighting(contested: 1)))
    }
}
