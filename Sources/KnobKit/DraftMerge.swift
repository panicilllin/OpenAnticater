import Foundation

/// 读到旋钮的新配置时，怎样和 App 里正在编辑的草稿合并。
public enum DraftMerge {
    /// 逐项合并：用户改过、还没应用的项保留草稿里的值；没改过的项换成旋钮的新值。
    ///
    /// 「改过」指草稿和上一次读到的旋钮值不同。没有上一次的值（第一次读取）时，直接用旋钮的新值。
    public static func merge(draft: [KnobGesture: KnobAction],
                             previousDevice: [KnobGesture: KnobAction]?,
                             newDevice: [KnobGesture: KnobAction]) -> [KnobGesture: KnobAction] {
        guard let previousDevice else { return newDevice }
        var result = newDevice
        for gesture in KnobGesture.allCases {
            if let edited = draft[gesture], edited != previousDevice[gesture] {
                result[gesture] = edited
            }
        }
        return result
    }
}
