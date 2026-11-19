import Foundation

/// 多媒体键（Consumer 用途页 0x0C）。
public enum ConsumerUsage {
    public static let brightnessUp: UInt16 = 0x006F
    public static let brightnessDown: UInt16 = 0x0070
    public static let nextTrack: UInt16 = 0x00B5
    public static let previousTrack: UInt16 = 0x00B6
    public static let stop: UInt16 = 0x00B7
    public static let playPause: UInt16 = 0x00CD
    public static let mute: UInt16 = 0x00E2
    public static let volumeUp: UInt16 = 0x00E9
    public static let volumeDown: UInt16 = 0x00EA
    public static let browserBack: UInt16 = 0x0224
    public static let browserForward: UInt16 = 0x0225
    public static let browserRefresh: UInt16 = 0x0227

    public struct Item: Identifiable, Hashable, Sendable {
        public let usage: UInt16
        public let name: String
        public let symbol: String
        public var id: UInt16 { usage }
    }

    /// 界面里可选的多媒体键，顺序即菜单顺序。
    // 计算属性而不是 static let：切换语言后要重新取翻译。
    public static var all: [Item] { [
        Item(usage: volumeUp, name: String(localized: "音量 +", bundle: L10n.bundle), symbol: "speaker.wave.3"),
        Item(usage: volumeDown, name: String(localized: "音量 −", bundle: L10n.bundle), symbol: "speaker.wave.1"),
        Item(usage: mute, name: String(localized: "静音", bundle: L10n.bundle), symbol: "speaker.slash"),
        Item(usage: playPause, name: String(localized: "播放 / 暂停", bundle: L10n.bundle), symbol: "playpause"),
        Item(usage: nextTrack, name: String(localized: "下一首", bundle: L10n.bundle), symbol: "forward"),
        Item(usage: previousTrack, name: String(localized: "上一首", bundle: L10n.bundle), symbol: "backward"),
        Item(usage: stop, name: String(localized: "停止", bundle: L10n.bundle), symbol: "stop"),
        Item(usage: brightnessUp, name: String(localized: "屏幕亮度 +", bundle: L10n.bundle), symbol: "sun.max"),
        Item(usage: brightnessDown, name: String(localized: "屏幕亮度 −", bundle: L10n.bundle), symbol: "sun.min"),
        Item(usage: browserBack, name: String(localized: "网页后退", bundle: L10n.bundle), symbol: "chevron.backward"),
        Item(usage: browserForward, name: String(localized: "网页前进", bundle: L10n.bundle), symbol: "chevron.forward"),
        Item(usage: browserRefresh, name: String(localized: "网页刷新", bundle: L10n.bundle), symbol: "arrow.clockwise"),
    ] }

    public static func name(_ usage: UInt16) -> String {
        all.first { $0.usage == usage }?.name ?? String(format: String(localized: "多媒体键 0x%04X", bundle: L10n.bundle), usage)
    }
}

