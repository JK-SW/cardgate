import Foundation
import Network

/// A light check whether the gateway's port can be reached: a TCP connection that is closed right
/// away, without TLS or any request, so it does not load the gateway or fill its web server logs.
/// It tells a missing internet connection, a wrong address or a firewall apart from a reachable
/// gateway; the certificate is checked when connecting (`GatewayCheckResult`).
public enum GatewayReachability: Equatable, Sendable {
    case reachable
    case unreachable

    /// HTTPS port of an RD Gateway unless the address names another one.
    public static let defaultPort: UInt16 = 443

    public static func probe(_ gateway: HostAddress, timeout: Duration = .seconds(5)) async -> GatewayReachability {
        await probe(host: gateway.host, port: gateway.port ?? defaultPort, timeout: timeout)
    }

    static func probe(host: String, port: UInt16, timeout: Duration) async -> GatewayReachability {
        guard let port = NWEndpoint.Port(rawValue: port) else { return .unreachable }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "io.github.jk-sw.cardgate.gateway-probe")
        let result = Once()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                @Sendable func finish(_ value: GatewayReachability) {
                    guard result.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: value)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: finish(.reachable)
                    case .failed, .cancelled: finish(.unreachable)
                    // .waiting (no route yet, name not found, refused) may be temporary right after
                    // a network change: the connection retries until the timeout decides.
                    default: break
                    }
                }
                connection.start(queue: queue)
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                queue.asyncAfter(deadline: .now() + seconds) { finish(.unreachable) }
            }
        } onCancel: {
            connection.cancel()  // a superseded check closes its connection at once
        }
    }
}

/// Lets exactly one of several racing callbacks finish.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
