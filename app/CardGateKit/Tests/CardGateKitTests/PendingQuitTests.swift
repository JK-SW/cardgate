import CardGateKit
import Foundation
import Testing

struct PendingQuitTests {
    @Test func quitsAtOnceWithoutAConnection() {
        #expect(PendingQuit().decide(sessionRunning: false) == .quitNow)
        #expect(PendingQuit().decide(sessionRunning: true) == .ask)
    }

    /// A second Quit (Dock menu, logout) while waiting for the client must not ask again.
    @Test func secondQuitKeepsWaiting() {
        var quit = PendingQuit()
        quit.begin()
        #expect(quit.decide(sessionRunning: true) == .keepWaiting)
        #expect(quit.decide(sessionRunning: false) == .keepWaiting)
    }

    /// The client's end and the deadline both finish the quit; the system gets one answer.
    @Test func finishesOnce() {
        var quit = PendingQuit()
        let withoutRequest = quit.finish()
        #expect(!withoutRequest, "no quit was requested")
        quit.begin()
        let first = quit.finish()
        let second = quit.finish()
        #expect(first)
        #expect(!second)
        #expect(quit.decide(sessionRunning: true) == .ask)
    }
}

struct PINDialogMessagesTests {
    @Test func acceptsOnlyTheOwnSession() {
        let own = PINDialogMessages.newSessionID()
        #expect(PINDialogMessages.isFrom(session: own, sender: own))
        #expect(!PINDialogMessages.isFrom(session: own, sender: PINDialogMessages.newSessionID()))
        #expect(!PINDialogMessages.isFrom(session: own, sender: nil), "another app's or an old dialog")
        #expect(!PINDialogMessages.isFrom(session: nil, sender: nil), "no connection runs")
    }

    /// The dialog inherits the ID from the client's environment; anything else is no session.
    @Test func readsTheSessionFromTheEnvironment() {
        let id = PINDialogMessages.newSessionID()
        #expect(PINDialogMessages.sessionID(in: [PINDialogMessages.sessionVariable: id]) == id)
        #expect(PINDialogMessages.sessionID(in: [PINDialogMessages.sessionVariable: "1234"]) == nil)
        #expect(PINDialogMessages.sessionID(in: [:]) == nil)
    }

    @Test func namesAreDistinct() {
        let names = PINDialogEvent.allCases.map(\.notification) + [PINDialogMessages.close]
        #expect(Set(names).count == names.count)
    }
}