/// 键盘键码（HID Keyboard/Keypad 用途页 0x07）。
public enum KeyUsage {
    /// HID 键码 → 显示名称（按 macOS 习惯用符号）。
    public static func name(_ usage: UInt8) -> String {
        switch usage {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(0x41) + usage - 0x04))
        case 0x1E...0x26: return String(usage - 0x1D)
        case 0x27: return "0"
        case 0x28: return "↩"
        case 0x29: return "⎋"
        case 0x2A: return "⌫"
        case 0x2B: return "⇥"
        case 0x2C: return String(localized: "空格", bundle: L10n.bundle)
        case 0x2D: return "-"
        case 0x2E: return "="
        case 0x2F: return "["
        case 0x30: return "]"
        case 0x31: return "\\"
        case 0x33: return ";"
        case 0x34: return "'"
        case 0x35: return "`"
        case 0x36: return ","
        case 0x37: return "."
        case 0x38: return "/"
        case 0x39: return "⇪"
        case 0x3A...0x45: return "F\(usage - 0x39)"
        case 0x46: return "F13"
        case 0x49: return "Insert"
        case 0x4A: return "↖"
        case 0x4B: return "⇞"
        case 0x4C: return "⌦"
        case 0x4D: return "↘"
        case 0x4E: return "⇟"
        case 0x4F: return "→"
        case 0x50: return "←"
        case 0x51: return "↓"
        case 0x52: return "↑"
        case 0x53: return "⌧"
        case 0x54: return String(localized: "数字键 /", bundle: L10n.bundle)
        case 0x55: return String(localized: "数字键 *", bundle: L10n.bundle)
        case 0x56: return String(localized: "数字键 -", bundle: L10n.bundle)
        case 0x57: return String(localized: "数字键 +", bundle: L10n.bundle)
        case 0x58: return String(localized: "数字键 ↩", bundle: L10n.bundle)
        case 0x59...0x61: return String(localized: "数字键 \(usage - 0x58)", bundle: L10n.bundle)
        case 0x62: return String(localized: "数字键 0", bundle: L10n.bundle)
        case 0x63: return String(localized: "数字键 .", bundle: L10n.bundle)
        case 0x64: return "§"
        case 0x67: return String(localized: "数字键 =", bundle: L10n.bundle)
        case 0x68...0x73: return "F\(usage - 0x68 + 13)"
        default: return String(format: String(localized: "键 0x%02X", bundle: L10n.bundle), usage)
        }
    }

    /// macOS 虚拟键码（`NSEvent.keyCode`）→ HID 键码。
    public static func fromMacKeyCode(_ code: UInt16) -> UInt8? { macToHID[code] }

    private static let macToHID: [UInt16: UInt8] = [
        0x00: 0x04, 0x01: 0x16, 0x02: 0x07, 0x03: 0x09, 0x04: 0x0B, 0x05: 0x0A, 0x06: 0x1D, 0x07: 0x1B,
        0x08: 0x06, 0x09: 0x19, 0x0A: 0x64, 0x0B: 0x05, 0x0C: 0x14, 0x0D: 0x1A, 0x0E: 0x08, 0x0F: 0x15,
        0x10: 0x1C, 0x11: 0x17, 0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x16: 0x23, 0x17: 0x22,
        0x18: 0x2E, 0x19: 0x26, 0x1A: 0x24, 0x1B: 0x2D, 0x1C: 0x25, 0x1D: 0x27, 0x1E: 0x30, 0x1F: 0x12,
        0x20: 0x18, 0x21: 0x2F, 0x22: 0x0C, 0x23: 0x13, 0x24: 0x28, 0x25: 0x0F, 0x26: 0x0D, 0x27: 0x34,
        0x28: 0x0E, 0x29: 0x33, 0x2A: 0x31, 0x2B: 0x36, 0x2C: 0x38, 0x2D: 0x11, 0x2E: 0x10, 0x2F: 0x37,
        0x30: 0x2B, 0x31: 0x2C, 0x32: 0x35, 0x33: 0x2A, 0x35: 0x29,
        0x40: 0x6C, 0x41: 0x63, 0x43: 0x55, 0x45: 0x57, 0x47: 0x53, 0x4B: 0x54, 0x4C: 0x58, 0x4E: 0x56,
        0x4F: 0x6D, 0x50: 0x6E, 0x51: 0x67, 0x52: 0x62, 0x53: 0x59, 0x54: 0x5A, 0x55: 0x5B, 0x56: 0x5C,
        0x57: 0x5D, 0x58: 0x5E, 0x59: 0x5F, 0x5A: 0x6F, 0x5B: 0x60, 0x5C: 0x61,
        0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x63: 0x3C, 0x64: 0x41, 0x65: 0x42, 0x67: 0x44, 0x69: 0x68,
        0x6A: 0x6B, 0x6B: 0x69, 0x6D: 0x43, 0x6F: 0x45, 0x71: 0x6A, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B,
        0x75: 0x4C, 0x76: 0x3D, 0x77: 0x4D, 0x78: 0x3B, 0x79: 0x4E, 0x7A: 0x3A, 0x7B: 0x50, 0x7C: 0x4F,
        0x7D: 0x51, 0x7E: 0x52,
    ]

    /// 把一段 ASCII 文本转成依次输出的按键（按美式键盘布局）。不支持的字符返回 nil。
    public static func strokes(forText text: String) -> [KeyStroke]? {
        var result: [KeyStroke] = []
        for ch in text {
            guard let s = asciiStroke(ch) else { return nil }
            result.append(s)
        }
        return result
    }

    /// 反过来：如果一串按键都能还原成可打印字符，返回对应文本。
    public static func text(forStrokes strokes: [KeyStroke]) -> String? {
        var out = ""
        for s in strokes {
            guard let ch = asciiTable.first(where: { $0.value == s })?.key else { return nil }
            out.append(ch)
        }
        return out
    }

    private static func asciiStroke(_ ch: Character) -> KeyStroke? { asciiTable[ch] }

    private static let asciiTable: [Character: KeyStroke] = {
        var t: [Character: KeyStroke] = [:]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            t[c] = KeyStroke(usage: UInt8(0x04 + i))
            t[Character(c.uppercased())] = KeyStroke(modifiers: .shift, usage: UInt8(0x04 + i))
        }
        for (i, c) in "1234567890".enumerated() { t[c] = KeyStroke(usage: UInt8(0x1E + i)) }
        for (i, c) in "!@#$%^&*()".enumerated() { t[c] = KeyStroke(modifiers: .shift, usage: UInt8(0x1E + i)) }
        let plain: [(Character, UInt8)] = [(" ", 0x2C), ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30),
                                          ("\\", 0x31), (";", 0x33), ("'", 0x34), ("`", 0x35), (",", 0x36),
                                          (".", 0x37), ("/", 0x38), ("\n", 0x28), ("\t", 0x2B)]
        let shifted: [(Character, UInt8)] = [("_", 0x2D), ("+", 0x2E), ("{", 0x2F), ("}", 0x30), ("|", 0x31),
                                            (":", 0x33), ("\"", 0x34), ("~", 0x35), ("<", 0x36), (">", 0x37),
                                            ("?", 0x38)]
        for (c, u) in plain { t[c] = KeyStroke(usage: u) }
        for (c, u) in shifted { t[c] = KeyStroke(modifiers: .shift, usage: u) }
        return t
    }()
}

