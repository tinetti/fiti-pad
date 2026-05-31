// ABOUTME: Protocol-level tests for the browser WebSocket bridge used by iPad remote control.
// ABOUTME: Covers the pieces that make the Pair button observable in Safari/Chrome.

import Foundation
import Testing

@Suite("WebSocket protocol")
struct WebSocketProtocolTests {
    @Test("accept key matches RFC 6455 sample")
    func acceptKeyMatchesRFC6455Sample() {
        let accept = WebSocketFrameCodec.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==")
        #expect(accept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test("decodes masked browser text frame")
    func decodesMaskedBrowserTextFrame() throws {
        let payload = Data("{\"type\":\"pairing\",\"clientId\":\"iPad\",\"pin\":\"1234\",\"remember\":false}".utf8)
        let mask = [UInt8]("mask".utf8)
        var frame = Data([0x81, 0x80 | UInt8(payload.count)])
        frame.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ mask[index % 4])
        }

        let decoded = try WebSocketFrameCodec.decodeTextFrames(from: frame)
        #expect(decoded == [String(data: payload, encoding: .utf8)!])
    }

    @Test("encodes unmasked server text frame")
    func encodesUnmaskedServerTextFrame() throws {
        let frame = WebSocketFrameCodec.encodeText("{\"type\":\"pairResult\",\"ok\":true}")
        #expect(frame.starts(with: Data([0x81, 0x1F])))
        let decoded = try WebSocketFrameCodec.decodeTextFrames(from: frame)
        #expect(decoded == ["{\"type\":\"pairResult\",\"ok\":true}"])
    }
}
