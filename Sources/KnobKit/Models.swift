import Foundation

/// 旋钮上的 5 个动作，原始值是固件里的键位编号。
///
/// 编号来自原厂 App 的「0 键 + 1 旋钮」布局（`Set_Keyboard_0add1`）：
/// 按钮 K16/K17/K18/K19/K21 分别放在左转、按下、右转、按住左转、按住右转的图片上，K20 不使用。
public enum KnobGesture: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case turnLeft = 16
    case press = 17
    case turnRight = 18
    case holdTurnLeft = 19
    case holdTurnRight = 21

    public var id: UInt8 { rawValue }
}

/// 一次按键：修饰键位图 + HID 键码（Keyboard/Keypad 用途页 0x07）。
public struct KeyStroke: Codable, Equatable, Hashable, Sendable {
    public var modifiers: Modifiers
    public var usage: UInt8

    public init(modifiers: Modifiers = [], usage: UInt8) {
        self.modifiers = modifiers
        self.usage = usage
    }
}

/// HID 修饰键位图（只用左侧修饰键）。
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 0x01)
    public static let shift = Modifiers(rawValue: 0x02)
    public static let option = Modifiers(rawValue: 0x04)
    public static let command = Modifiers(rawValue: 0x08)
}

/// 鼠标动作。字段顺序与固件记录一致：修饰键、按键、X、Y、滚轮。
public struct MouseAction: Codable, Equatable, Hashable, Sendable {
    public var modifiers: Modifiers
    public var buttons: UInt8
    public var wheel: Int8

    public init(modifiers: Modifiers = [], buttons: UInt8 = 0, wheel: Int8 = 0) {
        self.modifiers = modifiers
        self.buttons = buttons
        self.wheel = wheel
    }

    public static let leftClick = MouseAction(buttons: 0x01)
    public static let rightClick = MouseAction(buttons: 0x02)
    public static let middleClick = MouseAction(buttons: 0x04)
    public static let wheelUp = MouseAction(wheel: 1)
    public static let wheelDown = MouseAction(wheel: -1)
}

/// 一个动作触发后做什么。
public enum KnobAction: Codable, Equatable, Hashable, Sendable {
    /// 按键或组合键；多于一个时依次输出（文本），固件上限 18 个。
    case keys([KeyStroke])
    /// 多媒体键（Consumer 用途页 0x0C 的用途码）。
    case media(UInt16)
    case mouse(MouseAction)
    /// 固件里存的类型本 App 还不认识，原样保留以便显示。
    case unknown(type: UInt8, raw: [UInt8])

    public static let maxKeys = 18
}

/// 灯效模式，原始值是灯效字节的低 4 位。
///
/// 名称按实物观察（2026-11-19）确定，与说明书不同。这台旋钮（固件版本 0）不支持选颜色：
/// 灯效字节的高 4 位（原厂 App 当作颜色）写什么都没有效果。值 6 效果与 5 相近，原厂不提供，这里也不开放。
public enum LedMode: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case off = 0
    case white = 1
    case green = 2
    case marquee = 3
    case rgbCycle = 4
    case fastMarquee = 5

    public var id: UInt8 { rawValue }
}

public struct Lighting: Codable, Equatable, Hashable, Sendable {
    public var mode: LedMode

    /// 出厂时是快速跑马灯。
    public init(mode: LedMode = .fastMarquee) {
        self.mode = mode
    }
}

/// 旋钮的完整配置。
public struct KnobConfig: Codable, Equatable, Sendable {
    public var actions: [KnobGesture: KnobAction]
    public var lighting: Lighting

    public init(actions: [KnobGesture: KnobAction], lighting: Lighting = Lighting()) {
        self.actions = actions
        self.lighting = lighting
    }

    /// 说明书写的出厂默认值。
    public static let factoryDefault = KnobConfig(actions: [
        .turnLeft: .media(ConsumerUsage.volumeDown),
        .turnRight: .media(ConsumerUsage.volumeUp),
        .press: .media(ConsumerUsage.mute),
        .holdTurnLeft: .media(ConsumerUsage.brightnessDown),
        .holdTurnRight: .media(ConsumerUsage.brightnessUp),
    ])
}

/// 设备自报的形态信息（`03 FB FB FB` 的回复）。
public struct DeviceInfo: Equatable, Sendable {
    public var keyCount: UInt8
    public var knobCount: UInt8
    public var version: UInt8
}
