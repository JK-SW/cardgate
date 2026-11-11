import CardGateKit
import Testing

struct GatewayCheckScheduleTests {
    let gateway = try! HostAddress(parsing: "rdg.example.com")  // swiftlint:disable:this force_try
    let start = ContinuousClock.now

    @Test func checksANewGatewayAtOnce() {
        var schedule = GatewayCheckSchedule()
        #expect(schedule.decide(gateway: gateway, force: false, now: start) == .init(check: true, resetStatus: true))
    }

    @Test func activationChecksAtMostEveryFiveMinutes() {
        var schedule = GatewayCheckSchedule()
        _ = schedule.decide(gateway: gateway, force: true, now: start)
        #expect(!schedule.decide(gateway: gateway, force: false, now: start + .seconds(299)).check)
        #expect(schedule.decide(gateway: gateway, force: false, now: start + .seconds(300)).check)
    }

    @Test func networkOrConnectionChangesCheckAtOnce() {
        var schedule = GatewayCheckSchedule()
        _ = schedule.decide(gateway: gateway, force: true, now: start)
        #expect(
            schedule.decide(gateway: gateway, force: true, now: start + .seconds(1))
                == .init(check: true, resetStatus: false))
    }

    @Test func correctedAddressDropsTheOldResult() throws {
        var schedule = GatewayCheckSchedule()
        _ = schedule.decide(gateway: gateway, force: true, now: start)
        let corrected = try HostAddress(parsing: "rdg2.example.com")
        #expect(
            schedule.decide(gateway: corrected, force: false, now: start + .seconds(1))
                == .init(check: true, resetStatus: true))
    }

    @Test func noGatewayNoCheck() {
        var schedule = GatewayCheckSchedule()
        #expect(schedule.decide(gateway: nil, force: true, now: start) == .init(check: false, resetStatus: true))
    }
}
