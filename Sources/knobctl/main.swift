import Foundation
import KnobKit

// 命令行调试工具 / Command-line debugging tool
//
// 只读 / read-only:
//   knobctl status                         蓝牙、接收器连接状态和电量
//   knobctl info                           查询键数、旋钮数、版本
//   knobctl read                           读取 3 层的 5 个旋钮动作
//
// 会写入旋钮 / writes to the knob:
//   knobctl write-slot <键位> <层> media <hex> | key <修饰键hex> <键码hex>
//   knobctl write-current [灯效0-5]          把第 1 层的动作写进 3 层，并写灯效
//   knobctl led <0-5>                      只写灯效
//   knobctl led-raw <hex> [秒]              直接写灯效字节（探测用）

@MainActor
func run() async -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = args.first ?? "read"

    if command == "status" {
        print("蓝牙：\(KnobPresence.isBluetoothConnected() ? "已连接" : "未连接")")
        print("2.4G 接收器：\(KnobPresence.isReceiverConnected() ? "已插入" : "未插入")")
        print("电量：\(KnobBattery.level().map { "\($0)%" } ?? "读不到")")
        return 0
    }

    let connection = KnobConnection()
    let client = KnobClient(connection: connection)
    // 等匹配回调把设备接上。
    for _ in 0..<20 where !connection.isConnected {
        try? await Task.sleep(for: .milliseconds(50))
    }
    guard connection.isConnected else {
        print("没有找到用 USB 线连接的旋钮（514C:8850）。")
        return 1
    }
    do {
        switch command {
        case "info":
            let info = try await client.info()
            print("键数 \(info.keyCount)，旋钮数 \(info.knobCount)，版本 \(info.version)")
        case "read":
            for layer in KnobProtocol.layers {
                let slots = try await client.readLayer(layer)
                print("第 \(layer) 层")
                for g in KnobGesture.allCases {
                    print("  \(g.title)（键位 \(g.rawValue)）：\(slots[g.rawValue]?.displayName ?? "—")")
                }
            }
        case "write-current":
            // 用 App 同一个写入流程（KnobClient.write）：把第 1 层当前的 5 个动作写进 3 层，并写灯效。
            // knobctl write-current [灯效模式0-5]
            let mode = args.count > 1 ? UInt8(args[1]).flatMap(LedMode.init(rawValue:)) ?? .fastMarquee : .fastMarquee
            let before = try await client.readLayer(1)
            var actions: [KnobGesture: KnobAction] = [:]
            for g in KnobGesture.allCases { actions[g] = before[g.rawValue] }
            let config = KnobConfig(actions: actions, lighting: Lighting(mode: mode))
            print("写入 3 层：")
            for g in KnobGesture.allCases { print("  \(g.title)：\(actions[g]?.displayName ?? "—")") }
            print("  灯效：\(config.lighting.displayName)（灯效字节 0x"
                  + String(format: "%02X", KnobProtocol.lightingRequest(layer: 1, lighting: config.lighting)[11]) + "）")
            try await client.write(config) { p in print("  进度 \(Int(p * 100))%") }
            let result = try await client.readActions()
            print("读回第 1 层 \(result.actions == actions ? "✓ 与写入一致" : "✗ 不一致")；3 层\(result.layersConsistent ? "已统一 ✓" : "仍不一致 ✗")")
        case "led":
            // 只写灯效（3 层，每层提交）：knobctl led <模式0-5>
            guard args.count >= 2, let m = UInt8(args[1]).flatMap(LedMode.init(rawValue:)) else {
                print("用法：knobctl led <模式0-5>  （0 关闭 1 白光 2 绿光 3 跑马灯 4 红绿蓝轮换 5 快速跑马灯）")
                return 2
            }
            let lighting = Lighting(mode: m)
            for layer in KnobProtocol.layers {
                let p = KnobProtocol.lightingRequest(layer: layer, lighting: lighting)
                if layer == 1 { print("灯效 \(lighting.displayName)：03 " + p.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")) }
                try connection.send(p)
                try await Task.sleep(for: .milliseconds(20))
                try connection.send(KnobProtocol.commitRequest())
                try await Task.sleep(for: .seconds(1))
            }
            print("已发送")
        case "led-raw":
            // 探测用：直接写灯效字节到 3 层，然后保持若干秒。knobctl led-raw <hex> [秒]
            guard args.count >= 2, let byte = UInt8(args[1], radix: 16) else { return 2 }
            let hold = args.count > 2 ? Double(args[2]) ?? 0 : 0
            for layer in KnobProtocol.layers {
                var p = KnobProtocol.lightingRequest(layer: layer, lighting: Lighting())
                p[11] = byte
                try connection.send(p)
                try await Task.sleep(for: .milliseconds(20))
                try connection.send(KnobProtocol.commitRequest())
                try await Task.sleep(for: .milliseconds(300))
            }
            print(String(format: "灯效字节 0x%02X 已发送", byte))
            if hold > 0 { try await Task.sleep(for: .seconds(hold)) }
        case "write-slot":
            // knobctl write-slot <键位> <层> media <用途码hex>
            // knobctl write-slot <键位> <层> key <修饰键hex> <键码hex>
            guard args.count >= 5, let slot = UInt8(args[1]), let layer = UInt8(args[2]),
                  let gesture = KnobGesture(rawValue: slot), KnobProtocol.layers.contains(layer) else {
                print("用法：knobctl write-slot <16|17|18|19|21> <1-3> media <hex> | key <修饰键hex> <键码hex>")
                return 2
            }
            let action: KnobAction
            switch args[3] {
            case "media":
                guard let u = UInt16(args[4], radix: 16) else { return 2 }
                action = .media(u)
            case "key":
                guard args.count >= 6, let m = UInt8(args[4], radix: 16), let u = UInt8(args[5], radix: 16) else { return 2 }
                action = .keys([KeyStroke(modifiers: Modifiers(rawValue: m), usage: u)])
            default:
                return 2
            }
            let packet = try KnobProtocol.writeRequest(gesture: gesture, layer: layer, action: action)
            print("写入 第\(layer)层 \(gesture.title)（键位 \(slot)）= \(action.displayName)")
            print("  报文 03 " + packet.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ") + " …")
            try connection.send(packet)
            try await Task.sleep(for: .milliseconds(20))
            try connection.send(KnobProtocol.commitRequest())
            try await Task.sleep(for: .seconds(1))
            let back = try await client.readLayer(layer)[slot]
            print("读回：\(back?.displayName ?? "—")  \(back == action ? "✓ 一致" : "✗ 不一致")")
        default:
            print("未知命令：\(command)")
            return 2
        }
    } catch {
        print("出错：\(error.localizedDescription)")
        return 1
    }
    return 0
}

exit(await run())
