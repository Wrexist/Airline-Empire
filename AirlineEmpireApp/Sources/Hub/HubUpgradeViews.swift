import SwiftUI
import AirlineEmpireCore

// Upgrading from inside the Hub View (docs/HUB_HANDOFF.md §0c): the card
// beside a facility site, the tag floating over it, and the toast when a
// building opens.

extension HubFacilityKind {
    var systemImage: String {
        switch self {
        case .lounge: "sofa.fill"
        case .groundServices: "box.truck.fill"
        }
    }
}

/// The upgrade card: what stands on the site, what the next level builds,
/// what it does and costs, and the button that orders it. Ordering takes
/// two taps — the first arms the button with the price — because the
/// installation is not refundable.
@available(iOS 18.0, *)
struct HubUpgradeCard: View {
    @Bindable var model: HubScreenModel
    let kind: HubFacilityKind
    let mode: HubChromeMode
    @State private var armed = false

    /// A phone on its side has about 380 pt under the top bar: the card
    /// drops the fine print to fit.
    private var compact: Bool { mode == .landscape }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if let offer = model.offer(kind) {
                header(offer)
                levels(offer)
                now(offer)
                if let next = offer.next {
                    nextLevel(offer, next)
                    action(offer, next)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(HubChromeStyle.good)
                        Text("Fully built. \(Format.money(Money(cents: offer.monthlyCents))) a month.")
                            .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(HubChromeStyle.goodSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Text("Start an airline to build here.")
                    .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
            }
        }
        .frame(width: mode == .regular ? 340 : 300)
        .hubGlass(padding: compact ? 11 : 14)
        .onChange(of: model.offer(kind)?.level) { _, _ in armed = false }
    }

    private func header(_ offer: HubUpgradeOffer) -> some View {
        HStack(spacing: 10) {
            HubIconTile(systemName: kind.systemImage, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.title).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                Text(offer.buildingName).font(.system(size: 16, weight: .bold)).foregroundStyle(HubChromeStyle.ink)
                    .contentTransition(.opacity)
                    // On the title, not the card: an identifier on the card
                    // would be inherited by its build button.
                    .accessibilityIdentifier("ae-hub-upgrade-card")
            }
            Spacer()
            Button {
                withAnimation(HubMotion.panel) { model.panel = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HubChromeStyle.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.6), in: Circle())
            }
            .buttonStyle(HubPressStyle())
            .accessibilityLabel("Close upgrade")
        }
    }

    /// Three steps, the built ones filled, the next one outlined.
    private func levels(_ offer: HubUpgradeOffer) -> some View {
        HStack(spacing: 6) {
            ForEach(0...offer.maxLevel, id: \.self) { level in
                let built = level <= offer.level
                let next = level == offer.level + 1
                VStack(spacing: 4) {
                    Capsule()
                        .fill(built ? HubChromeStyle.accent : HubChromeStyle.track)
                        .overlay(Capsule().strokeBorder(next ? HubChromeStyle.accent : .clear,
                                                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                        .frame(height: 6)
                    Text(AirportService.levelName(level))
                        .font(.system(size: 10, weight: level == offer.level ? .semibold : .regular))
                        .foregroundStyle(level == offer.level ? HubChromeStyle.ink : HubChromeStyle.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(HubMotion.data, value: offer.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(offer.level) of \(offer.maxLevel), \(offer.levelName)")
    }

    private func now(_ offer: HubUpgradeOffer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NOW").font(.system(size: 10, weight: .bold)).kerning(0.6).foregroundStyle(HubChromeStyle.tertiary)
            Text(offer.effect).font(.system(size: 12)).foregroundStyle(HubChromeStyle.ink)
            if offer.level > 0 && !compact {
                Text("\(Format.money(Money(cents: offer.monthlyCents))) a month")
                    .font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextLevel(_ offer: HubUpgradeOffer, _ next: HubUpgradeOffer.Next) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("NEXT").font(.system(size: 10, weight: .bold)).kerning(0.6).foregroundStyle(HubChromeStyle.accent)
                Text(next.buildingName).font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
            }
            Label(next.effect, systemImage: "arrow.up.right.circle.fill")
                .font(.system(size: 12)).foregroundStyle(HubChromeStyle.good)
            if !compact {
                Text(offer.scope).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                cost("Build, once", Format.money(Money(cents: next.installationCents)))
                cost("Monthly", "\(Format.money(Money(cents: offer.monthlyCents))) → \(Format.money(Money(cents: next.monthlyCents)))")
            }
        }
        .padding(compact ? 8 : 10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cost(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
            Text(value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(HubChromeStyle.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func action(_ offer: HubUpgradeOffer, _ next: HubUpgradeOffer.Next) -> some View {
        if model.pendingUpgrade == kind {
            HStack(spacing: 8) {
                ProgressView().tint(HubChromeStyle.accent)
                Text("Building \(next.buildingName.lowercased())…")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(HubChromeStyle.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if armed {
                        armed = false
                        withAnimation(HubMotion.panel) { model.build(kind) }
                    } else {
                        withAnimation(HubMotion.snap) { armed = true }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: armed ? "checkmark.circle.fill" : "hammer.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(armed ? "Confirm · \(Format.money(Money(cents: next.installationCents)))"
                                   : "Build \(next.levelName.lowercased())")
                            .contentTransition(.opacity)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(offer.canUpgrade ? (armed ? HubChromeStyle.good : HubChromeStyle.accent) : HubChromeStyle.tertiary,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(HubPressStyle())
                .disabled(!offer.canUpgrade)
                .accessibilityIdentifier("ae-hub-upgrade-build")
                if let blocked = offer.blocked ?? model.upgradeError {
                    Label(blocked, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(HubChromeStyle.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else if armed {
                    Text("Installation is not refundable.")
                        .font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                }
            }
        }
    }
}

/// The tag floating over a facility site in the overview.
struct HubFacilityTagView: View {
    let tag: HubFacilityTag

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tag.building ? "hammer.fill" : tag.kind.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(tag.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                Text(tag.building ? "Under construction" : tag.next)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tag.canUpgrade ? HubChromeStyle.accent : HubChromeStyle.secondary)
            }
            if tag.canUpgrade && !tag.building {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 13)).foregroundStyle(HubChromeStyle.accent)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 4)
        .padding(.trailing, 9)
        .frame(height: 32)
        .background(Color.white.opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(tag.canUpgrade ? 0.7 : 0.3), lineWidth: 1.5))
        .shadow(color: HubChromeStyle.panelShadow, radius: 6, y: 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(tint.opacity(0.6)).frame(width: 1.5, height: 12).offset(y: 12)
        }
    }

    private var tint: Color {
        tag.building ? HubChromeStyle.warn : tag.maxed ? HubChromeStyle.good : HubChromeStyle.accent
    }
}

/// "Flagship lounge open at ARN", for a few seconds under the top bar.
struct HubToastView: View {
    let toast: HubToast

    var body: some View {
        HStack(spacing: 10) {
            HubIconTile(systemName: toast.systemImage, tint: HubChromeStyle.good, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                Text(toast.detail).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
            }
            .lineLimit(1)
        }
        .padding(.trailing, 6)
        .hubGlass(radius: 18, padding: 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ae-hub-toast")
    }
}
