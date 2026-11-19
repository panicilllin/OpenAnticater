import AppKit
import KnobKit
import SwiftUI

enum SidebarItem: Hashable {
    case gesture(KnobGesture)
    case lighting
    case settings
}

struct ContentView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(selection: $store.selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            Group {
                if store.selection == .settings {
                    SettingsView()
                } else if !store.usbConnected {
                    DisconnectedView()
                } else if store.deviceActions == nil {
                    ProgressView("正在读取旋钮配置…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch store.selection {
                    case .gesture(let g): ActionDetailView(gesture: g)
                    case .lighting: LightingDetailView()
                    case .settings, nil: Color.clear
                    }
                }
            }
            .toolbar { DeviceToolbar() }
            // 不画工具栏背景，标题栏和内容区连成一片；窗口失去焦点时也不会出现分隔线。
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .background(WindowConfigurator())
        .confirmationDialog(String(localized: "放弃 \(store.modifiedCount) 项未应用的修改并重新读取？", bundle: L10n.bundle),
                            isPresented: $store.confirmingReload) {
            Button(String(localized: "放弃并读取", bundle: L10n.bundle), role: .destructive) {
                Task { await store.read(discardingEdits: true) }
            }
        } message: {
            Text("旋钮当前的设置会替换 App 里还没应用的修改。")
        }
        .alert(String(localized: "出错了", bundle: L10n.bundle), isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button(String(localized: "好", bundle: L10n.bundle)) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        #if DEBUG
        .onAppear {
            switch DebugSnapshot.initialSelection {
            case "lighting": store.selection = .lighting
            case "settings": store.selection = .settings
            case "turnLeft": store.selection = .gesture(.turnLeft)
            case "holdTurnRight": store.selection = .gesture(.holdTurnRight)
            default: break
            }
        }
        #endif
    }
}

/// 窗口失去焦点时，系统会在标题栏下画一条分隔线，和内容区之间显得像断开了；这里把它关掉。
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarSeparatorStyle = .none
        }
    }
}

// MARK: - 工具栏

/// 读取是次要操作：一个刷新图标，配悬停提示和 ⌘R。
/// 应用是本页唯一的主要操作：强调色胶囊按钮，用一个动词「应用」，和系统里提交设置的习惯一致。
/// 两者分成两组，中间留出间距，最右侧再留一点边距。
private struct DeviceToolbar: ToolbarContent {
    @Environment(DeviceStore.self) private var store

