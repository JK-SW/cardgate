import CardGateKit
import Testing

struct ClientStopTests {
    /// Records what `ClientStop.run` does without a real process or waiting.
    final class Recorder: @unchecked Sendable {
        var calls: [String] = []
        var waited: Duration?
    }

    func run(connected: Bool = true, stillRunning: Bool, cancelled: Bool = false) async -> Recorder {
        let recorder = Recorder()
        await ClientStop.run(
            connected: connected,
            terminate: { recorder.calls.append("terminate") },
            isRunning: { stillRunning },
            kill: { recorder.calls.append("kill") },
            sleep: { duration in
                recorder.waited = duration
                if cancelled { throw CancellationError() }
            })
        return recorder
    }

    @Test func killsAClientThatDoesNotQuit() async {
        let recorder = await run(stillRunning: true)
        #expect(recorder.calls == ["terminate", "kill"])
        #expect(recorder.waited == ClientStop.gracePeriod(connected: true))
    }

    @Test func leavesAClientThatQuit() async {
        let recorder = await run(stillRunning: false)
        #expect(recorder.calls == ["terminate"])
    }

    @Test func cancelledWaitKillsNothing() async {
        let recorder = await run(stillRunning: true, cancelled: true)
        #expect(recorder.calls == ["terminate"])
    }

    /// Cancel while connecting should be quick; a connected client may disconnect cleanly.
    @Test func cancellingIsQuickerThanDisconnecting() async {
        let recorder = await run(connected: false, stillRunning: true)
        #expect(recorder.waited == ClientStop.gracePeriod(connected: false))
        #expect(ClientStop.gracePeriod(connected: false) < ClientStop.gracePeriod(connected: true))
        #expect(ClientStop.quitDeadline(connected: true) > ClientStop.gracePeriod(connected: true))
    }
}
