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
        "double..dot", "ünicode.example", "host/path", "a:b:c", "user@host", ".", "pc01.example..",
        ".pc01.example",
    ])
    func rejectsUnsafeOrInvalidHosts(_ text: String) {
        #expect(throws: (any Error).self) { try HostAddress(parsing: text) }
    }

    /// Windows computer names often contain an underscore.
    @Test func acceptsUnderscore() throws {
        #expect(try HostAddress(parsing: "pc_01.corp.example").host == "pc_01.corp.example")
        #expect(try HostAddress(parsing: "PC_01:3390").description == "pc_01:3390")
    }

    /// A fully qualified name may end with a dot; it is dropped.
    @Test func dropsTheDotOfAFullyQualifiedName() throws {
        #expect(try HostAddress(parsing: "pc01.corp.example.").description == "pc01.corp.example")
        #expect(try HostAddress(parsing: "rdg.example.com.:443").description == "rdg.example.com:443")
    }

    @Test(arguments: [
        ("[2001:db8::1]", "2001:db8::1", UInt16?.none), ("[::1]:3390", "::1", 3390), ("[FE80::A]", "fe80::a", nil),
    ])
    func acceptsBracketedIPv6(_ text: String, _ host: String, _ port: UInt16?) throws {
        let address = try HostAddress(parsing: text)
        #expect(address.isIPv6)
        #expect(address.host == host)
        #expect(address.port == port)
        #expect(try HostAddress(parsing: address.description) == address)
    }

    @Test(arguments: ["[2001:db8::1", "[not-an-address]", "[::1]x", "[::1]:", "2001:db8::1", "[::1],x"])
    func rejectsMalformedIPv6(_ text: String) {
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
