public enum AppIdentity {
    /// Matches the bundle identifier so `log show --predicate 'subsystem == …'` finds every log line.
    public static let subsystem = "io.github.dailyxplorer.thock"
}
