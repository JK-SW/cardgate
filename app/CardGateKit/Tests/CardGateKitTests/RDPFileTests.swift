import CardGateKit
import Foundation
import Testing

struct RDPFileTests {
    static let sample = """
        screen mode id:i:2
        use multimon:i:0
        desktopwidth:i:1920
        desktopheight:i:1080
        full address:s:pc01.corp.example
        gatewayhostname:s:rdg.example.com
        gatewayusagemethod:i:1
        gatewaycredentialssource:i:1
        redirectclipboard:i:1
        audiomode:i:0
        prompt for credentials:i:0
        """

    /// mstsc saves .rdp files as UTF-16LE with a byte order mark and CRLF line endings.
    static func mstscData(_ text: String) -> Data {
        var data = Data([0xFF, 0xFE])
        data.append(
            contentsOf: Array(text.replacingOccurrences(of: "\n", with: "\r\n").utf16).flatMap {
                [UInt8($0 & 0xFF), UInt8($0 >> 8)]
            })
        return data
    }

    @Test func readsUTF16WithBOM() throws {
        let file = try RDPFile(data: Self.mstscData(Self.sample))
        #expect(file["full address"] == "pc01.corp.example")
        #expect(file["GatewayHostname"] == "rdg.example.com")
    }

    @Test func readsUTF8() throws {
        let file = try RDPFile(data: Data(Self.sample.utf8))
        #expect(file["desktopwidth"] == "1920")
    }

    @Test func makesProfile() throws {
        let profile = try RDPFile(data: Self.mstscData(Self.sample)).makeProfile(name: "Office")
        #expect(profile.name == "Office")
        #expect(profile.computer.description == "pc01.corp.example")
        #expect(profile.gateway?.description == "rdg.example.com")
        #expect(profile.display.mode == .fullScreen)
        #expect(profile.display.windowSize == WindowSize(width: 1920, height: 1080))
        #expect(profile.redirection.clipboard)
        #expect(profile.redirection.audio)
        #expect(profile.pkcs11Module == nil)
    }

    @Test func multimonAndWindowedModes() throws {
        let multi = try RDPFile(data: Data("full address:s:pc\nscreen mode id:i:2\nuse multimon:i:1".utf8))
            .makeProfile(name: "x")
        #expect(multi.display.mode == .allDisplays)
        let windowed = try RDPFile(data: Data("full address:s:pc\nscreen mode id:i:1".utf8)).makeProfile(name: "x")
        #expect(windowed.display.mode == .window)
    }

    @Test func gatewayDisabledByUsageMethod() throws {
        let text = "full address:s:pc01.corp.example\ngatewayhostname:s:rdg.example.com\ngatewayusagemethod:i:0"
        let profile = try RDPFile(data: Data(text.utf8)).makeProfile(name: "x")
        #expect(profile.gateway == nil)
    }

    @Test func keepsPortInFullAddress() throws {
        let profile = try RDPFile(data: Data("full address:s:pc01.corp.example:3390".utf8)).makeProfile(name: "x")
        #expect(profile.computer.port == 3390)
    }

    @Test func valueMayContainColons() throws {
        let file = try RDPFile(data: Data("alternate shell:s:C:\\Windows\\explorer.exe".utf8))
        #expect(file["alternate shell"] == "C:\\Windows\\explorer.exe")
    }

    @Test func missingComputerIsAnError() throws {
        let file = try RDPFile(data: Data("gatewayhostname:s:rdg.example.com".utf8))
        #expect(throws: RDPFile.ReadError.missingComputer) { try file.makeProfile(name: "x") }
    }

    @Test func invalidAddressIsAnError() throws {
        let file = try RDPFile(data: Data("full address:s:bad,host".utf8))
        #expect(throws: RDPFile.ReadError.invalidAddress("bad,host")) { try file.makeProfile(name: "x") }
    }

    @Test func audioAndClipboardOff() throws {
        let text = "full address:s:pc\nredirectclipboard:i:0\naudiomode:i:2"
        let profile = try RDPFile(data: Data(text.utf8)).makeProfile(name: "x")
        #expect(!profile.redirection.clipboard)
        #expect(!profile.redirection.audio)
    }

    @Test func ignoresGarbageLines() throws {
        let file = try RDPFile(data: Data("garbage\n:s:empty name\nfull address:s:pc\n".utf8))
        #expect(file.settings == ["full address": "pc"])
    }
}
