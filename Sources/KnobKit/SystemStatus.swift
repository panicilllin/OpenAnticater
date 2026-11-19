import Foundation
import IOKit
import IOKit.ps

/// 旋钮在系统里的其他连接方式：蓝牙、2.4G 接收器。
///
/// 只读 IORegistry 里的属性，不打开任何设备，所以不需要「输入监控」权限。
public enum KnobPresence {
    /// 蓝牙名（说明书写明）。
    public static let bluetoothName = "ANTICATER_MINI"
    /// 2.4G 接收器 USB ID。
    public static let receiverVendorID = 0x514C
    public static let receiverProductID = 0x4155

    public static func isBluetoothConnected() -> Bool {
        hidDeviceExists(matching: [kIOHIDProductKey: bluetoothName, kIOHIDTransportKey: "Bluetooth Low Energy"])
    }

    public static func isReceiverConnected() -> Bool {
        hidDeviceExists(matching: [kIOHIDVendorIDKey: receiverVendorID, kIOHIDProductIDKey: receiverProductID])
    }

    /// 原厂 App 认的 USB 厂商 ID。
    public static let vendorIDs = [0x1189, 0x514C]

    /// 系统里一个 HID 接口的公开属性。不含序列号。
    public struct HIDInterface: Sendable, Equatable {
        public var vendorID: Int
        public var productID: Int
        public var product: String?
        public var transport: String?
        public var usagePage: Int
        public var usage: Int
        public var maxInputReportSize: Int
        public var maxOutputReportSize: Int
        public var maxFeatureReportSize: Int

        /// 一行文字，供 `knobctl list` 输出和设备反馈使用。
        public var summary: String {
            String(format: "%04X:%04X  usage %04X:%04X  in %d  out %d  feature %d  ",
                   vendorID, productID, usagePage, usage,
                   maxInputReportSize, maxOutputReportSize, maxFeatureReportSize)
                + "\(transport ?? "?")  \"\(product ?? "")\""
        }
    }

    /// 列出可能是 ANTICATER 设备的 HID 接口：厂商 ID 在 `vendorIDs` 里，或产品名含 "ANTICATER"。
    ///
    /// 只读 IORegistry 里的属性，不打开设备，也不发送任何报文。
    public static func candidateInterfaces() -> [HIDInterface] {
        guard let dict = IOServiceMatching(kIOHIDDeviceKey) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, dict, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [HIDInterface] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func value(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            func int(_ key: String) -> Int { (value(key) as? NSNumber)?.intValue ?? 0 }
            let product = value(kIOHIDProductKey) as? String
            let vendor = int(kIOHIDVendorIDKey)
            guard vendorIDs.contains(vendor) || product?.uppercased().contains("ANTICATER") == true else { continue }
            result.append(HIDInterface(
                vendorID: vendor, productID: int(kIOHIDProductIDKey), product: product,
                transport: value(kIOHIDTransportKey) as? String,
                usagePage: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey),
                maxInputReportSize: int(kIOHIDMaxInputReportSizeKey),
                maxOutputReportSize: int(kIOHIDMaxOutputReportSizeKey),
                maxFeatureReportSize: int(kIOHIDMaxFeatureReportSizeKey)))
        }
        return result.sorted { ($0.vendorID, $0.productID, $0.usagePage, $0.usage)
            < ($1.vendorID, $1.productID, $1.usagePage, $1.usage) }
    }

    private static func hidDeviceExists(matching properties: [String: Any]) -> Bool {
        guard let dict = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else { return false }
        dict[kIOPropertyMatchKey] = properties
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, dict, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        let first = IOIteratorNext(iterator)
        guard first != 0 else { return false }
        IOObjectRelease(first)
        return true
    }
}

/// 旋钮电量。蓝牙电池服务上报的电量由系统收集，这里从系统的电源列表里读。
///
/// 外设电量只出现在 `IOPSCopyPowerSourcesByType` 的结果里，这个函数没有写进公开头文件，
/// 所以运行时按名字查找；找不到时返回 nil，界面会显示「无法读取」。
public enum KnobBattery {
    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    private static let copyByType: CopyByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return nil }
        return unsafeBitCast(symbol, to: CopyByType.self)
    }()

    /// 电量百分比；旋钮没通过蓝牙连接时返回 nil。
    public static func level(deviceName: String = KnobPresence.bluetoothName) -> Int? {
        guard let copyByType, let info = copyByType(0)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let name = desc[kIOPSNameKey] as? String, name.contains(deviceName) else { continue }
            return desc[kIOPSCurrentCapacityKey] as? Int
        }
        return nil
    }
}
