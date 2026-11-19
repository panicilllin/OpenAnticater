#if DEBUG
import AppKit
import SwiftUI
import KnobKit

/// 调试用：设置环境变量后，App 启动几秒会把自己的窗口画成 PNG，不需要屏幕录制权限。
///
///     OPENANTICATER_SNAPSHOT_DIR=/tmp/shots    输出目录
///     OPENANTICATER_SELECT=lighting|turnLeft…  初始选中项
///     OPENANTICATER_DARK=1                     深色外观
enum DebugSnapshot {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var initialSelection: String? { environment["OPENANTICATER_SELECT"] }

    /// 侧边栏是系统合成的玻璃层，窗口截图里是空白；单独放进一个离屏窗口再画一次。
    @MainActor
    static func renderSidebar(store: DeviceStore, to url: URL) {
        let host = NSHostingView(rootView: SidebarView(selection: .constant(.gesture(.press)))
            .environment(store)
            .environment(\.locale, (UserDefaults.standard.string(forKey: SettingsKey.language)
                .flatMap(LanguageSetting.init(rawValue:)) ?? .system).activate())
            .frame(width: 280, height: 560)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 280, height: 560),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            window.orderOut(nil)
        }
    }

    /// 生成 App 图标用的 1024px PNG：浅灰圆角方块上放旋钮。
    @MainActor
    static func renderIcon(to url: URL) {
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.86)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 10)
            KnobView(size: 640, ring: .solid(.white), animated: false)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    @MainActor
    static func scheduleIfRequested(store: DeviceStore) {
        if let path = environment["OPENANTICATER_RENDER_ICON"] {
            renderIcon(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }
        if let dir = environment["OPENANTICATER_SNAPSHOT_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let name = environment["OPENANTICATER_SNAPSHOT_NAME"] ?? "window"
                renderSidebar(store: store, to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-sidebar.png"))
            }
        }
        if let lang = environment["OPENANTICATER_SWITCH_LANG"] {
            // 运行中切换语言，用来验证不重启也能生效。
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                UserDefaults.standard.set(lang, forKey: SettingsKey.language)
            }
        }
        if environment["OPENANTICATER_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard let dir = environment["OPENANTICATER_SNAPSHOT_DIR"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for (i, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 300 {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = environment["OPENANTICATER_SNAPSHOT_NAME"] ?? "window"
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(i).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            if environment["OPENANTICATER_SNAPSHOT_QUIT"] == "1" { NSApp.terminate(nil) }
        }
    }
}
#endif
