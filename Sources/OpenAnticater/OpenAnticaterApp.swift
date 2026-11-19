import AppKit
import KnobKit
import SwiftUI

@main
struct OpenAnticaterApp: App {
    @State private var store = DeviceStore()
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = false
    /// 语言写在这里：改动后整个界面带着新的 locale 重新渲染，代码拼的文字也换成新语言的包。
    @AppStorage(SettingsKey.language) private var language = LanguageSetting.system

    init() {
        // 早期版本把语言写进 AppleLanguages（需要重启），现在改为 App 内切换，清掉旧值。
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    var body: some Scene {
        Window("ANTICATER MINI", id: "main") {
            ContentView()
                .environment(store)
                .environment(\.locale, language.activate())
                // 代码里拼的文字不会随 locale 自动刷新，换语言时整棵视图重建一次。
                .id(language)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    let saved = UserDefaults.standard.string(forKey: SettingsKey.appearance)
                    (saved.flatMap(AppearanceSetting.init(rawValue:)) ?? .system).apply()
                    #if DEBUG
                    DebugSnapshot.scheduleIfRequested(store: store)
                    #endif
                }
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // 设置在主窗口里，⌘, 跳到侧栏的「设置」。
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton(store: store)
            }
        }

        MenuBarExtra("ANTICATER MINI", systemImage: "dial.medium", isInserted: $showInMenuBar) {
            MenuBarContent()
                .environment(store)
                .environment(\.locale, language.activate())
                // 代码里拼的文字不会随 locale 自动刷新，换语言时整棵视图重建一次。
                .id(language)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct OpenSettingsButton: View {
    let store: DeviceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(String(localized: "设置…", bundle: L10n.bundle)) {
            store.selection = .settings
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
    }
}

// MARK: - 菜单栏菜单（标准菜单，按 HIG 不用自定义面板）

private struct MenuBarContent: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.lowBatteryAlert) private var lowBatteryAlert = true

    var body: some View {
        Text(verbatim: "ANTICATER MINI")
        Text(store.connectionSummary)

        Divider()

        Menu(String(localized: "当前配置", bundle: L10n.bundle)) {
            ForEach(KnobGesture.allCases) { g in
                Text(verbatim: "\(g.title)　\(store.deviceActions?[g]?.displayName ?? "—")")
            }
            Text(verbatim: "\(String(localized: "灯效", bundle: L10n.bundle))　\(store.writtenLighting?.displayName ?? String(localized: "未知", bundle: L10n.bundle))")
            Divider()
            Text(String(localized: "要修改，请打开 App 并插上 USB 线。", bundle: L10n.bundle))
        }
        Toggle(String(localized: "电量低时提醒", bundle: L10n.bundle), isOn: $lowBatteryAlert)

        Divider()

        Button(String(localized: "打开 ANTICATER MINI", bundle: L10n.bundle)) {
            openWindow(id: "main")
            NSApp.activate()
        }
        OpenSettingsButton(store: store)

        Divider()

        Button(String(localized: "退出", bundle: L10n.bundle)) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
