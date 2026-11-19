import AppKit
import KnobKit
import SwiftUI

/// 快捷键录制框：点一下开始录制，直接按下组合键；Esc 取消。
struct ShortcutRecorder: View {
    @Binding var stroke: KeyStroke?
    @State private var recording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(stroke == nil && !recording ? .secondary : .primary)
                .tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if stroke != nil, !recording {
                Button {
                    stroke = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除快捷键")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: 200, height: 26)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 2)
        }
        .background(KeyCaptureView(recording: $recording) { captured in
            stroke = captured
        })
        .contentShape(Rectangle())
        .onTapGesture { recording = true }
        .onChange(of: recording) { _, on in SystemHotKeys.setPaused(on) }
        .onDisappear { if recording { SystemHotKeys.setPaused(false) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recording ? String(localized: "正在录制快捷键", bundle: L10n.bundle) : String(localized: "快捷键：\(label)", bundle: L10n.bundle))
        .help("点按后按下想用的组合键，按 Esc 取消")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { recording = true }
    }

    private var label: String {
        if recording { return stroke.map(\.displayName) ?? String(localized: "按下快捷键…", bundle: L10n.bundle) }
        return stroke?.displayName ?? String(localized: "点按以录制", bundle: L10n.bundle)
    }
}

/// 透明的 NSView，录制时成为第一响应者并接收按键。
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var recording: Bool
    var onCapture: (KeyStroke) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onCapture = { stroke in
            onCapture(stroke)
            recording = false
        }
        view.onCancel = { recording = false }
        return view
    }

    func updateNSView(_ view: CaptureNSView, context: Context) {
        view.onCapture = { stroke in
            onCapture(stroke)
            recording = false
        }
        view.onCancel = { recording = false }
        if recording, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        } else if !recording, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    final class CaptureNSView: NSView {
        var onCapture: ((KeyStroke) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func resignFirstResponder() -> Bool {
            onCancel?()
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 0x35, flags.isEmpty {  // Esc
                onCancel?()
                return
            }
            guard let usage = KeyUsage.fromMacKeyCode(event.keyCode) else {
                NSSound.beep()
                return
            }
            var mods: Modifiers = []
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.command) { mods.insert(.command) }
            onCapture?(KeyStroke(modifiers: mods, usage: usage))
        }

        // 让 ⌘ 组合键也进到 keyDown，而不是被菜单拿走。
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event)
            return true
        }
    }
}

/// 常见的 macOS 系统快捷键。旋钮触发它们时会直接执行系统功能。
enum SystemShortcut {
    static func name(for stroke: KeyStroke) -> String? {
        table[stroke].map { L10n.bundle.localizedString(forKey: $0, value: nil, table: nil) }
    }

    private static let table: [KeyStroke: String] = [
        KeyStroke(modifiers: [.command, .shift], usage: 0x20): "截取整个屏幕",
        KeyStroke(modifiers: [.command, .shift], usage: 0x21): "截取所选区域",
        KeyStroke(modifiers: [.command, .shift], usage: 0x22): "截屏工具",
        KeyStroke(modifiers: .command, usage: 0x2C): "聚焦搜索",
        KeyStroke(modifiers: .command, usage: 0x2B): "切换 App",
        KeyStroke(modifiers: .command, usage: 0x14): "退出当前 App",
        KeyStroke(modifiers: .command, usage: 0x1A): "关闭窗口",
        KeyStroke(modifiers: .control, usage: 0x52): "调度中心",
        KeyStroke(modifiers: .control, usage: 0x51): "App 窗口",
        KeyStroke(modifiers: .control, usage: 0x50): "向左切换桌面",
        KeyStroke(modifiers: .control, usage: 0x4F): "向右切换桌面",
        KeyStroke(modifiers: [.control, .command], usage: 0x14): "锁定屏幕",
    ]
}

/// 录制期间暂停系统快捷键。
///
/// `⌃←`、`⌘⇧4` 这类系统快捷键在按键事件送到 App 之前就被系统处理掉了，录制框收不到。
/// 和常见的快捷键录制工具一样，录制时调用 SkyLight 的 `SLSSetGlobalHotKeyOperatingMode`
/// 暂停系统快捷键，录完立即恢复。这个设置只对本 App 的窗口服务器连接有效，App 退出或崩溃时系统会自动恢复。
/// 找不到这些函数时什么也不做（退回到原来的行为）。
enum SystemHotKeys {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetMode = @convention(c) (Int32, Int32) -> Int32
    private typealias GetMode = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let mainConnection = symbol("SLSMainConnectionID", as: MainConnection.self)
    private static let setMode = symbol("SLSSetGlobalHotKeyOperatingMode", as: SetMode.self)
    private static let getMode = symbol("SLSGetGlobalHotKeyOperatingMode", as: GetMode.self)

    /// 0 = 启用，1 = 全部暂停。
    @discardableResult
    static func setPaused(_ paused: Bool) -> Bool {
        guard let mainConnection, let setMode else { return false }
        return setMode(mainConnection(), paused ? 1 : 0) == 0
    }

    static var isPaused: Bool? {
        guard let mainConnection, let getMode else { return nil }
        var mode: Int32 = -1
        guard getMode(mainConnection(), &mode) == 0 else { return nil }
        return mode != 0
    }
}
