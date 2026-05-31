import Foundation
import Testing

@MainActor
@Suite("RemoteControl parsing")
struct RemoteControlTests {
    private func data(_ json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [])
    }

    @Test("parse startStroke message")
    func parseStartStroke() throws {
        let json: [String: Any] = [
            "type": "startStroke",
            "strokeId": "abc123",
            "tool": "pen",
            "color": "#FF00FF",
            "width": 3.0,
            "point": ["x": 0.1, "y": 0.9, "pressure": 0.7, "t": 123.456]
        ]
        let action = try parseRemoteAction(from: data(json))
        guard case .startStroke(let s) = action else {
            Issue.record("expected startStroke, got \(action)")
            return
        }
        #expect(s.strokeId == "abc123")
        #expect(s.tool == RemoteTool.pen)
        #expect(s.color == "#FF00FF")
        #expect(s.width == 3.0)
        #expect(s.point.x == 0.1)
        #expect(s.point.y == 0.9)
        #expect(s.point.pressure == 0.7)
    }

    @Test("parse appendPoints message")
    func parseAppendPoints() throws {
        let json: [String: Any] = [
            "type": "appendPoints",
            "strokeId": "s1",
            "points": [["x": 0.2, "y": 0.3, "pressure": 0.5], ["x": 0.25, "y": 0.35]]
        ]
        let action = try parseRemoteAction(from: data(json))
        guard case .appendPoints(let a) = action else {
            Issue.record("expected appendPoints, got \(action)")
            return
        }
        #expect(a.strokeId == "s1")
        #expect(a.points.count == 2)
        #expect(a.points[0].pressure == 0.5)
        #expect(a.points[1].pressure == nil)
    }

    @Test("parse endStroke message")
    func parseEndStroke() throws {
        let action = try parseRemoteAction(from: data(["type": "endStroke", "strokeId": "s1"]))
        guard case .endStroke(let id) = action else {
            Issue.record("expected endStroke, got \(action)")
            return
        }
        #expect(id == "s1")
    }

    @Test("parse pairing message")
    func parsePairing() throws {
        let action = try parseRemoteAction(from: data([
            "type": "pairing",
            "clientId": "iPad",
            "pin": "1234",
            "remember": true
        ]))
        #expect(action == .pairing(clientId: "iPad", pin: "1234", remember: true))
    }

    @Test("parse undo/redo")
    func parseUndoRedo() throws {
        let undo = try parseRemoteAction(from: data(["type": "undo"]))
        let redo = try parseRemoteAction(from: data(["type": "redo"]))
        #expect(undo == .undo)
        #expect(redo == .redo)
    }

    @Test("invalid messages produce errors")
    func parseInvalid() {
        let data = Data("notjson".utf8)
        var didThrow = false
        do {
            _ = try parseRemoteAction(from: data)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }
}
