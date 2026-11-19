import Foundation

/// 在 `KnobConnection` 之上的读写操作。
@MainActor
public final class KnobClient {
    public let connection: KnobConnection

    public init(connection: KnobConnection) {
        self.connection = connection
    }

    public func info() async throws -> DeviceInfo {
        let replies = try await connection.request(KnobProtocol.infoRequest(), expecting: 1)
        guard let info = replies.lazy.compactMap(KnobProtocol.parseInfo).first else {
            throw KnobError.unexpectedReply
        }
        return info
    }

    /// 读取一层所有键位。旋钮会回复 24 条记录（键位 1–24）。
    public func readLayer(_ layer: UInt8) async throws -> [UInt8: KnobAction] {
        let replies = try await connection.request(KnobProtocol.readLayerRequest(layer: layer), expecting: 24)
        var result: [UInt8: KnobAction] = [:]
        for record in replies.compactMap(KnobProtocol.parseSlot) where record.layer == layer {
            result[record.slot] = record.action
        }
        return result
    }

    public struct ReadResult: Sendable {
        /// 第 1 层上 5 个旋钮动作的配置。
        public var actions: [KnobGesture: KnobAction]
        /// 3 层里这 5 个动作是否完全一致。不一致时写入会把 3 层统一。
        public var layersConsistent: Bool
    }

    /// 读取 3 层，返回第 1 层的旋钮动作。
    public func readActions() async throws -> ReadResult {
        var layers: [[UInt8: KnobAction]] = []
        for layer in KnobProtocol.layers {
            layers.append(try await readLayer(layer))
        }
        var actions: [KnobGesture: KnobAction] = [:]
        for gesture in KnobGesture.allCases {
            actions[gesture] = layers[0][gesture.rawValue]
        }
        let consistent = KnobGesture.allCases.allSatisfy { g in
            layers.allSatisfy { $0[g.rawValue] == layers[0][g.rawValue] }
        }
        guard actions.count == KnobGesture.allCases.count else { throw KnobError.unexpectedReply }
        return ReadResult(actions: actions, layersConsistent: consistent)
    }

    /// 把配置写进旋钮。3 层写同样的内容，不管固件当前用哪一层，效果都一样。
    ///
    /// 顺序与原厂 App 一致：每层先写各键位和灯效，再发提交命令，之后等 1 秒。
    ///
    /// 灯效读不回来，App 不一定知道旋钮当前的灯效；`includeLighting` 为 false 时只写键位、不动灯效（已实测可行）。
    public func write(_ config: KnobConfig, includeLighting: Bool = true,
                      progress: ((Double) -> Void)? = nil) async throws {
        let layers = Array(KnobProtocol.layers)
        for (index, layer) in layers.enumerated() {
            for gesture in KnobGesture.allCases {
                guard let action = config.actions[gesture] else { continue }
                try connection.send(KnobProtocol.writeRequest(gesture: gesture, layer: layer, action: action))
                try await Task.sleep(for: .milliseconds(20))
            }
            if includeLighting {
                try connection.send(KnobProtocol.lightingRequest(layer: layer, lighting: config.lighting))
                try await Task.sleep(for: .milliseconds(20))
            }
            try connection.send(KnobProtocol.commitRequest())
            try await Task.sleep(for: .seconds(1))
            progress?(Double(index + 1) / Double(layers.count))
        }
    }
}
