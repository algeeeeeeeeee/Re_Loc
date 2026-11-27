#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const kRelocBundleIdentifier = @"dev.reloc.ios";

static NSDictionary<NSString *, NSString *> *RELTranslations(void) {
    static NSDictionary<NSString *, NSString *> *translations;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        translations = @{
            @"定位": @"Location",
            @"设备连接": @"Device Connection",
            @"实测与日志": @"Diagnostics & Logs",
            @"提示": @"Notice",
            @"确定": @"OK",
            @"取消": @"Cancel",
            @"关闭": @"Close",
            @"应用": @"Apply",
            @"保存": @"Save",
            @"删除": @"Delete",
            @"重命名": @"Rename",
            @"清空": @"Clear",
            @"全部": @"All",
            @"错误": @"Errors",
            @"停止": @"Stop",
            @"开始定位": @"Start Location",
            @"开始实测": @"Start Diagnostics",
            @"重试": @"Retry",
            @"立即刷新": @"Refresh Now",
            @"强制刷新": @"Force Refresh",
            @"去开启": @"Enable",
            @"更新到此位置": @"Update to This Location",
            @"当前设备不可用": @"Device Not Available",
            @"Reloc 仅支持 iPhone": @"Reloc Supports iPhone Only",
            @"Reloc 依赖 iOS 的 CarKit（com.apple.carkit.service）外设定位通道向系统注入 GPS 坐标。由于 iPadOS 不支持 CarPlay 且未提供该系统服务，此应用无法在 iPad 上运行定位模拟。": @"Reloc uses the iOS CarKit (com.apple.carkit.service) accessory-location channel to provide GPS coordinates to the system. iPadOS does not provide this service, so location simulation is unavailable on iPad.",
            @"已连接": @"Connected",
            @"验证中": @"Verifying",
            @"连接失败": @"Connection Failed",
            @"待验证": @"Not Verified",
            @"外部代理提供本地回环": @"Local Loopback Provided by External Proxy",
            @"回环通路": @"Loopback Connection",
            @"配对记录": @"Pairing Record",
            @"尚未配置这台 iPhone": @"This iPhone Has Not Been Paired",
            @"重新配对这台 iPhone": @"Re-pair This iPhone",
            @"一键配对这台 iPhone": @"Pair This iPhone",
            @"悬浮窗指引": @"Floating Guide",
            @"此系统版本请导入已有的配对文件。": @"Import an existing pairing file on this iOS version.",
            @"导入已有配对文件": @"Import Pairing File",
            @"移除已保存配对记录": @"Remove Saved Pairing Record",
            @"设备配对": @"Device Pairing",
            @"重新检测连接": @"Recheck Connection",
            @"检测设备连接": @"Test Device Connection",
            @"设备 UDID": @"Device UDID",
            @"连接验证": @"Connection Verification",
            @"自动发现 Remote Pairing 服务并用配对记录验证广播身份，最终通过设备服务确认连接可用。": @"Automatically discovers the Remote Pairing service, verifies its advertised identity using the pairing record, and confirms device-service availability.",
            @"设备服务": @"Device Service",
            @"回环主机": @"Loopback Host",
            @"广播就绪": @"Broadcast Ready",
            @"输入配对码": @"Enter Pairing Code",
            @"保存完成": @"Saved",
            @"已复制配对码": @"Pairing Code Copied",
            @"复制配对码": @"Copy Pairing Code",
            @"收起悬浮指引窗": @"Hide Floating Guide",
            @"弹出悬浮指引窗": @"Show Floating Guide",
            @"取消配对": @"Cancel Pairing",
            @"依次完成回环通路、本机配对与连接验证": @"Complete the loopback connection, device pairing, and connection verification in order",
            @"设备回环已就绪": @"Device Loopback Ready",
            @"配置本机回环连接": @"Configure Local Loopback",
            @"可直接返回「定位」标签页开始定格定位": @"Return to the Location tab to set a fixed location",
            @"配对状态": @"Pairing Status",
            @"已保存": @"Saved",
            @"未配置": @"Not Configured",
            @"定位选项": @"Location Options",
            @"NMEA 发送间隔 · %.1f 秒": @"NMEA Send Interval · %.1f sec",
            @"持续运行": @"Continuous",
            @"60 秒": @"60 seconds",
            @"180 秒": @"180 seconds",
            @"600 秒": @"600 seconds",
            @"1800 秒": @"1800 seconds",
            @"会话时长": @"Session Duration",
            @"中国大陆地图 GCJ-02 纠偏": @"Mainland China Map GCJ-02 Correction",
            @"自然微漂移（±0.6m GPS 抖动）": @"Natural Micro-drift (±0.6 m GPS Jitter)",
            @"后台保活（切换地图不断连）": @"Background Keep-Alive (Stay Connected When Switching Maps)",
            @"外观主题": @"Appearance",
            @"地图数据源": @"Map Source",
            @"Apple 地图样式": @"Apple Maps Style",
            @"地图与外观": @"Map & Appearance",
            @"默认使用 Apple 系统地图（MapKit 原生）；如需无高德字样的纯国际 WGS-84 底图，可切换为全球街道图、OpenStreetMap 或全球卫星图。": @"Apple Maps (native MapKit) is used by default. For an international WGS-84 map without Amap branding, switch to Global Streets, OpenStreetMap, or Global Satellite.",
            @"设备配对与连接": @"Device Pairing & Connection",
            @"停止定位并恢复真实位置？": @"Stop Location and Restore the Real Position?",
            @"停止并恢复": @"Stop & Restore",
            @"停止后系统将逐步切回本机真实 GPS 位置。": @"After stopping, the system will gradually return to the iPhone's real GPS location.",
            @"搜索地点或输入 纬度, 经度": @"Search for a Place or Enter Latitude, Longitude",
            @"清空搜索": @"Clear Search",
            @"手动输入坐标": @"Enter Coordinates Manually",
            @"坐标": @"Coordinates",
            @"手动输入经纬度": @"Enter Latitude and Longitude",
            @"外设定位已生效 ✓": @"Accessory Location Active ✓",
            @"已鉴权 · 待刷新订阅": @"Authenticated · Waiting for Subscription Refresh",
            @"已鉴权 · 唤醒订阅中…": @"Authenticated · Waking Subscription…",
            @"建立回环连接中…": @"Establishing Loopback Connection…",
            @"回环已就绪": @"Loopback Ready",
            @"已配对 · 可一键定位": @"Paired · Ready to Set Location",
            @"未配对设备": @"Device Not Paired",
            @"未知地点": @"Unknown Place",
            @"上次定位会话意外中断": @"The Previous Location Session Ended Unexpectedly",
            @"恢复": @"Restore",
            @"尚未配对这台 iPhone，前往「设备连接」一键配对": @"This iPhone is not paired. Open Device Connection to pair it.",
            @"未开启定位权限，无法自动触发外设订阅": @"Location permission is disabled. The accessory subscription cannot start automatically.",
            @"未开启「精确位置」，可能导致外设 GPS 无法锁定或偏移": @"Precise Location is disabled. Accessory GPS may not lock or may be offset.",
            @"已恢复本机真实 GPS 定位": @"The iPhone's Real GPS Location Has Been Restored",
            @"外设连接已断开，但系统仍在缓存上次定位（室内弱信号常见）。点击下方一键刷新定位服务即可立即恢复真实位置。": @"The accessory connection has ended, but the system is still using a cached location. Tap the button below to refresh Location Services and restore the real position.",
            @"一键刷新定位服务（恢复真实位置）": @"Refresh Location Services (Restore Real Location)",
            @"已发送断开与失效报文，正在唤醒本机真实 GPS 恢复定位…": @"Disconnect and invalidation messages sent. Waking the iPhone's real GPS…",
            @"外设 GPS 已 100% 生效": @"Accessory GPS Is Active",
            @"系统已确认外设来源（isProducedByAccessory = true），可直接切去任意 App": @"The system confirmed the accessory as the location source (isProducedByAccessory = true). You can switch to another app.",
            @"MFi 鉴权已通过，但系统尚未订阅外设 GPS。点击下方一键刷新（含悬浮 5 秒倒计时）即可唤醒订阅。": @"MFi authentication succeeded, but the system has not subscribed to accessory GPS yet. Tap Refresh below to wake the subscription (includes a floating 5-second countdown).",
            @"NMEA 已连通，但系统仍在沿用本机缓存定位。点击下方一键刷新（含悬浮 5 秒倒计时）即可 100% 强制切换。": @"NMEA is connected, but the system is still using the iPhone's cached location. Tap Refresh below to force the switch (includes a floating 5-second countdown).",
            @"一键刷新定位服务（浮窗指引）": @"Refresh Location Services (Floating Guide)",

            @"正在连接设备回环并完成 MFi 鉴权…": @"Connecting to the device loopback and completing MFi authentication…",
            @"鉴权成功，正在自动唤醒系统外设 GPS 订阅…": @"Authentication succeeded. Waking the system's accessory GPS subscription…",
            @"正在高速注入 NMEA 坐标，等待系统锁定外设源…": @"Injecting NMEA coordinates at high speed and waiting for the system to lock onto the accessory…",
            @"未找到匹配地点，可尝试换个关键词": @"No matching places found. Try another keyword.",
            @"搜索过于频繁，请稍后再试": @"Search rate limit reached. Try again later.",
            @"搜索失败，请检查网络连接": @"Search failed. Check your network connection.",
            @"当前位置": @"Current Location",
            @"待更新位置": @"Pending Location Update",
            @"分类": @"Category",
            @"收藏当前选中位置": @"Add Selected Location to Favorites",
            @"输入名称": @"Enter a Name",
            @"已保存收藏": @"Favorite Saved",
            @"暂无收藏地点": @"No Favorite Locations",
            @"暂无最近使用记录": @"No Recent Locations",
            @"最近使用（最多 30 条）": @"Recent Locations (Up to 30)",
            @"收藏与历史": @"Favorites & History",
            @"重命名收藏": @"Rename Favorite",
            @"新名称": @"New Name",
            @"纬度 (-90 ~ 90)": @"Latitude (-90 to 90)",
            @"经度 (-180 ~ 180)": @"Longitude (-180 to 180)",
            @"海拔 (米)": @"Altitude (meters)",
            @"WGS-84 坐标": @"WGS-84 Coordinates",
            @"请输入合法的纬度（-90 ~ 90）和经度（-180 ~ 180）。": @"Enter a valid latitude (-90 to 90) and longitude (-180 to 180).",
            @"保存到收藏（可选）": @"Save to Favorites (Optional)",
            @"地点名称": @"Place Name",
            @"暂无协议事件": @"No Protocol Events",
            @"开始定位或连接验证后，这里会实时展示连接握手与 NMEA 数据流。": @"Connection handshakes and NMEA data will appear here after you start location or test the connection.",
            @"定位实测与日志": @"Location Diagnostics & Logs",
            @"筛选事件（如 FFFA / acknowledged）": @"Filter Events (e.g. FFFA / acknowledged)",
            @"CoreLocation 实时实测": @"Live CoreLocation Diagnostics",
            @"正在实时读取系统上报定位来源": @"Reading the location source reported by the system",
            @"验证系统是否识别为外设 GPS": @"Verify Whether the System Recognizes Accessory GPS",
            @"纬度 / 经度": @"Latitude / Longitude",
            @"精度 / 海拔": @"Accuracy / Altitude",
            @"软件模拟": @"Software Simulation",
            @"外设来源": @"Accessory Source",
            @"点击右上角「开始实测」，即可实时查看 iOS sourceInformation 中的软件模拟与外设定位标记。": @"Tap “Start Diagnostics” in the upper-right corner to view the software-simulation and accessory-location flags in iOS sourceInformation.",
            @"准备设备配对…": @"Preparing Device Pairing…",
            @"请保持本机网络回环已开启": @"Keep the local network loopback enabled",
            @"准备本机配对服务…": @"Preparing the Local Pairing Service…",
            @"正在启动 Bonjour 配对广播": @"Starting Bonjour Pairing Broadcast",
            @"关闭后将自动开始 5 秒倒计时，无需手动计时": @"A 5-second countdown starts automatically after switching it off",
            @"定位刷新已取消": @"Location Refresh Cancelled",
            @"配对成功 · 记录已保存": @"Pairing Successful · Record Saved",
            @"配对未完成": @"Pairing Incomplete",
            @"Reloc · 设备配对": @"Reloc · Device Pairing",
            @"Reloc · 一键触发定位": @"Reloc · One-Tap Location",
            @"Reloc · 设备配对指引": @"Reloc · Device Pairing Guide",
            @"请在「系统设置」弹窗中输入以上 6 位配对码": @"Enter the 6-digit pairing code above in the System Settings prompt",
            @"现在重新打开！": @"Turn it back on now!",
            @"尚未开始设备配对": @"Device Pairing Has Not Started",
            @"设备端配对需要 iOS 27 或更新版本的真实 iPhone。": @"On-device pairing requires a real iPhone running iOS 27 or later.",
            @"当前系统请导入已有的配对文件；设备端直接配对需要 iOS 27。": @"Import an existing pairing file on this iOS version. On-device pairing requires iOS 27.",
            @"系统结束了后台配对时间，请返回 Reloc 重试。": @"The system ended the background pairing session. Return to Reloc and try again.",
            @"无法启动设备配对服务。": @"Unable to Start the Device Pairing Service.",
            @"配对服务返回了无效的广播参数。": @"The pairing service returned invalid broadcast parameters.",
            @"请前往「设置 → 隐私与安全性 → 开发者模式」，在底部选择「与 Reloc 配对」。": @"Go to Settings → Privacy & Security → Developer Mode, then select “Pair with Reloc” at the bottom.",
            @"① 设置 → 隐私与安全性 → 开发者模式": @"① Settings → Privacy & Security → Developer Mode",
            @"滑到底部点击「与 Reloc 配对」，配对码将显示在此处": @"Scroll to the bottom and tap “Pair with Reloc”. The pairing code will appear here.",
            @"系统已连接，正在生成配对码…": @"System Connected. Generating Pairing Code…",
            @"② 系统已连接": @"② System Connected",
            @"正在协商安全通道并生成 6 位配对码…": @"Negotiating a secure channel and generating a 6-digit pairing code…",
            @"请在系统设置中输入以下 6 位配对码。": @"Enter the following 6-digit pairing code in System Settings.",
            @"请输入配对码": @"Enter Pairing Code",
            @"请在系统设置弹窗中输入 6 位配对码": @"Enter the 6-digit pairing code in the System Settings prompt",
            @"系统未返回完整的配对记录。": @"The system did not return a complete pairing record.",
            @"配对记录已自动保存": @"Pairing Record Saved Automatically",
            @"设备配对未完成。": @"Device Pairing Incomplete.",
            @"配对已结束": @"Pairing Ended",
            @"配对完成，可返回 Reloc 开始定位": @"Pairing Complete. Return to Reloc to start location.",
            @"无法通过 Remote Pairing 建立设备服务通道": @"Unable to Establish a Device Service Channel Through Remote Pairing",
            @"设备连接验证无返回结果": @"Device Connection Verification Returned No Result",
            @"设备连接验证失败": @"Device Connection Verification Failed",
            @"配对记录校验未通过": @"Pairing Record Validation Failed",
            @"公私钥不匹配": @"Public and Private Keys Do Not Match",
            @"配对身份格式无效": @"Invalid Pairing Identity Format",
            @"配对数据为空": @"Pairing Data Is Empty",
            @"打开 Remote Pairing 服务失败": @"Failed to Open the Remote Pairing Service",
            @"设备身份与回环连接已验证": @"Device Identity and Loopback Connection Verified",
            @"请先配对这台 iPhone": @"Pair This iPhone First",
            @"不支持 iPad（仅支持 iPhone）": @"iPad Not Supported (iPhone Only)",
            @"正在解析地名…": @"Resolving Place Name…",
            @"请先配对这台 iPhone 或导入配对文件": @"Pair This iPhone or Import a Pairing File First",
            @"正在发现服务并验证配对身份…": @"Discovering the Service and Verifying Pairing Identity…",
            @"请先在「设备连接」页面完成本机配对或导入配对文件，并确保外部代理已启用 10.7.0.1 回环映射。": @"Complete on-device pairing or import a pairing file on the Device Connection page, and make sure your external proxy has enabled the 10.7.0.1 loopback mapping.",
            @"内置配件认证组件不可用，请重新安装应用。": @"The built-in accessory authentication component is unavailable. Reinstall the app.",
            @"定位会话已停止": @"Location Session Stopped",
            @"高德地图": @"Amap"
        };
    });
    return translations;
}

