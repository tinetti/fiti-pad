import Testing

@MainActor
@Suite("RemoteControl Status View")
struct RemoteControlStatusTests {
    @Test("status view shows connected state")
    func showsConnectedState() {
        let view = RemoteControlStatusView()
        view.setRemoteController(name: "iPad Air")

        #expect(view.isConnectedPublic)
        #expect(view.controllerNamePublic == "iPad Air")
    }

    @Test("status view updates on disconnection")
    func updatesOnDisconnect() {
        let view = RemoteControlStatusView()
        view.setRemoteController(name: "iPad Air")
        view.setRemoteController(name: nil)

        #expect(!view.isConnectedPublic)
        #expect(view.controllerNamePublic == nil)
    }
}
