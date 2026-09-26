/// The schedule used by route creation and its opportunity forecast.
public enum PlayerRouteDefaults {
    public static let dailyRoundTrips = 2
    /// The part of the assumptions that has to sit *beside* each figure:
    /// what schedule it is for, and that overhead is not in it. The rest of
    /// `forecastAssumptions` is the same for every opportunity, so a list
    /// shows it once rather than under each row (release audit AUD-04).
    public static let forecastBasis =
        "\(dailyRoundTrips) daily round trips, before airline overhead"
    public static let forecastAssumptions =
        "Estimate for 2 daily round trips at the standard fare and service, "
        + "including lease and route payroll, before airline overhead. "
        + "Demand, competitors and operating conditions can change the result."
}
