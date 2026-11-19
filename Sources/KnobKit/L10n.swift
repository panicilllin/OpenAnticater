import Foundation

/// App 内切换语言用的本地化来源，不需要重启 App。
///
/// 代码里拼出来的文字都写成 `String(localized: "…", bundle: L10n.bundle)`；
/// 切换语言时把 `bundle` 换成对应的 `xx.lproj` 子包，SwiftUI 界面则跟随环境里的 `locale`。
public enum L10n {
    /// 当前用来查找翻译的包。跟随系统时就是主包。
    nonisolated(unsafe) public static var bundle: Bundle = .main

    /// 切换到指定语言（如 "en"、"zh-Hans"）；nil 表示跟随系统。返回界面应使用的 Locale。
    @discardableResult
    public static func use(language: String?) -> Locale {
        guard let language,
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let lproj = Bundle(path: path) else {
            bundle = .main
            return .autoupdatingCurrent
        }
        bundle = lproj
        return Locale(identifier: language)
    }
}