    var body: some ToolbarContent {
        if store.usbConnected && store.selection != .settings {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.requestReload()
                } label: {
                    if store.activity == .reading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("从旋钮重新读取", systemImage: "arrow.clockwise")
                    }
                }
                .help("读取旋钮当前的设置，放弃未应用的修改（⌘R）")
                .keyboardShortcut("r")
                .disabled(store.isBusy)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.write() }
                } label: {
                    applyLabel
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isBusy || store.writeBlocker != nil || store.modifiedCount == 0)
                .help(applyHelp)
                .keyboardShortcut("s")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }

    @ViewBuilder private var applyLabel: some View {
        switch store.activity {
        case .writing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在应用")
            }
        default:
            if store.justApplied {
                Label("已应用", systemImage: "checkmark")
            } else {
                Text("应用")
            }
        }
    }

    private var applyHelp: String {
        if let blocker = store.writeBlocker { return blocker }
        if store.modifiedCount == 0 { return String(localized: "没有需要应用的修改", bundle: L10n.bundle) }
        return String(localized: "把 \(store.modifiedCount) 项修改写入旋钮（⌘S）", bundle: L10n.bundle)
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @Environment(DeviceStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            DeviceHeader()
                .listRowSeparator(.hidden)
                .selectionDisabled()

            Section(store.usbConnected ? LocalizedStringKey("旋钮动作") : LocalizedStringKey("旋钮动作 · 上次读取")) {
                ForEach(KnobGesture.allCases) { g in
                    GestureRow(gesture: g)
                        .tag(SidebarItem.gesture(g))
                }
            }
            Section("灯光") {
                LightingRow()
                    .tag(SidebarItem.lighting)
            }
            Section {
                SidebarRow(title: String(localized: "设置", bundle: L10n.bundle), detail: "", tile: .gray,
                           symbol: "gearshape.fill", modified: false)
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DeviceHeader: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            KnobView(size: 32, ring: isOn ? store.lightingRing : .off, animated: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "ANTICATER MINI").font(.headline)
                Text(statusText).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var isOn: Bool { store.usbConnected || store.bluetoothConnected }

    private var statusText: String { store.connectionSummary }
}

extension DeviceStore {
    /// 「USB 已连接 · 电量 100%」这样的一行状态。
    var connectionSummary: String {
        let connection = usbConnected ? String(localized: "USB 已连接", bundle: L10n.bundle)
            : bluetoothConnected ? String(localized: "蓝牙已连接", bundle: L10n.bundle)
            : receiverConnected ? String(localized: "接收器已插入", bundle: L10n.bundle)
            : String(localized: "未连接", bundle: L10n.bundle)
        guard let level = batteryLevel else { return connection }
        return connection + " · " + String(localized: "电量 \(level)%", bundle: L10n.bundle)
    }
}

/// 侧栏行自己读取 store，而不是由列表把算好的值传进来：
/// macOS 的 SwiftUI 侧栏在只有传入值变化时，可能只重绘选中的那一行，
/// 导致其他行的「已修改」蓝点在应用后不消失。让每行自己观察 store，任何一行的数据变化都会让它自己重绘。
private struct GestureRow: View {
    let gesture: KnobGesture
    @Environment(DeviceStore.self) private var store

    var body: some View {
        SidebarRow(title: gesture.title,
                   detail: store.draftActions[gesture]?.displayName ?? "—",
                   tile: gesture.tileColor,
                   symbol: gesture.symbol,
                   modified: store.usbConnected && store.isModified(gesture))
    }
}

private struct LightingRow: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        SidebarRow(title: String(localized: "灯效", bundle: L10n.bundle),
                   detail: store.lightingName,
                   tile: .pink,
                   symbol: "sun.max.fill",
                   modified: store.usbConnected && store.isLightingModified)
    }
}

private struct SidebarRow: View {
    var title: String
    var detail: String
    var tile: Color
    var symbol: String
    var modified: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tile.gradient, in: RoundedRectangle(cornerRadius: 5))
            Text(title)
            Spacer(minLength: 8)
            if modified {
                Circle().fill(.tint).frame(width: 6, height: 6)
                    .accessibilityLabel("已修改")
                    .help("已修改，尚未应用")
            }
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

extension KnobGesture {
    var symbol: String {
        switch self {
        case .turnLeft, .holdTurnLeft: "arrow.counterclockwise"
        case .turnRight, .holdTurnRight: "arrow.clockwise"
        case .press: "smallcircle.filled.circle"
        }
    }

    var tileColor: Color {
        switch self {
        case .turnLeft, .turnRight: .blue
        case .press: .orange
        case .holdTurnLeft, .holdTurnRight: .purple
        }
    }
}

// MARK: - 未插线

private struct DisconnectedView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "cable.connector")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Text("插上 USB 线即可修改设置")
                .font(.title3.weight(.semibold))
                .padding(.top, 24)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
                .padding(.top, 8)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        if store.bluetoothConnected {
            return String(localized: "旋钮正通过蓝牙工作。蓝牙只传输按键，不能改键。", bundle: L10n.bundle)
        }
        if store.receiverConnected {
            return String(localized: "旋钮正通过 2.4G 接收器工作。接收器只传输按键，不能改键。", bundle: L10n.bundle)
        }
        return String(localized: "插上数据线后会自动读取旋钮当前的配置。", bundle: L10n.bundle)
    }
}
