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