// MARK: - 显示文字

extension Modifiers {
    /// 按 macOS 习惯的顺序：⌃⌥⇧⌘。
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

extension KeyStroke {
    public var displayName: String { modifiers.symbols + KeyUsage.name(usage) }
}

extension MouseAction {
    public var displayName: String {
        var base: String
        switch (buttons, wheel) {
        case (0x01, _): base = String(localized: "鼠标左键", bundle: L10n.bundle)
        case (0x02, _): base = String(localized: "鼠标右键", bundle: L10n.bundle)
        case (0x04, _): base = String(localized: "鼠标中键", bundle: L10n.bundle)
        case (_, let w) where w > 0: base = String(localized: "滚轮向上", bundle: L10n.bundle)
        case (_, let w) where w < 0: base = String(localized: "滚轮向下", bundle: L10n.bundle)
        default: base = String(localized: "鼠标", bundle: L10n.bundle)
        }
        return modifiers.symbols + base
    }
}

extension KnobAction {
    public var displayName: String {
        switch self {
        case .keys(let strokes):
            if strokes.count > 1, let text = KeyUsage.text(forStrokes: strokes) { return "“\(text)”" }
            return strokes.map(\.displayName).joined(separator: " ")
        case .media(let usage): return ConsumerUsage.name(usage)
        case .mouse(let m): return m.displayName
        case .unknown(let type, _): return String(localized: "未识别（类型 \(type)）", bundle: L10n.bundle)
        }
    }
}

extension KnobGesture {
    public var title: String {
        switch self {
        case .turnLeft: String(localized: "左转", bundle: L10n.bundle)
        case .press: String(localized: "按下", bundle: L10n.bundle)
        case .turnRight: String(localized: "右转", bundle: L10n.bundle)
        case .holdTurnLeft: String(localized: "按住左转", bundle: L10n.bundle)
        case .holdTurnRight: String(localized: "按住右转", bundle: L10n.bundle)
        }
    }

    public var caption: String {
        switch self {
        case .turnLeft: String(localized: "逆时针旋转一格时触发", bundle: L10n.bundle)
        case .press: String(localized: "短按旋钮时触发", bundle: L10n.bundle)
        case .turnRight: String(localized: "顺时针旋转一格时触发", bundle: L10n.bundle)
        case .holdTurnLeft: String(localized: "按住旋钮的同时逆时针转", bundle: L10n.bundle)
        case .holdTurnRight: String(localized: "按住旋钮的同时顺时针转", bundle: L10n.bundle)
        }
    }
}

extension LedMode {
    public var name: String {
        switch self {
        case .off: String(localized: "关闭", bundle: L10n.bundle)
        case .white: String(localized: "白光", bundle: L10n.bundle)
        case .green: String(localized: "绿光", bundle: L10n.bundle)
        case .marquee: String(localized: "跑马灯", bundle: L10n.bundle)
        case .rgbCycle: String(localized: "红绿蓝轮换", bundle: L10n.bundle)
        case .fastMarquee: String(localized: "快速跑马灯", bundle: L10n.bundle)
        }
    }
}

extension Lighting {
    public var displayName: String { mode.name }
}
