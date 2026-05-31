import CryptoKit
import Foundation

/// Minimal RFC 6455 helpers for the browser-based remote-control transport.
/// Supports complete, non-fragmented text frames, which is all the iPad client sends.
enum WebSocketFrameCodec {
    enum Error: Swift.Error, Equatable {
        case incompleteFrame
        case unsupportedOpcode(UInt8)
        case invalidUTF8
    }

    private struct Header {
        let opcode: UInt8
        let isMasked: Bool
        let length: Int
    }

    static func acceptKey(for key: String) -> String {
        let magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(magic.utf8))
        return Data(digest).base64EncodedString()
    }

    static func encodeText(_ text: String) -> Data {
        var frame = Data([0x81]) // FIN + text opcode
        let payload = Data(text.utf8)
        appendLength(payload.count, masked: false, to: &frame)
        frame.append(payload)
        return frame
    }

    static func decodeTextFrames(from data: Data) throws -> [String] {
        let bytes = [UInt8](data)
        var index = 0
        var messages: [String] = []

        while index < bytes.count {
            if let message = try decodeTextFrame(from: bytes, index: &index) {
                messages.append(message)
            }
        }

        return messages
    }

    private static func decodeTextFrame(from bytes: [UInt8], index: inout Int) throws -> String? {
        let header = try readHeader(from: bytes, index: &index)
        guard header.opcode == 0x1 else {
            if header.opcode == 0x8 { return nil } // close frame
            throw Error.unsupportedOpcode(header.opcode)
        }

        let mask = try readMask(from: bytes, index: &index, isMasked: header.isMasked)
        var payload = try readPayload(from: bytes, index: &index, length: header.length)
        apply(mask: mask, to: &payload)

        guard let message = String(data: Data(payload), encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        return message
    }

    private static func readHeader(from bytes: [UInt8], index: inout Int) throws -> Header {
        guard bytes.count - index >= 2 else { throw Error.incompleteFrame }
        let opcode = bytes[index] & 0x0F
        index += 1

        let second = bytes[index]
        let isMasked = (second & 0x80) != 0
        var length = Int(second & 0x7F)
        index += 1

        if length == 126 {
            length = try readUInt16Length(from: bytes, index: &index)
        } else if length == 127 {
            length = try readUInt64Length(from: bytes, index: &index)
        }

        return Header(opcode: opcode, isMasked: isMasked, length: length)
    }

    private static func readUInt16Length(from bytes: [UInt8], index: inout Int) throws -> Int {
        guard bytes.count - index >= 2 else { throw Error.incompleteFrame }
        defer { index += 2 }
        return (Int(bytes[index]) << 8) | Int(bytes[index + 1])
    }

    private static func readUInt64Length(from bytes: [UInt8], index: inout Int) throws -> Int {
        guard bytes.count - index >= 8 else { throw Error.incompleteFrame }
        var length = 0
        for byte in bytes[index..<(index + 8)] {
            length = (length << 8) | Int(byte)
        }
        index += 8
        return length
    }

    private static func readMask(from bytes: [UInt8], index: inout Int, isMasked: Bool) throws -> [UInt8] {
        guard isMasked else { return [] }
        guard bytes.count - index >= 4 else { throw Error.incompleteFrame }
        defer { index += 4 }
        return Array(bytes[index..<(index + 4)])
    }

    private static func readPayload(from bytes: [UInt8], index: inout Int, length: Int) throws -> [UInt8] {
        guard bytes.count - index >= length else { throw Error.incompleteFrame }
        defer { index += length }
        return Array(bytes[index..<(index + length)])
    }

    private static func apply(mask: [UInt8], to payload: inout [UInt8]) {
        guard !mask.isEmpty else { return }
        for payloadIndex in payload.indices {
            payload[payloadIndex] ^= mask[payloadIndex % 4]
        }
    }

    private static func appendLength(_ length: Int, masked: Bool, to frame: inout Data) {
        let maskBit: UInt8 = masked ? 0x80 : 0
        if length <= 125 {
            frame.append(maskBit | UInt8(length))
        } else if length <= UInt16.max {
            frame.append(maskBit | 126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
    }
}
