import Foundation
import Network
import Testing

@testable import CardGateKit

struct GatewayReachabilityTests {
    @Test func reachesAListeningPort() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        let ready = AsyncStream<UInt16> { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state, let port = listener.port?.rawValue { continuation.yield(port) }
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        var ports = ready.makeAsyncIterator()
        let port = try #require(await ports.next())
        #expect(await GatewayReachability.probe(host: "127.0.0.1", port: port, timeout: .seconds(5)) == .reachable)
    }

    @Test func closedPortIsUnreachable() async {
        // Port 9 (discard) is not open on a Mac.
        #expect(await GatewayReachability.probe(host: "127.0.0.1", port: 9, timeout: .seconds(2)) == .unreachable)
    }

    @Test func unknownNameIsUnreachable() async throws {
        let gateway = try HostAddress(parsing: "rdg.invalid")
        #expect(await GatewayReachability.probe(gateway, timeout: .seconds(2)) == .unreachable)
    }

    /// Fractions of a second count (a sub-second timeout once fired at once).
    @Test func waitsForTheWholeTimeout() async {
        let clock = ContinuousClock()
        let started = clock.now
        // TEST-NET-1 (RFC 5737): never answers.
        #expect(
            await GatewayReachability.probe(host: "192.0.2.1", port: 443, timeout: .milliseconds(600)) == .unreachable)
        let elapsed = clock.now - started
        #expect(elapsed >= .milliseconds(550) && elapsed < .seconds(3))
    }
}
