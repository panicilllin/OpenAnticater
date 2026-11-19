import Foundation
import KnobKit
import Observation
import ServiceManagement
import UserNotifications

/// 界面状态的唯一来源：连接、电量、旋钮里的配置、正在编辑的草稿。
@MainActor
@Observable
final class DeviceStore {
    // MARK: 连接与电量
    private(set) var usbConnected = false
    private(set) var bluetoothConnected = false
    private(set) var receiverConnected = false
    private(set) var batteryLevel: Int?

    // MARK: 配置
    /// 最近一次从旋钮读到的动作（没插线时是缓存）。
    private(set) var deviceActions: [KnobGesture: KnobAction]?
    private(set) var lastReadDate: Date?
    private(set) var layersConsistent = true
    /// 最近一次从这台 Mac 写入的灯效。老固件读不回灯效，nil 表示不知道旋钮当前的灯效。
    private(set) var writtenLighting: Lighting?
    /// 正在编辑的动作。还没读过旋钮时为空。
    var draftActions: [KnobGesture: KnobAction] = [:]
    /// 在 App 里选了、还没应用的灯效；nil 表示没有改动。
    var draftLighting: Lighting?
    /// 手动重新读取前，有未应用的修改时要先确认。
    var confirmingReload = false

    // MARK: 进行中的操作
    enum Activity: Equatable { case idle, reading, writing(Double) }
    private(set) var activity: Activity = .idle
    var errorMessage: String?
    /// 侧栏当前选中项。放在这里是为了让菜单栏和 ⌘, 能跳到设置。
    var selection: SidebarItem? = .gesture(.press)
    private(set) var lastWriteVerified: Date?
    /// 写入并核对成功后短暂为 true，工具栏用它显示「已应用」。
    private(set) var justApplied = false

    private let connection = KnobConnection()
    private let client: KnobClient
    private let defaults = UserDefaults.standard
    private var lowBatteryNotified = false

