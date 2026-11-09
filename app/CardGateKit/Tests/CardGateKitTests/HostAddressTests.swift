import CardGateKit
import Foundation
import Testing

struct HostAddressTests {
    @Test(arguments: ["pc01.corp.example", "gateway.example.com", "10.0.0.5", "localhost", "a-b.example"])
    func acceptsPlainHosts(_ text: String) throws {
        let address = try HostAddress(parsing: text)
        #expect(address.host == text)
        #expect(address.port == nil)
        #expect(address.description == text)
    }

    @Test func parsesPortAndNormalizesCase() throws {
        let address = try HostAddress(parsing: "  RDG.Example.COM:8443 ")
        #expect(address.host == "rdg.example.com")
        #expect(address.port == 8443)
        #expect(address.description == "rdg.example.com:8443")
    }

    @Test(arguments: [
        "host,with,comma", "two words", "host;rm", "-leading.example", "trailing-.example",
        "double..dot", "ünicode.example", "host/path", "a:b:c", "user@host",
    ])
    func rejectsUnsafeOrInvalidHosts(_ text: String) {
        #expect(throws: (any Error).self) { try HostAddress(parsing: text) }
    }

    @Test func rejectsEmpty() {
        #expect(throws: HostAddress.ParseError.empty) { try HostAddress(parsing: "   ") }
    }

    @Test(arguments: ["host:0", "host:65536", "host:abc", "host:"])
    func rejectsInvalidPorts(_ text: String) {
        #expect(throws: HostAddress.ParseError.invalidPort) { try HostAddress(parsing: text) }
    }

    @Test func roundTripsThroughJSON() throws {
        let address = try HostAddress(parsing: "gw.example.com:443")
        let data = try JSONEncoder().encode([address])
        #expect(data == Data(#"["gw.example.com:443"]"#.utf8))
        #expect(try JSONDecoder().decode([HostAddress].self, from: data) == [address])
    }

    @Test func rejectsInvalidJSONValue() {
        let data = Data(#"["bad,host"]"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([HostAddress].self, from: data) }
    }
}
