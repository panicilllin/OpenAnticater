import Foundation

/// ANTICATER MINI（USB 514C:8850）改键通道的报文编解码。
///
/// 改键通道是 USB 接口 0（厂商自定义用途页 0xFF00），收发都是报告 ID 3 + 64 字节。
/// 报文格式通过原厂 App（ANTICATER.app 2025-08 版）的反汇编和对实物的只读查询确认，
/// 详见 docs/PROTOCOL.md。本文件中的 payload 都不含开头的报告 ID。
public enum KnobProtocol {
    public static let vendorID = 0x514C
    public static let productID = 0x8850
    public static let usagePage = 0xFF00
    public static let reportID: UInt8 = 0x03
    public static let payloadSize = 64
    /// 老固件（版本 < 10）每条键位记录只使用前 50 字节。
    public static let recordSize = 50
    public static let layers: ClosedRange<UInt8> = 1...3

    enum Command {
        static let info: UInt8 = 0xFB
        static let read: UInt8 = 0xFA
        static let write: UInt8 = 0xFD
        static let lighting: UInt8 = 0xFE
    }

    enum RecordType {
        static let keyboard: UInt8 = 0x01
        static let media: UInt8 = 0x02
        static let mouse: UInt8 = 0x03
        static let lighting: UInt8 = 0x08
    }

    // MARK: - 请求

    /// 查询键数、旋钮数和版本：`FB FB FB`。
    public static func infoRequest() -> [UInt8] {
        padded([Command.info, Command.info, Command.info])
    }

    /// 读取一层的全部键位：`FA 0F 03 <层>`（老固件参数）。旋钮会逐条回复每个键位。
    public static func readLayerRequest(layer: UInt8) -> [UInt8] {
        padded([Command.read, 0x0F, 0x03, layer])
    }

    /// 提交本层改动：`FD FE FF`。
    public static func commitRequest() -> [UInt8] {
        padded([Command.write, 0xFE, 0xFF])
    }

    /// 写一个键位：`FD <键位> <层> <类型> 00×5 <数量> <数据…>`。
    public static func writeRequest(gesture: KnobGesture, layer: UInt8, action: KnobAction) throws -> [UInt8] {
        var p = [UInt8](repeating: 0, count: payloadSize)
        p[0] = Command.write
        p[1] = gesture.rawValue
        p[2] = layer
        switch action {
        case .keys(let strokes):
            guard (1...KnobAction.maxKeys).contains(strokes.count) else {
                throw KnobError.invalidAction(String(localized: "按键数量必须在 1 到 \(KnobAction.maxKeys) 之间", bundle: L10n.bundle))
            }
            p[3] = RecordType.keyboard
            p[9] = UInt8(strokes.count)
            for (i, s) in strokes.enumerated() {
                p[10 + i * 2] = s.modifiers.rawValue
                p[11 + i * 2] = s.usage
            }
        case .media(let usage):
            p[3] = RecordType.media
            p[9] = 1
            p[10] = UInt8(usage & 0xFF)
            p[11] = UInt8(usage >> 8)
        case .mouse(let m):
            p[3] = RecordType.mouse
            p[9] = 1
            p[10] = m.modifiers.rawValue
            p[11] = m.buttons
            p[14] = UInt8(bitPattern: m.wheel)
        case .unknown:
            throw KnobError.invalidAction(String(localized: "不能写入未识别的动作类型", bundle: L10n.bundle))
        }
        return p
    }

    /// 写灯效：`FE B0 <层> 08 00×5 01 00 <模式>`，固定写在 0 号键位。
    ///
    /// 原厂 App 会在高 4 位放颜色，但这台旋钮的固件忽略它（已实测），所以这里写 0。
    public static func lightingRequest(layer: UInt8, lighting: Lighting) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: payloadSize)
        p[0] = Command.lighting
        p[1] = 0xB0
        p[2] = layer
        p[3] = RecordType.lighting
        p[9] = 1
        p[11] = lighting.mode.rawValue
        return p
    }

    // MARK: - 回复

    /// 解析 `03 FB <键数> <旋钮数> <版本> …`。参数含报告 ID。
    public static func parseInfo(_ report: [UInt8]) -> DeviceInfo? {
        guard report.count >= 5, report[0] == reportID, report[1] == Command.info else { return nil }
        return DeviceInfo(keyCount: report[2], knobCount: report[3], version: report[4])
    }

    public struct SlotRecord: Equatable, Sendable {
        public var slot: UInt8
        public var layer: UInt8
        public var action: KnobAction
    }

    /// 解析读取回复 `03 FA <键位> <层> <类型> 00×5 <数量> <数据…>`。参数含报告 ID。
    public static func parseSlot(_ report: [UInt8]) -> SlotRecord? {
        guard report.count >= 16, report[0] == reportID, report[1] == Command.read else { return nil }
        let slot = report[2], layer = report[3], type = report[4]
        let count = Int(report[10])
        let data = Array(report[11...])
        let action: KnobAction
        switch type {
        case RecordType.keyboard where (1...KnobAction.maxKeys).contains(count) && data.count >= count * 2:
            action = .keys((0..<count).map { i in
                KeyStroke(modifiers: Modifiers(rawValue: data[i * 2]), usage: data[i * 2 + 1])
            })
        case RecordType.media where count >= 1:
            action = .media(UInt16(data[0]) | UInt16(data[1]) << 8)
        case RecordType.mouse where count >= 1:
            action = .mouse(MouseAction(modifiers: Modifiers(rawValue: data[0]),
                                        buttons: data[1],
                                        wheel: Int8(bitPattern: data[4])))
        default:
            action = .unknown(type: type, raw: Array(report[5..<min(report.count, 51)]))
        }
        return SlotRecord(slot: slot, layer: layer, action: action)
    }

    static func padded(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [UInt8](repeating: 0, count: payloadSize - bytes.count)
    }
}

public enum KnobError: LocalizedError, Equatable {
    case notConnected
    case timeout
    case ioError(Int32)
    case invalidAction(String)
    case unexpectedReply

    public var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "旋钮没有通过 USB 线连接。", bundle: L10n.bundle)
        case .timeout: String(localized: "旋钮没有回应。", bundle: L10n.bundle)
        case .ioError(let code): String(format: String(localized: "USB 通信出错（0x%08X）。", bundle: L10n.bundle), code)
        case .invalidAction(let msg): msg
        case .unexpectedReply: String(localized: "旋钮的回复无法识别。", bundle: L10n.bundle)
        }
    }
}
