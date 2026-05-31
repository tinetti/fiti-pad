import Foundation
import Network

/// Lightweight WebSocket server for remote control using Network.framework.
/// 
/// NOTE: @unchecked Sendable is safe because all mutable state is accessed
/// only from the queue or is immutable after initialization.
public final class WebSocketServer: @unchecked Sendable {
    private let serverPort: UInt16
    private var isRunning = false
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "fiti.remotecontrol")

    private weak var controlPort: RemoteControlPort?
    private let pairingManager: PairingManager

    public init(serverPort: UInt16, controlPort: RemoteControlPort, pairingManager: PairingManager) {
        self.serverPort = serverPort
        self.controlPort = controlPort
        self.pairingManager = pairingManager
    }

    /// Start the WebSocket server using Network.framework
    public func start() async throws {
        print("Remote control WebSocket server starting on port \(serverPort)")
        
        let parameters = NWParameters.tcp
        let endpoint = NWEndpoint.Port(rawValue: serverPort) ?? .any
        
        do {
            listener = try NWListener(using: parameters, on: endpoint)
        } catch {
            print("Failed to create WebSocket listener: \(error)")
            throw error
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let port = self?.listener?.port.map(String.init(describing:)) ?? "unknown"
                print("Remote control WebSocket server ready on port \(port)")
                self?.isRunning = true
            case .failed(let error):
                print("Remote control WebSocket server failed: \(error)")
                self?.isRunning = false
            case .cancelled:
                print("Remote control WebSocket server cancelled")
                self?.isRunning = false
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
        
        // Wait for server to be ready
        let deadline = Date().addingTimeInterval(2)
        while !isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        if !isRunning {
            throw RemoteControlError.serverStartTimeout
        }
    }

    /// Stop the server
    public func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil
        print("Remote control WebSocket server stopped")
    }

    /// Check if the server is running
    public var running: Bool {
        isRunning
    }

    /// Handle new WebSocket connection
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPHandshake(on: connection, buffer: Data())
    }

    /// Receive HTTP handshake and upgrade to WebSocket
    private func receiveHTTPHandshake(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            
            var buf = buffer
            if let d = data { buf.append(d) }
            
            // Detect WebSocket upgrade request
            if let text = String(data: buf, encoding: .utf8),
               text.contains("GET /remote-control") && text.contains("Upgrade: websocket") {
                // Extract Sec-WebSocket-Key and send upgrade response
                if let key = self.extractWebSocketKey(text) {
                    let accept = WebSocketFrameCodec.acceptKey(for: key)
                    let upgradeResponse = "HTTP/1.1 101 Switching Protocols\r\n" +
                                          "Upgrade: websocket\r\n" +
                                          "Connection: Upgrade\r\n" +
                                          "Sec-WebSocket-Accept: \(accept)\r\n" +
                                          "\r\n"
                    connection.send(content: upgradeResponse.data(using: .utf8), completion: .contentProcessed { _ in
                        self.sendJSON(["type": "pairChallenge", "pin": self.pairingManager.currentPin], on: connection)
                        self.receiveWebSocketData(on: connection, buffer: Data())
                    })
                } else {
                    connection.cancel()
                }
                return
            }
            
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            
            self.receiveHTTPHandshake(on: connection, buffer: buf)
        }
    }

    /// Extract Sec-WebSocket-Key from handshake request
    private func extractWebSocketKey(_ request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        for line in lines where line.lowercased().hasPrefix("sec-websocket-key:") {
            return line.dropFirst("Sec-WebSocket-Key:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Receive WebSocket data messages
    private func receiveWebSocketData(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            
            if let data, !data.isEmpty {
                do {
                    for text in try WebSocketFrameCodec.decodeTextFrames(from: data) {
                        self.handleReceivedText(text, on: connection)
                    }
                } catch {
                    print("WebSocket frame error: \(error)")
                    connection.cancel()
                    return
                }
            }
            
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            
            // Continue receiving
            self.receiveWebSocketData(on: connection, buffer: Data())
        }
    }

    /// Process incoming text message (WebSocket data)
    public func handleReceivedText(_ text: String, on connection: NWConnection? = nil) {
        guard let data = text.data(using: .utf8) else {
            print("Invalid UTF-8 received")
            return
        }

        do {
            let action = try parseRemoteAction(from: data)

            // Pairing handshake handling
            if case .pairing(let clientId, let pin, let remember) = action {
                handlePairing(clientId: clientId, pin: pin, remember: remember, on: connection)
                return
            }

            // Auth check for non-pairing messages
            guard pairingManager.isClientAuthenticated else {
                print("Authentication required")
                sendJSON(["type": "error", "message": "Pairing required"], on: connection)
                return
            }

            // Forward to port on main actor (async call)
            Task {
                @MainActor in
                self.controlPort?.remote_handleAction(action)
            }
            sendJSON(["type": "ack"], on: connection)

        } catch {
            print("Parse error: \(error)")
            sendJSON(["type": "error", "message": "Invalid message"], on: connection)
        }
    }

    private func handlePairing(clientId: String, pin: String, remember: Bool, on connection: NWConnection?) {
        if pairingManager.verifyPin(pin) {
            let token = pairingManager.issueToken(clientId: clientId, remember: remember)
            pairingManager.addAuthenticatedClient(token: token)
            pairingManager.setClientName(clientId)
            print("Pairing successful for \(clientId)")
            sendJSON([
                "type": "pairResult",
                "ok": true,
                "token": token,
                "controllerName": clientId
            ], on: connection)
        } else {
            print("Invalid PIN from \(clientId)")
            sendJSON(["type": "pairResult", "ok": false, "message": "Invalid PIN"], on: connection)
        }
    }

    private func sendJSON(_ payload: [String: Any], on connection: NWConnection?) {
        guard let connection,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        connection.send(content: WebSocketFrameCodec.encodeText(text), completion: .contentProcessed { _ in })
    }
}

public enum RemoteControlError: Error {
    case serverStartTimeout
    case invalidState
}
