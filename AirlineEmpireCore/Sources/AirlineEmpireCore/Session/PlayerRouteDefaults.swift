/// The schedule used by route creation and its opportunity forecast.
public enum PlayerRouteDefaults {
    public static let dailyRoundTrips = 2
    public static let forecastAssumptions =
        "Estimate for 2 daily round trips at the standard fare and service, "
        + "including lease and route payroll, before airline overhead. "
        + "Demand, competitors and operating conditions can change the result."
}
