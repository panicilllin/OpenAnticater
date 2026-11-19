import KnobKit
import SwiftUI

/// 旋钮插图：灰白磨砂、边缘圆润，靠阴影和体积与背景区分；底部一圈灯带。
///
/// 光从正上方来：上半部分略亮、下半部分略暗；投影分接触阴影和环境阴影两层。
/// 转动演示只转一个浅凹点，磨砂表面的明暗不跟着转。
struct KnobView: View {
    enum Demo { case none, press, turnLeft, turnRight, holdTurnLeft, holdTurnRight }

    /// 灯带的样子。
    enum Ring: Equatable {
        case off
        case solid(Color)
        case rainbow(fast: Bool)
        case rgbCycle

        var isAnimated: Bool {
            switch self {
            case .rainbow, .rgbCycle: true
            default: false
            }
        }
    }

    var size: CGFloat
    var ring: Ring = .solid(.white)
    var demo: Demo = .none
    /// 侧边栏等小图标不需要动画。
    var animated = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated, !reduceMotion, demo != .none || ring.isAnimated {
            TimelineView(.animation) { context in
                content(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(time: 0)
        }
    }

    private func content(time: Double) -> some View {
        let (pressed, angle) = (demo == .none || reduceMotion || !animated) ? (0, .zero) : Self.pose(for: demo, time: time)
        return knob(pressed: pressed, angle: angle, time: time)
    }

    private static let rainbow: [Color] = [
        Color(red: 1.0, green: 0.27, blue: 0.23), Color(red: 1.0, green: 0.62, blue: 0.04),
        Color(red: 1.0, green: 0.84, blue: 0.04), Color(red: 0.19, green: 0.82, blue: 0.35),
        Color(red: 0.39, green: 0.82, blue: 1.0), Color(red: 0.04, green: 0.52, blue: 1.0),
        Color(red: 0.75, green: 0.35, blue: 0.95), Color(red: 1.0, green: 0.27, blue: 0.23),
    ]

    private static let rgb: [Color] = [
        Color(red: 1.0, green: 0.23, blue: 0.19), Color(red: 0.2, green: 0.8, blue: 0.35), Color(red: 0.1, green: 0.45, blue: 1.0),
    ]

    @ViewBuilder
    private func ringFill(time: Double) -> some View {
        switch ring {
        case .off:
            Circle().fill(colorScheme == .dark ? Color(white: 0.23) : Color(white: 0.85))
        case .solid(let color):
            Circle().fill(color)
        case .rainbow(let fast):
            Circle().fill(AngularGradient(colors: Self.rainbow, center: .center))
                .rotationEffect(.degrees(time * (fast ? 240 : 90)))
        case .rgbCycle:
            Circle().fill(Self.rgb[Int(time / 1.2) % 3])
        }
    }

    private func knob(pressed: Double, angle: Angle, time: Double) -> some View {
        let dark = colorScheme == .dark
        let isWhite = ring == .solid(.white)
        let glow: Double = switch ring {
        case .off: 0
        case .solid: isWhite ? (dark ? 0.55 : 0) : 0.5
        default: 0.5
        }
        return ZStack {
            // 灯带：一层模糊的光晕 + 一圈实体
            if ring != .off {
                ringFill(time: time)
                    .blur(radius: size * 0.05)
                    .opacity(glow + pressed * 0.3)
                    .padding(size * 0.03)
            }
            ringFill(time: time)
                .overlay(Circle().strokeBorder(isWhite && !dark ? Color.black.opacity(0.10) : .clear,
                                               lineWidth: max(0.5, size * 0.004)))
                // 浅色背景上白光看不出来，加一圈很淡的外影让灯带能被看见。
                .shadow(color: .black.opacity(isWhite && !dark ? 0.12 : 0), radius: size * 0.015)
                .padding(size * 0.055)

            // 旋钮本体
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.98, green: 0.98, blue: 0.973),
                                              Color(red: 0.933, green: 0.933, blue: 0.922),
                                              Color(red: 0.867, green: 0.867, blue: 0.851)],
                                     center: UnitPoint(x: 0.5, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.42))
                .overlay {
                    // 圆润的边：上沿柔和高光、下沿柔和暗部
                    Circle()
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0), .black.opacity(0.10)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: size * 0.045)
                        .blur(radius: size * 0.025)
                        .clipShape(Circle())
                }
                .overlay {
                    // 浅凹点：指示转动
                    Circle()
                        .fill(Color(red: 0.886, green: 0.886, blue: 0.871))
                        .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: max(0.5, size * 0.006))
                                    .blur(radius: size * 0.006).offset(y: size * 0.004).clipShape(Circle()))
                        .frame(width: size * 0.06, height: size * 0.06)
                        .offset(y: -size * 0.30)
                        .rotationEffect(angle)
                }
                .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: size * 0.012, y: size * 0.012)
                .shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: size * 0.09, y: size * 0.09)
                .padding(size * 0.08)
                .scaleEffect(1 - pressed * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 演示动画的姿态：按下程度 0–1，指示点角度。
    private static func pose(for demo: Demo, time: TimeInterval) -> (Double, Angle) {
        let period = 2.6
        let p = time.truncatingRemainder(dividingBy: period) / period  // 0..1
        func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
        func bump(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            if p < a || p > d { return 0 }
            if p < b { return ease((p - a) / (b - a)) }
            if p <= c { return 1 }
            return 1 - ease((p - c) / (d - c))
        }
        switch demo {
        case .none: return (0, .zero)
        case .press: return (bump(0.5, 0.58, 0.72, 0.8), .zero)
        case .turnLeft: return (0, .degrees(-50 * bump(0.15, 0.5, 0.65, 0.95)))
        case .turnRight: return (0, .degrees(50 * bump(0.15, 0.5, 0.65, 0.95)))
        case .holdTurnLeft: return (bump(0.05, 0.12, 0.85, 0.92), .degrees(-50 * bump(0.18, 0.5, 0.65, 0.85)))
        case .holdTurnRight: return (bump(0.05, 0.12, 0.85, 0.92), .degrees(50 * bump(0.18, 0.5, 0.65, 0.85)))
        }
    }
}

extension KnobView.Demo {
    init(_ gesture: KnobGesture) {
        switch gesture {
        case .turnLeft: self = .turnLeft
        case .press: self = .press
        case .turnRight: self = .turnRight
        case .holdTurnLeft: self = .holdTurnLeft
        case .holdTurnRight: self = .holdTurnRight
        }
    }
}

extension Lighting {
    /// 插图里灯带的样子，按实物观察到的效果画。
    var ring: KnobView.Ring {
        switch mode {
        case .off: .off
        case .white: .solid(.white)
        case .green: .solid(Color(red: 0.19, green: 0.82, blue: 0.35))
        case .marquee: .rainbow(fast: false)
        case .rgbCycle: .rgbCycle
        case .fastMarquee: .rainbow(fast: true)
        }
    }
}

extension DeviceStore {
    /// 插图里灯带的样子；灯效未知时画成白色。
    var lightingRing: KnobView.Ring { shownLighting?.ring ?? .solid(.white) }
}
