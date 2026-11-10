import CardGateKit
import Foundation
import Testing

struct DonationPromptTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    func freshDefaults() throws -> UserDefaults {
        let name = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func offeredOnlyAfterEnoughConnectionsAndDays() throws {
        let prompt = DonationPrompt(defaults: try freshDefaults())
        for _ in 1..<DonationPrompt.requiredConnections {
            prompt.recordSuccessfulConnection(at: start)
        }
        #expect(!prompt.isDue(at: start.addingTimeInterval(30 * day)))  // one connection short
        prompt.recordSuccessfulConnection(at: start.addingTimeInterval(day))
        #expect(!prompt.isDue(at: start.addingTimeInterval(6 * day)))  // too early
        #expect(prompt.isDue(at: start.addingTimeInterval(7 * day)))
    }

    @Test func neverAgainAfterClosing() throws {
        let prompt = DonationPrompt(defaults: try freshDefaults())
        for _ in 0..<DonationPrompt.requiredConnections { prompt.recordSuccessfulConnection(at: start) }
        prompt.finish()
        prompt.recordSuccessfulConnection(at: start)
        #expect(!prompt.isDue(at: start.addingTimeInterval(100 * day)))
    }

    @Test func administratorsCanTurnItOff() throws {
        let defaults = try freshDefaults()
        let prompt = DonationPrompt(defaults: defaults)
        for _ in 0..<DonationPrompt.requiredConnections { prompt.recordSuccessfulConnection(at: start) }
        defaults.set(true, forKey: DonationPrompt.disabledKey)
        #expect(!prompt.isDue(at: start.addingTimeInterval(100 * day)))
    }

    @Test func linksPointToTheProject() {
        #expect(ProjectLinks.sourceCode.host() == "github.com")
        #expect(ProjectLinks.donation.scheme == "https")
    }
}