static NSString *RELTranslate(id value) {
    if (![value isKindOfClass:[NSString class]]) return value;
    NSString *source = (NSString *)value;
    NSString *translated = RELTranslations()[source];
    if (translated) return translated;

    // Dynamic values that include counts, coordinates, port numbers, or error details.
    if ([source hasPrefix:@"已连接回环端口："])
        return [@"Loopback port connected: " stringByAppendingString:[source substringFromIndex:@"已连接回环端口：".length]];
    if ([source hasPrefix:@"恢复上次位置："])
        return [@"Restore Previous Location: " stringByAppendingString:[source substringFromIndex:@"恢复上次位置：".length]];
    if ([source hasPrefix:@"上次错误："])
        return [@"Last Error: " stringByAppendingString:[source substringFromIndex:@"上次错误：".length]];
    if ([source hasPrefix:@"配对文件导入失败："])
        return [@"Failed to Import Pairing File: " stringByAppendingString:[source substringFromIndex:@"配对文件导入失败：".length]];
    if ([source hasPrefix:@"收藏 ("] && [source hasSuffix:@")"])
        return [@"Favorites " stringByAppendingString:[source substringFromIndex:@"收藏 ".length]];
    if ([source hasPrefix:@"最近记录 ("] && [source hasSuffix:@")"])
        return [@"Recent Records " stringByAppendingString:[source substringFromIndex:@"最近记录 ".length]];
    if ([source hasPrefix:@"已保存（"] && [source hasSuffix:@"）"])
        return [NSString stringWithFormat:@"Saved (%@)", [source substringWithRange:NSMakeRange(4, source.length - 5)]];
    if ([source hasPrefix:@"已锁定「"] && [source containsString:@"」，可返回任意 App 使用"])
        return [[source stringByReplacingOccurrencesOfString:@"已锁定「" withString:@"Locked onto “"]
                stringByReplacingOccurrencesOfString:@"」，可返回任意 App 使用" withString:@"”. You can switch to any app."];

    return source;
}

