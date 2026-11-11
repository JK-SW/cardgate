/// When the app checks in the background whether the selected connection's gateway can be
/// reached (`GatewayReachability`): on start, network and connection changes (`force`); when the
/// app is activated again at most every 5 minutes – so the gateway is not bothered needlessly.
public struct GatewayCheckSchedule: Sendable {
    public static let minimumInterval: Duration = .seconds(300)

    /// The gateway the last check was for.
    public private(set) var gateway: HostAddress?
    private var lastCheck: ContinuousClock.Instant?

    public struct Decision: Equatable, Sendable {
        /// Start a check now.
        public var check: Bool
        /// Forget the shown result: it belongs to another (e.g. corrected) gateway or there is none.
        public var resetStatus: Bool

        public init(check: Bool, resetStatus: Bool) {
            self.check = check
            self.resetStatus = resetStatus
        }
    }

    public init() {}

    public mutating func decide(
        gateway: HostAddress?, force: Bool, now: ContinuousClock.Instant = .now
    ) -> Decision {
        let changed = gateway != self.gateway
        self.gateway = gateway
        guard gateway != nil else {
            lastCheck = nil
            return Decision(check: false, resetStatus: true)
        }
        if !force, !changed, let lastCheck, now - lastCheck < Self.minimumInterval {
            return Decision(check: false, resetStatus: false)
        }
        lastCheck = now
        return Decision(check: true, resetStatus: changed)
    }
}
