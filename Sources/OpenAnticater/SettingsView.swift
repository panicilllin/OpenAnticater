import AppKit
import KnobKit
import SwiftUI
import UserNotifications

/// 外观：跟随系统 / 浅色 / 深色。
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// App 语言：跟随系统，或固定为简体中文 / English。切换后立即生效，不需要重启。
enum LanguageSetting: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "跟随系统", bundle: L10n.bundle)
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    /// 切换本地化来源，返回界面要用的 Locale。
    func activate() -> Locale {
        L10n.use(language: self == .system ? nil : rawValue)
    }
}

/// 设置页：放在主窗口里，从侧栏或 ⌘, 进入。
///
/// 说明文字只留真正需要的：每个开关的含义写在悬停提示里，较长的解释放进 ⓘ 弹出框。
struct SettingsView: View {
    @Environment(DeviceStore.self) private var store
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = false
    @AppStorage(SettingsKey.lowBatteryAlert) private var lowBatteryAlert = true
    @AppStorage(SettingsKey.lowBatteryThreshold) private var threshold = 20
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false
    @AppStorage(SettingsKey.language) private var language = LanguageSetting.system

    var body: some View {
        Form {
            Section("通用") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: appearance) { _, new in new.apply() }

                Picker("语言", selection: $language) {
                    ForEach(LanguageSetting.allCases) { Text($0.title).tag($0) }
                }

                Toggle("登录时打开", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try LoginItem.set(on) } catch {
                            launchAtLogin = LoginItem.isEnabled
                            store.errorMessage = String(localized: "无法修改登录项：\(error.localizedDescription)", bundle: L10n.bundle)
                        }
                    }
                Toggle("在菜单栏中显示", isOn: $showInMenuBar)
                    .help("在菜单栏显示电量和当前配置")
            }

            Section {
                Toggle(isOn: $lowBatteryAlert) {
                    HStack(spacing: 4) {
                        Text("电量低时发送通知")
                        InfoButton("电量由旋钮通过蓝牙上报。使用 2.4G 接收器时读不到电量，也不会提醒。")
                    }
                }
                .onChange(of: lowBatteryAlert) { _, on in
                    if on { requestNotificationPermission() }
                }
                Picker("提醒阈值", selection: $threshold) {
                    ForEach([10, 20, 30], id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                }
                .disabled(!lowBatteryAlert)
            } header: {
                Text("电量提醒")
            }

            Section("设备") {
                LabeledContent("设备 ID") { Text(verbatim: "514C:8850") }
                LabeledContent("把 5 个动作和灯效恢复为出厂设置") {
                    Button("恢复出厂设置…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "设置", bundle: L10n.bundle))
        .confirmationDialog(String(localized: "恢复出厂设置？", bundle: L10n.bundle), isPresented: $confirmReset) {
            Button("恢复", role: .destructive) { store.restoreFactoryDefaults() }
        } message: {
            Text("5 个动作会改回说明书里的默认值（音量、静音、亮度），灯效改回快速跑马灯。之后还要点「应用」才会写入旋钮。")
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// 小的 ⓘ 按钮，点开显示一段说明。用来替代常驻的大段脚注。
struct InfoButton: View {
    let text: LocalizedStringKey
    @State private var shown = false

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("说明")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(16)
        }
    }
}
