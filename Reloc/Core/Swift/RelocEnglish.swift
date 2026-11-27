import Foundation

/// Converts remaining Simplified-Chinese messages returned by the native pairing
/// and tunnel libraries into English before they reach the UI or exported logs.
enum RelocEnglish {
    private static let replacements: [(String, String)] = [
        ("设备连接验证超时（请检查 10.7.0.1 回环代理是否已开启）", "Device connection verification timed out. Check that the 10.7.0.1 loopback proxy is enabled."),
        ("打开设备服务连接超时", "Timed out while opening the device service connection."),
        ("设备连接验证任务异常中止", "The device connection verification task terminated unexpectedly."),
        ("打开设备服务任务异常中止", "The device service task terminated unexpectedly."),
        ("配对引擎已结束，请重试", "The pairing engine has stopped. Please try again."),
        ("配对等待超时，请返回 Reloc 重试", "Pairing timed out. Return to Reloc and try again."),
        ("隧道设备 IPv6 地址无效", "The tunnel device IPv6 address is invalid."),
        ("隧道本地 IPv6 地址无效", "The local tunnel IPv6 address is invalid."),
        ("无法读取已保存的配对身份", "Unable to read the saved pairing identity."),
        ("系统时间无效", "The system time is invalid."),
        ("已保存的配对身份无效，请重新导入", "The saved pairing identity is invalid. Please import it again."),
        ("配对身份公私钥不匹配", "The public and private keys in the pairing identity do not match."),
        ("配对数据为空或体积异常", "The pairing data is empty or has an unexpected size."),
        ("配对身份格式无效", "The pairing identity format is invalid."),
        ("配对记录校验未通过", "Pairing record validation failed."),
        ("回环 IP 地址无效", "The loopback IP address is invalid."),
        ("设备连接参数无效", "The device connection parameters are invalid."),
        ("设备连接验证失败", "Device connection verification failed."),
        ("设备连接验证无返回结果", "Device connection verification returned no result."),
        ("无法通过 Remote Pairing 建立设备服务通道", "Unable to establish the device service channel through Remote Pairing."),
        ("打开 Remote Pairing 服务失败", "Failed to open the Remote Pairing service."),
        ("无法读取已保存的配对身份", "Unable to read the saved pairing identity."),
        ("配对数据为空", "The pairing data is empty."),
        ("公私钥不匹配", "The public and private keys do not match."),
        ("配对身份格式无效", "The pairing identity format is invalid."),
        ("配对记录校验未通过", "Pairing record validation failed."),
        ("秒后自动重连（第 ", " sec until automatic reconnection (attempt "),
        ("隧道中断，", "Tunnel interrupted, "),
        ("通道建立失败，", "Channel establishment failed, "),
        ("连接断开，", "Connection lost, "),
        ("Lockdown 中断，", "Lockdown interrupted, "),
        ("无法发布配对服务", "Unable to publish the pairing service"),
        ("无法写入系统钥匙串", "Unable to write to the system Keychain"),
        ("配对文件导入失败：", "Failed to import pairing file: ")
    ]

    static func translate(_ source: String) -> String {
        var result = source
        for (original, english) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
            result = result.replacingOccurrences(of: original, with: english)
        }
        return result
    }
}
