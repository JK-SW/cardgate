import CardGateKit
import Foundation
import Testing

struct InstancePolicyTests {
    let app = URL(filePath: "/Applications/CardGate.app")

    /// The PIN dialog of a client left behind runs CardGate's executable without a Dock icon; it
    /// must not keep CardGate from starting.
    @Test func pinDialogIsNoOtherInstance() {
        let running = [
            RunningInstance(pid: 10, isRegularApp: true, bundleURL: app),
            RunningInstance(pid: 20, isRegularApp: false, bundleURL: app),
        ]
        #expect(InstancePolicy.otherInstance(among: running, current: 10) == nil)
        #expect(InstancePolicy.otherInstance(among: running, current: 30)?.pid == 10)
    }

    @Test func copyElsewhereIsAnotherInstance() {
        let copy = RunningInstance(
            pid: 11, isRegularApp: true, bundleURL: URL(filePath: "/Users/test/Downloads/CardGate.app"))
        #expect(InstancePolicy.otherInstance(among: [copy], current: 12) == copy)
    }

    @Test func endsOnlyOwnClients() {
        let own = RunningInstance(
            pid: 40, isRegularApp: false, bundleURL: FreeRDPCommand.clientApp(in: app))
        let developer = RunningInstance(
            pid: 41, isRegularApp: false,
            bundleURL: URL(filePath: "/Users/test/cardgate/build/helper/Helpers/CardGateSession.app"))
        let unknown = RunningInstance(pid: 42, isRegularApp: false, bundleURL: nil)
        #expect(InstancePolicy.orphanedClients(among: [own, developer, unknown], app: app) == [own])
        #expect(
            InstancePolicy.orphanedClients(among: [own], app: URL(filePath: "/Applications/CardGate.app/")) == [own])
    }
}
