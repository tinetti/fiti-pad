import Foundation

/// Handler that wires up the WebSocket server with RemoteControlPort and PairingManager
@MainActor
public final class RemoteControlWebSocketHandler {
    private let controlPort: RemoteControlPort
    private let pairingManager: PairingManager
    private var server: WebSocketServer?

    public init(controlPort: RemoteControlPort, pairingManager: PairingManager) {
        self.controlPort = controlPort
        self.pairingManager = pairingManager
    }

    public func start(port: UInt16) async throws {
        let server = WebSocketServer(
            serverPort: port,
            controlPort: controlPort,
            pairingManager: pairingManager
        )
        try await server.start()
        self.server = server
    }

    public func stop() {
        server?.stop()
        server = nil
    }

    public var isRunning: Bool {
        server?.running == true
    }
}
