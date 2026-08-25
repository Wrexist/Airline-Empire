/// A starting scenario / difficulty preset (docs/GAME_DESIGN.md §5):
/// difficulty is the world you start in, never a mid-game slider.
public struct ScenarioSpec: Equatable, Codable, Sendable {
    public let code: ScenarioCode
    public let name: String
    public let blurb: String
    public let startYear: Int
    public let playerStartingCash: Money
    public let competitorCount: Int
    public let competitorStartingCash: Money

    public init(code: ScenarioCode, name: String, blurb: String, startYear: Int,
                playerStartingCash: Money, competitorCount: Int,
                competitorStartingCash: Money) {
        self.code = code
        self.name = name
        self.blurb = blurb
        self.startYear = startYear
        self.playerStartingCash = playerStartingCash
        self.competitorCount = competitorCount
        self.competitorStartingCash = competitorStartingCash
    }
}
