import Testing
@testable import KnobKit

/// 以下回复字节是从实物（514C:8850）上用只读命令抓到的原始数据。
private func report(_ hex: String) -> [UInt8] {
    var bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    bytes += [UInt8](repeating: 0, count: 65 - bytes.count)
    return bytes
}

@Test func parsesInfoReply() {
    let info = KnobProtocol.parseInfo(report("03 fb 00 01"))
    #expect(info == DeviceInfo(keyCount: 0, knobCount: 1, version: 0))
}

@Test func parsesKeyboardRecord() throws {
    // 第 1 层键位 16：Ctrl + →
    let r = try #require(KnobProtocol.parseSlot(report("03 fa 10 01 01 00 00 00 00 00 01 01 4f")))
    #expect(r.slot == 16)
    #expect(r.layer == 1)
    #expect(r.action == .keys([KeyStroke(modifiers: .control, usage: 0x4F)]))
}

@Test func parsesMediaRecord() throws {
    // 第 2 层键位 18：音量 −
    let r = try #require(KnobProtocol.parseSlot(report("03 fa 12 02 02 00 00 00 00 00 01 ea 00")))
    #expect(r.action == .media(ConsumerUsage.volumeDown))
    #expect(r.action.displayName == "音量 −")
}

@Test func writeRequestMirrorsReadFormat() throws {
    // 写入报文与读回报文只差命令字节（FD ↔ FA）。
    let action = KnobAction.keys([KeyStroke(modifiers: .control, usage: 0x4F)])
    let w = try KnobProtocol.writeRequest(gesture: .turnLeft, layer: 1, action: action)
    let read = report("03 fa 10 01 01 00 00 00 00 00 01 01 4f")
    #expect(w.count == 64)
    #expect(w[0] == 0xFD)
    #expect(Array(w[1...]) == Array(read[2...]))
}

@Test func mediaWriteRequest() throws {
    let w = try KnobProtocol.writeRequest(gesture: .press, layer: 3, action: .media(ConsumerUsage.playPause))
    #expect(Array(w[0..<12]) == [0xFD, 17, 3, 0x02, 0, 0, 0, 0, 0, 1, 0xCD, 0x00])
}

@Test func mouseRoundTrip() throws {
    let m = MouseAction(modifiers: .control, buttons: 0, wheel: -1)
    var w = try KnobProtocol.writeRequest(gesture: .turnRight, layer: 2, action: .mouse(m))
    w[0] = 0xFA
    let parsed = try #require(KnobProtocol.parseSlot([0x03] + w))
    #expect(parsed.action == .mouse(m))
}

@Test func textRoundTrip() throws {
    let strokes = try #require(KeyUsage.strokes(forText: "Hi!"))
    #expect(strokes == [KeyStroke(modifiers: .shift, usage: 0x0B), KeyStroke(usage: 0x0C),
                        KeyStroke(modifiers: .shift, usage: 0x1E)])
    #expect(KeyUsage.text(forStrokes: strokes) == "Hi!")
}

@Test func rejectsTooManyKeys() {
    let strokes = [KeyStroke](repeating: KeyStroke(usage: 0x04), count: 19)
    #expect(throws: KnobError.self) {
        try KnobProtocol.writeRequest(gesture: .press, layer: 1, action: .keys(strokes))
    }
}

@Test func lightingRequestCarriesModeOnly() {
    // 实测：这台旋钮只看低 4 位的模式，颜色位写 0。
    let p = KnobProtocol.lightingRequest(layer: 1, lighting: Lighting(mode: .rgbCycle))
    #expect(Array(p[0..<12]) == [0xFE, 0xB0, 1, 0x08, 0, 0, 0, 0, 0, 1, 0, 0x04])
    #expect(KnobProtocol.lightingRequest(layer: 2, lighting: Lighting())[11] == 0x05)
    #expect(Lighting().displayName == "快速跑马灯")
}

@Test func commitRequest() {
    #expect(Array(KnobProtocol.commitRequest()[0..<4]) == [0xFD, 0xFE, 0xFF, 0x00])
}

// MARK: - 读取时与草稿合并

private let volDown = KnobAction.media(ConsumerUsage.volumeDown)
private let volUp = KnobAction.media(ConsumerUsage.volumeUp)
private let mute = KnobAction.media(ConsumerUsage.mute)
private let play = KnobAction.media(ConsumerUsage.playPause)

@Test func firstReadTakesDeviceValues() {
    let device: [KnobGesture: KnobAction] = [.turnLeft: volDown, .press: mute]
    #expect(DraftMerge.merge(draft: [:], previousDevice: nil, newDevice: device) == device)
}

@Test func mergeKeepsUnappliedEditsAndRefreshesTheRest() {
    let old: [KnobGesture: KnobAction] = [.turnLeft: volDown, .press: mute, .turnRight: volUp]
    // 用户把「按下」改成了播放 / 暂停，还没应用。
    var draft = old
    draft[.press] = play
    // 与此同时旋钮上的「右转」在别处被改成了静音。
    var new = old
    new[.turnRight] = mute
    let merged = DraftMerge.merge(draft: draft, previousDevice: old, newDevice: new)
    #expect(merged[.press] == play)       // 未应用的修改保留
    #expect(merged[.turnRight] == mute)   // 没改过的项用旋钮的新值
    #expect(merged[.turnLeft] == volDown)
}

@Test func mergeWithoutEditsEqualsDevice() {
    let old: [KnobGesture: KnobAction] = [.turnLeft: volDown, .press: mute]
    let new: [KnobGesture: KnobAction] = [.turnLeft: volUp, .press: mute]
    #expect(DraftMerge.merge(draft: old, previousDevice: old, newDevice: new) == new)
}
