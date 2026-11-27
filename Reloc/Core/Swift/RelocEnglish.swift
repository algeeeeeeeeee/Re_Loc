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
        ("配对文件导入失败：", "Failed to import pairing file: "),
        ("无法连接回环地址 ", "Unable to connect to loopback address "),
        ("（请确认外部代理已开启 10.7.0.1 回环）：", " (make sure the external proxy has enabled the 10.7.0.1 loopback): "),
        ("Remote Pairing 身份验证失败：", "Remote Pairing identity verification failed: "),
        ("配对记录校验未通过，请重新配对这台 iPhone：", "Pairing record validation failed. Please re-pair this iPhone: "),
        ("无法创建设备加密隧道：", "Unable to create the encrypted device tunnel: "),
        ("无法连接设备隧道端口 ", "Unable to connect to device tunnel port "),
        ("TLS-PSK 隧道握手失败：", "TLS-PSK tunnel handshake failed: "),
        ("无法连接 RSD 服务发现端口 ", "Unable to connect to RSD discovery port "),
        ("RSD 服务发现握手失败：", "RSD service discovery handshake failed: "),
        ("序列化 plist 失败：", "Failed to serialize the plist: "),
        ("写入 RSDCheckin 长度失败：", "Failed to write the RSDCheckin length: "),
        ("写入 RSDCheckin 数据失败：", "Failed to write the RSDCheckin data: "),
        ("刷新 RSDCheckin 失败：", "Failed to flush RSDCheckin: "),
        ("读取 RSDCheckin 响应长度失败：", "Failed to read the RSDCheckin response length: "),
        ("RSDCheckin 响应长度异常：", "Unexpected RSDCheckin response length: "),
        ("读取 RSDCheckin 响应体失败：", "Failed to read the RSDCheckin response body: "),
        ("解析 RSDCheckin 响应失败：", "Failed to parse the RSDCheckin response: "),
        ("RSDCheckin 握手回复异常", "Unexpected RSDCheckin handshake response."),
        ("RSD StartService 握手回复异常", "Unexpected RSD StartService handshake response."),
        ("无法启动配对监听：", "Unable to start the pairing listener: "),
        ("配对连接未建立：", "The pairing connection was not established: "),
        ("设备配对未完成：", "Device pairing was not completed: "),
        ("无法连接 RSD lockdownd：", "Unable to connect to RSD lockdownd: "),
        ("无法启动服务 ", "Unable to start service "),
        ("无法连接服务 ", "Unable to connect to service "),
        (" (端口 ", " (port "),
        ("创建本地桥接通道失败：", "Failed to create the local bridge channel: "),
        ("转换桥接句柄失败：", "Failed to convert the bridge handle: "),
        ("无法连接回环地址", "Unable to connect to the loopback address"),
        ("序列化 plist 失败", "Failed to serialize the plist"),
        ("配对身份的公私钥不匹配", "The public and private keys in the pairing identity do not match."),
        ("配对记录校验未通过，请重新配对这台 iPhone", "Pairing record validation failed. Please re-pair this iPhone."),
    ]

    static func translate(_ source: String) -> String {
        var result = source
        for (original, english) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
            result = result.replacingOccurrences(of: original, with: english)
        }
        return result
    }
}
