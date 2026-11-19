import Foundation
import IOKit
import IOKit.hid

/// 与旋钮改键通道（USB 接口 0）之间的连接。
///
/// 只匹配厂商自定义用途页 0xFF00 的接口，不会打开键盘、鼠标接口，因此不需要「输入监控」权限。
/// 所有回调都在主线程的 run loop 上执行。
@MainActor
public final class KnobConnection {
    public private(set) var isConnected = false
    /// 连接状态变化时调用。
    public var onConnectionChange: ((Bool) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    private var collector: Collector?
    private var busy = false

    private struct Collector {
        let id = UUID()
        let expected: Int
        var received: [[UInt8]] = []
        let continuation: CheckedContinuation<[[UInt8]], Error>
    }

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: KnobProtocol.vendorID,
            kIOHIDProductIDKey: KnobProtocol.productID,
            kIOHIDPrimaryUsagePageKey: KnobProtocol.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let me = Unmanaged<KnobConnection>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.attach(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let me = Unmanaged<KnobConnection>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.detach(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - 设备插拔

    private func attach(_ newDevice: IOHIDDevice) {
        guard device == nil else { return }
        guard IOHIDDeviceOpen(newDevice, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        device = newDevice
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(newDevice, inputBuffer, 128, { context, result, _, _, _, report, length in
            guard let context, result == kIOReturnSuccess else { return }
            let me = Unmanaged<KnobConnection>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { me.receive(bytes) }
        }, context)
        setConnected(true)
    }

    private func detach(_ removed: IOHIDDevice) {
        guard let device, CFEqual(device, removed) else { return }
        self.device = nil
        busy = false
        if let c = collector {
            collector = nil
            c.continuation.resume(throwing: KnobError.notConnected)
        }
        setConnected(false)
    }

    private func setConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        onConnectionChange?(value)
    }

    // MARK: - 收发

    private func receive(_ report: [UInt8]) {
        guard var c = collector else { return }
        c.received.append(report)
        if c.received.count >= c.expected {
            collector = nil
            c.continuation.resume(returning: c.received)
        } else {
            collector = c
        }
    }

    /// 发送一条报文（不含报告 ID）。
    public func send(_ payload: [UInt8]) throws {
        guard let device else { throw KnobError.notConnected }
        let report = [KnobProtocol.reportID] + payload
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(KnobProtocol.reportID),
                                          report, report.count)
        guard result == kIOReturnSuccess else { throw KnobError.ioError(result) }
    }

    /// 发送请求并收集回复：收满 `expecting` 条或超时为止。超时时只要收到过回复就返回已收到的部分。
    public func request(_ payload: [UInt8], expecting count: Int,
                        timeout: Duration = .milliseconds(800)) async throws -> [[UInt8]] {
        guard device != nil else { throw KnobError.notConnected }
        while busy { try await Task.sleep(for: .milliseconds(20)) }
        busy = true
        defer { busy = false }
        return try await withCheckedThrowingContinuation { continuation in
            let c = Collector(expected: count, continuation: continuation)
            collector = c
            do {
                try send(payload)
            } catch {
                collector = nil
                continuation.resume(throwing: error)
                return
            }
            let id = c.id
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire(id)
            }
        }
    }

    private func expire(_ id: UUID) {
        guard let c = collector, c.id == id else { return }
        collector = nil
        if c.received.isEmpty {
            c.continuation.resume(throwing: KnobError.timeout)
        } else {
            c.continuation.resume(returning: c.received)
        }
    }
}