%hook NSBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:kRelocBundleIdentifier]) {
        NSString *translated = RELTranslate(key);
        if (![translated isEqualToString:key]) return translated;
    }
    return %orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig(RELTranslate(text));
}
%end

%hook UIButton
- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    %orig(RELTranslate(title), state);
}
%end

%hook UIBarButtonItem
- (void)setTitle:(NSString *)title {
    %orig(RELTranslate(title));
}
%end

%hook UINavigationItem
- (void)setTitle:(NSString *)title {
    %orig(RELTranslate(title));
}
%end

%hook UITextField
- (void)setPlaceholder:(NSString *)placeholder {
    %orig(RELTranslate(placeholder));
}
%end

%hook UISearchBar
- (void)setPlaceholder:(NSString *)placeholder {
    %orig(RELTranslate(placeholder));
}
%end

%hook UITextView
- (void)setText:(NSString *)text {
    %orig(RELTranslate(text));
}
%end

%hook UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle {
    return %orig(RELTranslate(title), RELTranslate(message), preferredStyle);
}
%end

%hook UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *action))handler {
    return %orig(RELTranslate(title), style, handler);
}
%end

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:kRelocBundleIdentifier]) return;
        NSLog(@"[RelocEnglish] English UI translation loaded for %@", kRelocBundleIdentifier);
    }
}
