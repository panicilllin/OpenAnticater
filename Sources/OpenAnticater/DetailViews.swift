import KnobKit
import SwiftUI

// MARK: - 动作编辑

enum ActionKind: String, CaseIterable, Identifiable {
    case key, media, mouse, text
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .key: "按键"
        case .media: "多媒体"
        case .mouse: "鼠标"
        case .text: "文本"
        }
    }

    init(_ action: KnobAction?) {
        switch action {
        case .keys(let s) where s.count > 1: self = .text
        case .media: self = .media
        case .mouse: self = .mouse
        default: self = .key
        }
    }
}

struct ActionDetailView: View {
    let gesture: KnobGesture
    @Environment(DeviceStore.self) private var store
    @State private var kind: ActionKind = .key
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    KnobView(size: 152, ring: store.lightingRing, demo: .init(gesture))
                    Text(gesture.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section {
                Picker("类型", selection: kindBinding) {
                    ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                editor
            } footer: {
                footer
            }

            if let conflict {
                Section {
                    Label {
                        Text("\(conflict.0) 是系统「\(conflict.1)」的快捷键")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .help("旋钮触发这个动作时，macOS 会直接执行对应的系统功能。")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(gesture.title)
        .onAppear(perform: syncKind)
        .onChange(of: gesture) { syncKind() }
        .onChange(of: store.draftActions[gesture]) { _, new in
            if ActionKind(new) != kind, !(kind == .text && new == .keys([])) { syncKind() }
        }
    }

    // MARK: 各类型的编辑控件

    @ViewBuilder private var editor: some View {
        switch kind {
        case .key:
            LabeledContent("快捷键") {
                ShortcutRecorder(stroke: strokeBinding)
            }
        case .media:
            Picker("多媒体按键", selection: mediaBinding) {
                ForEach(ConsumerUsage.all) { item in
                    Label(item.name, systemImage: item.symbol).tag(item.usage)
                }
            }
        case .mouse:
            Picker("鼠标动作", selection: mouseBinding) {
                ForEach(MousePreset.allCases) { Text($0.name).tag($0) }
            }
            if mouseBinding.wrappedValue.isWheel {
                Picker("同时按住", selection: mouseModifierBinding) {
                    Text("无").tag(Modifiers())
                    Text("⌃ Control").tag(Modifiers.control)
                    Text("⌥ Option").tag(Modifiers.option)
                    Text("⇧ Shift").tag(Modifiers.shift)
                }
            }
        case .text:
            LabeledContent("输出文本") {
                HStack(spacing: 8) {
                    TextField("输出文本", text: $text, prompt: Text("英文、数字或符号"))
                        .labelsHidden()
                        .onChange(of: text) { _, new in applyText(new) }
                    Text(verbatim: "\(text.count)/\(KnobAction.maxKeys)")
                        .monospacedDigit()
                        .foregroundStyle(text.count > KnobAction.maxKeys ? .red : .secondary)
                }
            }
            .help("旋钮会依次输出这些字符")
        }
    }

    /// 脚注只放和当前状态有关、需要用户知道或处理的内容：输入错误、未应用的修改、3 层不一致。
    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = textError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            if store.isModified(gesture) {
                HStack(spacing: 4) {
                    Text("已修改，尚未应用")
                    if store.deviceActions?[gesture] != nil {
                        Text(verbatim: "·")
                        Button("还原") { store.revert(gesture) }
                            .buttonStyle(.link)
                    }
                }
            }
            if !store.layersConsistent {
                Text("旋钮里 3 层的设置不一致，应用后会统一")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var textError: String? {
        guard kind == .text, !text.isEmpty else { return nil }
        if text.count > KnobAction.maxKeys { return String(localized: "最多 \(KnobAction.maxKeys) 个字符", bundle: L10n.bundle) }
        if KeyUsage.strokes(forText: text) == nil { return String(localized: "只支持英文字母、数字和常用符号", bundle: L10n.bundle) }
        return nil
    }

    private var conflict: (String, String)? {
        guard case .keys(let s) = store.draftActions[gesture], s.count == 1,
              let name = SystemShortcut.name(for: s[0]) else { return nil }
        return (s[0].displayName, name)
    }

    // MARK: 绑定

    private var action: KnobAction? {
        get { store.draftActions[gesture] }
        nonmutating set {
            store.draftActions[gesture] = newValue
            store.draftChanged()
        }
    }

    private func syncKind() {
        kind = ActionKind(store.draftActions[gesture])
        if case .keys(let s) = store.draftActions[gesture], s.count > 1 {
            text = KeyUsage.text(forStrokes: s) ?? ""
        } else {
            text = ""
        }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(get: { kind }, set: { newKind in
            guard newKind != kind else { return }
            kind = newKind
            switch newKind {
            case .key: action = .keys([])
            case .media: action = .media(ConsumerUsage.playPause)
            case .mouse: action = .mouse(.leftClick)
            case .text:
                text = ""
                action = .keys([])
            }
        })
    }

    private var strokeBinding: Binding<KeyStroke?> {
        Binding(get: {
            if case .keys(let s) = action, s.count == 1 { return s[0] }
            return nil
        }, set: { new in
            action = .keys(new.map { [$0] } ?? [])
        })
    }

    private var mediaBinding: Binding<UInt16> {
        Binding(get: {
            if case .media(let u) = action { return u }
            return ConsumerUsage.playPause
        }, set: { action = .media($0) })
    }

    private var mouseBinding: Binding<MousePreset> {
        Binding(get: {
            if case .mouse(let m) = action { return MousePreset(m) }
            return .left
        }, set: { preset in
            var m = preset.action
            if case .mouse(let old) = action, preset.isWheel { m.modifiers = old.modifiers }
            action = .mouse(m)
        })
    }

    private var mouseModifierBinding: Binding<Modifiers> {
        Binding(get: {
            if case .mouse(let m) = action { return m.modifiers }
            return []
        }, set: { mods in
            if case .mouse(var m) = action {
                m.modifiers = mods
                action = .mouse(m)
            }
        })
    }

    private func applyText(_ new: String) {
        guard kind == .text else { return }
        if let strokes = KeyUsage.strokes(forText: new), (1...KnobAction.maxKeys).contains(strokes.count) {
            action = .keys(strokes)
        } else {
            action = .keys([])
        }
    }
}

enum MousePreset: String, CaseIterable, Identifiable, Hashable {
    case left, right, middle, wheelUp, wheelDown
    var id: Self { self }

    init(_ m: MouseAction) {
        switch (m.buttons, m.wheel) {
        case (0x02, _): self = .right
        case (0x04, _): self = .middle
        case (_, let w) where w > 0: self = .wheelUp
        case (_, let w) where w < 0: self = .wheelDown
        default: self = .left
        }
    }

    var name: String {
        switch self {
        case .left: String(localized: "左键单击", bundle: L10n.bundle)
        case .right: String(localized: "右键单击", bundle: L10n.bundle)
        case .middle: String(localized: "中键单击", bundle: L10n.bundle)
        case .wheelUp: String(localized: "滚轮向上", bundle: L10n.bundle)
        case .wheelDown: String(localized: "滚轮向下", bundle: L10n.bundle)
        }
    }

    var isWheel: Bool { self == .wheelUp || self == .wheelDown }

    var action: MouseAction {
        switch self {
        case .left: .leftClick
        case .right: .rightClick
        case .middle: .middleClick
        case .wheelUp: .wheelUp
        case .wheelDown: .wheelDown
        }
    }
}

// MARK: - 灯效

struct LightingDetailView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                VStack(spacing: 16) {
                    KnobView(size: 152, ring: store.lightingRing)
                    Text(store.shownLighting == nil ? String(localized: "当前灯效未知", bundle: L10n.bundle) : store.lightingName)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section {
                Picker(selection: modeBinding) {
                    ForEach(LedMode.allCases) { Text($0.name).tag(Optional($0)) }
                } label: {
                    HStack(spacing: 4) {
                        Text("灯效")
                        InfoButton("这台旋钮的固件不支持自选颜色。旋钮读不回灯效，这里显示的是上次从这台 Mac 应用的设置；从没应用过时显示为未知。用蓝牙或 2.4G 时，为了省电只在连接时亮灯。")
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                if store.isLightingModified {
                    HStack(spacing: 4) {
                        Text("已修改，尚未应用")
                        Text(verbatim: "·")
                        Button("还原") { store.revertLighting() }.buttonStyle(.link)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "灯效", bundle: L10n.bundle))
    }

    /// 选中项为 nil 时表示灯效未知，6 个选项都不选中。
    private var modeBinding: Binding<LedMode?> {
        Binding(get: { store.shownLighting?.mode }, set: { mode in
            guard let mode else { return }
            store.draftLighting = mode == store.writtenLighting?.mode ? nil : Lighting(mode: mode)
            store.draftChanged()
        })
    }
}