    init() {
        client = KnobClient(connection: connection)
        loadCache()
        connection.onConnectionChange = { [weak self] connected in
            self?.usbConnectedChanged(connected)
        }
        usbConnected = connection.isConnected
        refreshSystemStatus()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.refreshSystemStatus()
            }
        }
    }

    // MARK: - 派生状态

    func isModified(_ gesture: KnobGesture) -> Bool {
        guard let device = deviceActions?[gesture] else { return draftActions[gesture] != nil }
        return draftActions[gesture] != device
    }

    var isLightingModified: Bool { draftLighting != nil && draftLighting != writtenLighting }

    /// 界面上显示的灯效：改过就显示改后的，否则显示上次写入的；都没有时为 nil（未知）。
    var shownLighting: Lighting? { draftLighting ?? writtenLighting }

    var lightingName: String {
        shownLighting?.displayName ?? String(localized: "未知", bundle: L10n.bundle)
    }

    var modifiedCount: Int {
        KnobGesture.allCases.filter(isModified).count + (isLightingModified ? 1 : 0)
    }

    /// 不能写入时的原因；能写入时为 nil。
    var writeBlocker: String? {
        if !usbConnected { return String(localized: "用 USB 线连接旋钮后才能写入。", bundle: L10n.bundle) }
        for g in KnobGesture.allCases {
            guard let action = draftActions[g] else { return String(localized: "「\(g.title)」还没有设置。", bundle: L10n.bundle) }
            if case .keys(let s) = action, s.isEmpty { return String(localized: "「\(g.title)」还没有录入按键。", bundle: L10n.bundle) }
            if case .unknown = action { return String(localized: "「\(g.title)」是本 App 不认识的类型，请重新设置。", bundle: L10n.bundle) }
        }
        return nil
    }

    var isBusy: Bool { activity != .idle }

    // MARK: - 操作

    /// 工具栏的「重新读取」：用户想看旋钮的真实状态。有未应用的修改时先确认，确认后放弃这些修改。
    func requestReload() {
        guard usbConnected, !isBusy else { return }
        if modifiedCount > 0 {
            confirmingReload = true
        } else {
            Task { await read(discardingEdits: true) }
        }
    }

    /// 读取旋钮配置。
    /// - discardingEdits: true 时用旋钮的值替换整个草稿（手动重新读取）；
    ///   false 时逐项合并，保留未应用的修改（插线时自动读取）。
    func read(discardingEdits: Bool = false) async {
        guard usbConnected, !isBusy else { return }
        activity = .reading
        defer { activity = .idle }
        do {
            let result = try await client.readActions()
            if discardingEdits {
                draftActions = result.actions
                draftLighting = nil
            } else {
                draftActions = DraftMerge.merge(draft: draftActions, previousDevice: deviceActions,
                                                newDevice: result.actions)
            }
            deviceActions = result.actions
            layersConsistent = result.layersConsistent
            lastReadDate = .now
            saveCache()
        } catch {
            errorMessage = String(localized: "读取失败：\(error.localizedDescription)", bundle: L10n.bundle)
        }
    }

    func write() async {
        guard writeBlocker == nil, !isBusy else { return }
        activity = .writing(0)
        defer { activity = .idle }
        do {
            // 只有在 App 里改过灯效才写灯效，避免覆盖旋钮上 App 不知道的灯效设置。
            let writeLighting = isLightingModified
            let config = KnobConfig(actions: draftActions, lighting: draftLighting ?? Lighting())
            try await client.write(config, includeLighting: writeLighting) { [weak self] p in
                self?.activity = .writing(p)
            }
            if writeLighting {
                writtenLighting = config.lighting
                draftLighting = nil
            }
            // 写完读回来核对。
            let result = try await client.readActions()
            deviceActions = result.actions
            layersConsistent = result.layersConsistent
            lastReadDate = .now
            saveCache()
            ApplyLog.record(written: config.actions, readBack: result.actions,
                            stillModified: KnobGesture.allCases.filter { isModified($0) })
            if result.actions == config.actions {
                lastWriteVerified = .now
                justApplied = true
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2.5))
                    self?.justApplied = false
                }
            } else {
                errorMessage = String(localized: "已写入，但读回的配置和设置的不一致。请重新读取后再试一次。", bundle: L10n.bundle)
            }
        } catch {
            errorMessage = String(localized: "写入失败：\(error.localizedDescription)", bundle: L10n.bundle)
        }
    }

    func revert(_ gesture: KnobGesture) {
        draftActions[gesture] = deviceActions?[gesture]
        saveCache()
    }

    func revertLighting() {
        draftLighting = nil
        saveCache()
    }

    func restoreFactoryDefaults() {
        draftActions = KnobConfig.factoryDefault.actions
        draftLighting = KnobConfig.factoryDefault.lighting
        saveCache()
    }

    /// 草稿变化后调用，把未应用的修改存下来，退出 App 也不会丢。
    func draftChanged() {
        saveCache()
    }

    // MARK: - 连接与系统状态

    private func usbConnectedChanged(_ connected: Bool) {
        usbConnected = connected
        if connected {
            Task { await read() }
        }
    }

    private func refreshSystemStatus() {
        bluetoothConnected = KnobPresence.isBluetoothConnected()
        receiverConnected = KnobPresence.isReceiverConnected()
        batteryLevel = bluetoothConnected ? KnobBattery.level() : nil
        checkLowBattery()
    }

    private func checkLowBattery() {
        guard defaults.object(forKey: SettingsKey.lowBatteryAlert) as? Bool ?? true,
              let level = batteryLevel else { return }
        let threshold = defaults.object(forKey: SettingsKey.lowBatteryThreshold) as? Int ?? 20
        if level > threshold {
            lowBatteryNotified = false
            return
        }
        guard !lowBatteryNotified else { return }
        lowBatteryNotified = true
        let content = UNMutableNotificationContent()
        content.title = String(localized: "ANTICATER MINI 电量低", bundle: L10n.bundle)
        content.body = String(localized: "剩余 \(level)%，请尽快充电。", bundle: L10n.bundle)
        let request = UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 缓存

    private struct Cache: Codable {
        var actions: [KnobGesture: KnobAction]?
        var lastReadDate: Date?
        var layersConsistent: Bool
        var writtenLighting: Lighting?
        /// 未应用的修改，下次打开 App 时恢复。
        var draftActions: [KnobGesture: KnobAction]?
        var draftLighting: Lighting?
    }

    private func saveCache() {
        let cache = Cache(actions: deviceActions, lastReadDate: lastReadDate,
                          layersConsistent: layersConsistent, writtenLighting: writtenLighting,
                          draftActions: draftActions, draftLighting: draftLighting)
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: "deviceCache")
        }
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: "deviceCache"),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        deviceActions = cache.actions
        lastReadDate = cache.lastReadDate
        layersConsistent = cache.layersConsistent
        writtenLighting = cache.writtenLighting
        draftActions = cache.draftActions ?? cache.actions ?? [:]
        draftLighting = cache.draftLighting
    }
}

enum SettingsKey {
    static let showInMenuBar = "showInMenuBar"
    static let lowBatteryAlert = "lowBatteryAlert"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let appearance = "appearance"
    static let language = "appLanguage"
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// 每次「应用」追加一行到 ~/Library/Logs/OpenAnticater/apply.log，便于排查界面状态和旋钮不一致的问题。
enum ApplyLog {
    static func record(written: [KnobGesture: KnobAction], readBack: [KnobGesture: KnobAction],
                       stillModified: [KnobGesture]) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenAnticater")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("apply.log")
        func describe(_ a: [KnobGesture: KnobAction]) -> String {
            KnobGesture.allCases.map { "\($0.rawValue)=\(a[$0]?.displayName ?? "-")" }.joined(separator: " ")
        }
        let line = "\(Date.now.ISO8601Format()) 写入[\(describe(written))] 读回[\(describe(readBack))] 仍标记已修改\(stillModified.map(\.rawValue))\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
