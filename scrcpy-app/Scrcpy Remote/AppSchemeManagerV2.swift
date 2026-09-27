//
//  AppSchemeManagerV2.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//

import Foundation
import UIKit

/*
 AppSchemeManagerV2 支持以下 URL Scheme 格式：

 1. 传统的 host:port 方式：
    scrcpy2://192.168.1.100:5555?max-size=1920&bit-rate=8M
 
 2. 使用会话 UUID：
    scrcpy2://550e8400-e29b-41d4-a716-446655440000?max-size=1920&bit-rate=8M
 
 3. 执行 Action（动作）：
    scrcpy2://550e8400-e29b-41d4-a716-446655440000?type=action
 
 支持的参数覆盖：
 - host: 覆盖主机地址
 - port: 覆盖端口号
 - session-name/name: 覆盖会话名称
 - use-tailscale/tailscale: 是否使用 Tailscale (true/false)
 
 ADB 参数：
 - max-size: 最大屏幕尺寸
 - video-bit-rate/bit-rate: 视频比特率
 - max-fps: 最大帧率
 - video-codec: 视频编解码器 (h264/h265)
 - video-encoder: 视频编码器
 - audio-codec: 音频编解码器 (opus/aac/flac/raw)
 - audio-encoder: 音频编码器
 - enable-audio/audio: 启用音频 (true/false)
 - clipboard-sync: 启用剪贴板同步 (true/false)
 - no-clipboard-autosync: 禁用剪贴板自动同步 (true/false)
 - volume-scale: 音量缩放 (0.0-50.0)
 - start-new-display/new-display: 启动新显示 (true/false)
 - display-width/width: 显示宽度
 - display-height/height: 显示高度
 - display-dpi/dpi: 显示 DPI
 - display-id: 显示器 ID (用于多显示器支持)
 - sync-iphone-orientation: 用 iPhone 的方向同步 Android 主屏幕 (true/false)
 
 VNC 参数：
 - vnc-user/user: VNC 用户名
 - vnc-password/password: VNC 密码
 
 自定义参数支持：
 - 任何未在上述列表中的参数都会被自动添加为 scrcpy 的自定义标志
 - 参数值为 "true" 或空值时，会被处理为布尔标志（如 --custom-flag）
 - 参数值为其他值时，会被处理为键值对标志（如 --custom-flag=value）
 - 例如：custom-option=123 会转换为 --custom-option=123
 */

// MARK: - Notification Names
extension Notification.Name {
    static let scrcpySchemeV2Received = Notification.Name("ScrcpySchemeV2Received")
}

// MARK: - Constants
private let ScrcpySchemeV2URLKey = "ScrcpySchemeV2URLKey"

class AppSchemeManagerV2: ObservableObject {
    static let shared = AppSchemeManagerV2()
    
    @Published var pendingScheme: URL?
    @Published var shouldShowConnectionAlert = false
    @Published var connectionMessage = ""
    
    // 使用 SessionConnectionManager 来管理连接状态
    private let connectionManager = SessionConnectionManager.shared
    
    private init() {
        // 监听应用变为活跃状态的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // 监听 scheme 通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrcpyURLScheme(_:)),
            name: .scrcpySchemeV2Received,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// 处理 URL scheme
    func handleURL(_ url: URL) -> Bool {
        guard url.scheme == "scrcpy2" else {
            print("❌ [AppSchemeManagerV2] Invalid URL scheme: \(url.scheme ?? "nil")")
            return false
        }
        
        print("✅ [AppSchemeManagerV2] Received URL: \(url)")
        
        // 发送通知
        NotificationCenter.default.post(
            name: .scrcpySchemeV2Received,
            object: nil,
            userInfo: [ScrcpySchemeV2URLKey: url]
        )
        
        return true
    }
    
    // MARK: - Private Methods
    
    @objc private func handleScrcpyURLScheme(_ notification: Notification) {
        guard let openingURL = notification.userInfo?[ScrcpySchemeV2URLKey] as? URL else {
            print("❌ [AppSchemeManagerV2] No URL found in notification")
            return
        }
        
        print("📱 [AppSchemeManagerV2] Handling URL Scheme: \(openingURL)")
        
        guard openingURL.scheme == "scrcpy2" else {
            print("❌ [AppSchemeManagerV2] Invalid URL Scheme: URL is not supported")
            return
        }
        
        self.pendingScheme = openingURL
        checkStartScheme()
    }
    
    @objc private func applicationDidBecomeActive() {
        // 当应用变为活跃状态时检查是否有待处理的 scheme
        checkStartScheme()
    }
    
    /// 检查并启动 scheme 连接
    private func checkStartScheme() {
        guard let pendingScheme = self.pendingScheme else {
            return
        }
        
        // 检查是否有活跃的窗口
        guard hasActiveWindow() else {
            return
        }
        
        let url = pendingScheme
        // 标记这里以避免前台通知和 viewAppear 触发两次
        self.pendingScheme = nil
        
        guard let hostOrSessionId = url.host, !hostOrSessionId.isEmpty else {
            print("❌ [AppSchemeManagerV2] No host or session ID found in scheme")
            showConnectionError("No host or session ID found in URL scheme")
            return
        }
        
        // 检查URL查询参数是否包含type=action
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)
        let queryItems = urlComponents?.queryItems ?? []
        let isActionType = queryItems.contains { $0.name == "type" && $0.value == "action" }
        
        if isActionType {
            // 处理 Action URL Scheme
            if let actionId = UUID(uuidString: hostOrSessionId) {
                print("🎬 [AppSchemeManagerV2] Processing action ID: \(actionId)")
                handleActionExecution(actionId: actionId)
            } else {
                print("❌ [AppSchemeManagerV2] Invalid action ID format: \(hostOrSessionId)")
                showConnectionError("Invalid action ID format. Action ID must be a valid UUID.\\n\\nReceived: \\(hostOrSessionId)\\n\\nExample: 550e8400-e29b-41d4-a716-446655440000")
            }
            return
        }
        
        // 尝试解析为 UUID (session ID)
        if let sessionId = UUID(uuidString: hostOrSessionId) {
            print("🔗 [AppSchemeManagerV2] Processing session ID: \(sessionId)")
            handleSessionIdConnection(sessionId: sessionId, url: url)
        } else {
            // 检查是否看起来像 UUID 但格式不正确
            if isLikelyInvalidUUID(hostOrSessionId) {
                print("❌ [AppSchemeManagerV2] Invalid UUID format: \(hostOrSessionId)")
                showConnectionError("Invalid session ID format. Session ID must be a valid UUID.\n\nReceived: \(hostOrSessionId)\n\nExample: 550e8400-e29b-41d4-a716-446655440000")
                return
            }
            
            // 传统的 host:port 方式
            let adbPort = url.port?.description ?? "5555"
            print("🔗 [AppSchemeManagerV2] Processing connection to \(hostOrSessionId):\(adbPort)")
            
            // 解析 URL 参数并创建会话
            let session = parseURLToSession(url: url, host: hostOrSessionId, port: adbPort)
            
            // 启动连接
            startConnection(with: session)
        }
    }
    
    /// 处理通过 session ID 启动连接
    private func handleSessionIdConnection(sessionId: UUID, url: URL) {
        // 从 SessionManager 读取会话配置
        guard let baseSession = SessionManager.shared.getSession(id: sessionId) else {
            print("❌ [AppSchemeManagerV2] Session not found for ID: \(sessionId)")
            
            // 获取所有可用的会话信息，用于更好的错误提示
            let availableSessions = SessionManager.shared.loadSessions()
            
            var errorMessage = "Session not found for ID: \(sessionId.uuidString)"
            
            if availableSessions.isEmpty {
                errorMessage += "\n\nNo sessions are currently saved. Please create a session first in the app."
            } else {
                errorMessage += "\n\nAvailable sessions (\(availableSessions.count)):"
                for session in availableSessions.prefix(3) {
                    let sessionName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
                    errorMessage += "\n• \(sessionName) (ID: \(session.id.uuidString))"
                }
                if availableSessions.count > 3 {
                    errorMessage += "\n• ... and \(availableSessions.count - 3) more"
                }
                errorMessage += "\n\nTip: You can copy the correct URL scheme from the session's context menu in the app."
            }
            
            showConnectionError(errorMessage)
            return
        }
        
        print("✅ [AppSchemeManagerV2] Found session: \(baseSession.sessionName)")
        handleSessionConnection(session: baseSession, url: url)
    }
    
    /// 处理通过会话配置启动连接
    private func handleSessionConnection(session: ScrcpySessionModel, url: URL) {
        print("✅ [AppSchemeManagerV2] Using session: \(session.sessionName)")
        
        // 使用会话配置作为基础，根据 URL 参数进行覆盖
        let customizedSession = applyURLParametersToSession(baseSession: session, url: url)
        
        // 启动连接
        startConnection(with: customizedSession)
    }
    
    /// 处理 Action 执行
    private func handleActionExecution(actionId: UUID) {
        print("🎬 [AppSchemeManagerV2] Looking for action with ID: \(actionId)")
        
        // 从 ActionManager 获取 action
        guard let action = ActionManager.shared.getActionBy(actionId) else {
            print("❌ [AppSchemeManagerV2] Action not found for ID: \(actionId)")
            showActionNotFoundError(actionId: actionId)
            return
        }
        
        print("✅ [AppSchemeManagerV2] Found action: \(action.name)")
        
        // 检查 action 是否有关联的设备
        guard let deviceId = action.deviceId else {
            print("❌ [AppSchemeManagerV2] Action has no associated device: \(action.name)")
            showConnectionError("Action '\(action.name)' has no associated device.")
            return
        }
        
        // 获取关联的会话
        guard let session = SessionManager.shared.getSession(id: deviceId) else {
            print("❌ [AppSchemeManagerV2] Session not found for device ID: \(deviceId)")
            showConnectionError("Session not found for action '\(action.name)'. The associated device may have been deleted.")
            return
        }
        
        print("🚀 [AppSchemeManagerV2] Executing action '\(action.name)' on session '\(session.sessionName)'")
        
        // 发送通知来执行 action
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("ExecuteActionFromScheme"),
                object: nil,
                userInfo: ["action": action, "session": session]
            )
        }
    }
    
    /// 将 URL 参数应用到已有会话配置中
    private func applyURLParametersToSession(baseSession: ScrcpySessionModel, url: URL) -> ScrcpySessionModel {
        var session = baseSession
        
        // 更新会话名称以表明这是通过 URL scheme 启动的
        session.sessionName = "\(baseSession.sessionName) (URL Override)"
        
        // 解析查询参数
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = urlComponents.queryItems else {
            print("📝 [AppSchemeManagerV2] No query parameters found, using original session configuration")
            return session
        }
        
        print("🔧 [AppSchemeManagerV2] Applying URL parameter overrides to session...")
        
        for queryItem in queryItems {
            let name = queryItem.name
            let value = queryItem.value
            
            print("🔧 [AppSchemeManagerV2] Overriding parameter: \(name) = \(value ?? "nil")")
            
            // 应用参数覆盖
            switch name {
            case "host":
                if let hostValue = value, !hostValue.isEmpty {
                    session.host = hostValue
                }
            case "port":
                if let portValue = value, !portValue.isEmpty {
                    session.port = portValue
                }
            case "session-name", "name":
                if let nameValue = value, !nameValue.isEmpty {
                    session.sessionName = nameValue
                }
            case "use-tailscale", "tailscale":
                session.useTailscale = value == "true"
            
            // ADB 相关参数
            case "max-size":
                session.adbOptions.maxScreenSize = value ?? ""
            case "video-bit-rate", "bit-rate":
                session.adbOptions.bitRate = value ?? ""
            case "max-fps":
                session.adbOptions.maxFPS = value ?? "60"
            case "video-codec":
                if let codecValue = value {
                    session.adbOptions.videoCodec = ADBVideoCodec(rawValue: codecValue) ?? session.adbOptions.videoCodec
                }
            case "video-encoder":
                session.adbOptions.videoEncoder = value ?? ""
            case "audio-codec":
                if let codecValue = value {
                    session.adbOptions.audioCodec = ADBAudioCodec(rawValue: codecValue) ?? session.adbOptions.audioCodec
                }
            case "audio-encoder":
                session.adbOptions.audioEncoder = value ?? ""
            case "enable-audio", "audio":
                session.adbOptions.enableAudio = value == "true"
            case "clipboard-sync":
                session.adbOptions.enableClipboardSync = value == "true"
            case "no-clipboard-autosync":
                session.adbOptions.enableClipboardSync = value != "true"
            case "turn-screen-off":
                session.adbOptions.turnScreenOff = value == "true"
            case "stay-awake":
                session.adbOptions.stayAwake = value == "true"
            case "power-off-on-close":
                session.adbOptions.powerOffOnClose = value == "true"
            case "sync-iphone-orientation":
                session.adbOptions.syncIPhoneOrientation = value == "true"
            case "force-adb-forward":
                session.adbOptions.forceAdbForward = value == "true"
            case "volume-scale":
                if let volumeValue = value, let volume = Double(volumeValue) {
                    session.adbOptions.volumeScale = volume
                }
            case "start-new-display", "new-display":
                session.adbOptions.startNewDisplay = value == "true"
            case "display-width", "width":
                if let widthValue = value, !widthValue.isEmpty {
                    session.adbOptions.displayWidth = widthValue
                }
            case "display-height", "height":
                if let heightValue = value, !heightValue.isEmpty {
                    session.adbOptions.displayHeight = heightValue
                }
            case "display-dpi", "dpi":
                if let dpiValue = value, !dpiValue.isEmpty {
                    session.adbOptions.displayDPI = dpiValue
                }
            
            // VNC 相关参数
            case "vnc-user", "user":
                if let userValue = value, !userValue.isEmpty {
                    session.vncOptions.vncUser = userValue
                }
            case "vnc-password", "password":
                if let passwordValue = value, !passwordValue.isEmpty {
                    session.vncOptions.vncPassword = passwordValue
                }
            
            default:
                // 存储未知参数到 customFlags 中
                print("🔧 [AppSchemeManagerV2] Storing unknown parameter in customFlags: \(name) = \(value ?? "nil")")
                if let value = value {
                    session.adbOptions.customFlags[name] = value
                }
                break
            }
        }
        
        print("📋 [AppSchemeManagerV2] Customized session: \(session)")
        
        return session
    }
    
    /// 检查是否有活跃的窗口
    private func hasActiveWindow() -> Bool {
        if #available(iOS 13.0, *) {
            // iOS 13+ 使用 scene 方式
            let activeScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return activeScenes.contains { $0.activationState == .foregroundActive }
        } else {
            // iOS 12 及以下使用传统方式
            return UIApplication.shared.windows.contains { $0.isKeyWindow }
        }
    }
    
    /// 解析 URL 为会话模型
    private func parseURLToSession(url: URL, host: String, port: String) -> ScrcpySessionModel {
        var session = ScrcpySessionModel()
        session.host = host
        session.port = port
        session.sessionName = "URL Scheme - \(host)"
        
        // 解析查询参数
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = urlComponents.queryItems else {
            print("📝 [AppSchemeManagerV2] No query parameters found")
            return session
        }
        
        var scrcpyOptions = getDefaultScrcpyOptions()
        
        for queryItem in queryItems {
            let name = queryItem.name
            let value = queryItem.value
            
            print("🔧 [AppSchemeManagerV2] Processing parameter: \(name) = \(value ?? "nil")")
            
            // 如果 value == "true"，设置 value 为 "" 以匹配命令行样式的 scrcpy 选项，如 --turn-screen-off
            let processedValue = (value == "true") ? "" : value
            
            // Client-side orientation sync must not become a scrcpy CLI flag.
            if name != "sync-iphone-orientation" {
                scrcpyOptions = setScrcpyOption(scrcpyOptions, name: name, value: processedValue)
            }
            
            // 处理特殊参数
            switch name {
            case "max-size":
                session.adbOptions.maxScreenSize = value ?? ""
            case "video-bit-rate", "bit-rate":
                session.adbOptions.bitRate = value ?? ""
            case "max-fps":
                session.adbOptions.maxFPS = value ?? "60"
            case "video-codec":
                if let codecValue = value {
                    session.adbOptions.videoCodec = ADBVideoCodec(rawValue: codecValue) ?? .h264
                }
            case "video-encoder":
                session.adbOptions.videoEncoder = value ?? ""
            case "audio-codec":
                if let codecValue = value {
                    session.adbOptions.audioCodec = ADBAudioCodec(rawValue: codecValue) ?? .opus
                }
            case "audio-encoder":
                session.adbOptions.audioEncoder = value ?? ""
            case "enable-audio", "audio":
                session.adbOptions.enableAudio = value == "true"
            case "no-clipboard-autosync":
                session.adbOptions.enableClipboardSync = value != "true"
            case "turn-screen-off":
                session.adbOptions.turnScreenOff = value == "true"
            case "stay-awake":
                session.adbOptions.stayAwake = value == "true"
            case "power-off-on-close":
                session.adbOptions.powerOffOnClose = value == "true"
            case "sync-iphone-orientation":
                session.adbOptions.syncIPhoneOrientation = value == "true"
            case "force-adb-forward":
                session.adbOptions.forceAdbForward = value == "true"
            case "volume-scale":
                if let volumeValue = value, let volume = Double(volumeValue) {
                    session.adbOptions.volumeScale = volume
                }
            default:
                // 存储未知参数到 customFlags 中
                print("🔧 [AppSchemeManagerV2] Storing unknown parameter in customFlags: \(name) = \(value ?? "nil")")
                if let value = value {
                    session.adbOptions.customFlags[name] = value
                }
                break
            }
        }
        
        // 应用自定义标志到 scrcpy 选项
        scrcpyOptions = applyCustomFlagsToOptions(scrcpyOptions, customFlags: session.adbOptions.customFlags)
        
        print("📋 [AppSchemeManagerV2] Parsed session: \(session)")
        print("⚙️ [AppSchemeManagerV2] Scrcpy options: \(scrcpyOptions)")
        print("🔧 [AppSchemeManagerV2] Custom flags: \(session.adbOptions.customFlags)")
        
        return session
    }
    
    /// 获取默认的 scrcpy 选项
    private func getDefaultScrcpyOptions() -> [String: Any] {
        return [
            "--fullscreen": true,
            "--video-codec": "h264",
            "--video-buffer": "0",
            "--audio-buffer": "150",
            "--print-fps": true,
            "--video-bit-rate": "4M",
            "--audio-output-buffer": "10",
            "--shortcut-mod": "lctrl,rctrl,lalt,ralt"
        ]
    }
    
    /// 设置 scrcpy 选项
    private func setScrcpyOption(_ options: [String: Any], name: String, value: String?) -> [String: Any] {
        var newOptions = options
        
        // 参数名映射
        let parameterMapping: [String: String] = [
            "max-size": "--max-size",
            "video-bit-rate": "--video-bit-rate",
            "bit-rate": "--video-bit-rate",
            "max-fps": "--max-fps",
            "video-codec": "--video-codec",
            "video-encoder": "--video-encoder",
            "audio-codec": "--audio-codec",
            "audio-encoder": "--audio-encoder",
            "video-buffer": "--video-buffer",
            "audio-buffer": "--audio-buffer",
            "display-id": "--display-id",
            "turn-screen-off": "--turn-screen-off",
            "stay-awake": "--stay-awake",
            "show-touches": "--show-touches",
            "disable-screensaver": "--disable-screensaver",
            "power-off-on-close": "--power-off-on-close",
            "no-audio": "--no-audio",
            "no-clipboard-autosync": "--no-clipboard-autosync"
        ]
        
        // 布尔参数映射（这些参数如果值为 true 则只添加参数名，不添加值）
        let booleanParameters: Set<String> = [
            "turn-screen-off", "stay-awake", "show-touches", 
            "disable-screensaver", "power-off-on-close", "no-audio", "no-clipboard-autosync"
        ]
        
        if let mappedName = parameterMapping[name] {
            if booleanParameters.contains(name) {
                // 布尔参数
                if value == "" || value == "true" {
                    newOptions[mappedName] = true
                }
            } else {
                // 值参数
                if let value = value, !value.isEmpty {
                    newOptions[mappedName] = value
                }
            }
        } else {
            // 处理未知参数，自动添加 "--" 前缀
            let customFlagName = name.hasPrefix("--") ? name : "--\(name)"
            if let value = value, !value.isEmpty {
                if value == "true" || value == "" {
                    // 布尔类型的自定义标志
                    newOptions[customFlagName] = true
                } else {
                    // 有值的自定义标志
                    newOptions[customFlagName] = value
                }
            }
        }
        
        return newOptions
    }
    
    /// 将 customFlags 应用到 scrcpy 选项
    private func applyCustomFlagsToOptions(_ options: [String: Any], customFlags: [String: String]) -> [String: Any] {
        var newOptions = options
        
        for (flagName, flagValue) in customFlags {
            let scrcpyFlagName = flagName.hasPrefix("--") ? flagName : "--\(flagName)"
            
            if flagValue == "true" || flagValue.isEmpty {
                // 布尔标志
                newOptions[scrcpyFlagName] = true
            } else if flagValue == "false" {
                // 显式设为 false 的标志不添加
                continue
            } else {
                // 有值的标志
                newOptions[scrcpyFlagName] = flagValue
            }
        }
        
        return newOptions
    }
    
    /// Forward each URL launch to the same connection lifecycle used by the
    /// Sessions screen. A repeated URL is an explicit request to reconnect,
    /// even when it targets the current device. Do not pre-disconnect or set
    /// currentSession here: connectToSession() owns both operations and waits
    /// for rotation restoration before starting the next connection.
    private func startConnection(with session: ScrcpySessionModel) {
        print("🚀 [AppSchemeManagerV2] Starting connection with session: \(session.sessionName)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .startSchemeConnection,
                object: nil,
                userInfo: ["session": session]
            )
        }
    }
    
    /// 显示连接错误
    private func showConnectionError(_ message: String) {
        DispatchQueue.main.async {
            self.connectionMessage = "连接错误: \(message)"
            self.shouldShowConnectionAlert = true
        }
    }
    
    /// 显示 Action 未找到错误
    private func showActionNotFoundError(actionId: UUID) {
        // 获取所有可用的 Actions 信息，用于更好的错误提示
        let availableActions = ActionManager.shared.actions
        
        var errorMessage = "Action not found for ID: \(actionId.uuidString)"
        
        if availableActions.isEmpty {
            errorMessage += "\n\nNo actions are currently saved. Please create an action first in the app."
        } else {
            errorMessage += "\n\nAvailable actions (\(availableActions.count)):"
            for action in availableActions.prefix(3) {
                errorMessage += "\n• \(action.name) (ID: \(action.id.uuidString))"
            }
            if availableActions.count > 3 {
                errorMessage += "\n• ... and \(availableActions.count - 3) more"
            }
            errorMessage += "\n\nTip: You can copy the correct URL scheme from the action's context menu in the app."
        }
        
        DispatchQueue.main.async {
            self.connectionMessage = errorMessage
            self.shouldShowConnectionAlert = true
        }
    }
    
    /// 检查是否看起来像 UUID 但格式不正确
    private func isLikelyInvalidUUID(_ string: String) -> Bool {
        // 如果字符串长度接近 UUID 长度 (36字符) 或包含典型的 UUID 字符但格式不对
        let cleanString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查长度是否接近 UUID (32-40 字符范围)
        if cleanString.count >= 32 && cleanString.count <= 40 {
            // 检查是否主要包含十六进制字符和连字符
            let hexAndDashPattern = "^[0-9a-fA-F-]+$"
            let regex = try! NSRegularExpression(pattern: hexAndDashPattern)
            let range = NSRange(location: 0, length: cleanString.utf16.count)
            
            if regex.firstMatch(in: cleanString, range: range) != nil {
                // 看起来像 UUID 但格式不正确
                return true
            }
        }
        
        // 检查是否包含连字符且长度较长（可能是格式错误的 UUID）
        if cleanString.contains("-") && cleanString.count >= 20 {
            return true
        }
        
        return false
    }
    
    // MARK: - Public Utility Methods
    
    /// 获取当前连接状态信息
    func getCurrentConnectionStatus() -> String {
        return connectionManager.connectionDescription + " - " + connectionManager.statusDescription
    }
    
    /// 检查是否有活跃连接
    var hasActiveConnection: Bool {
        return connectionManager.connectionStatus.isActive
    }
}

// MARK: - Extensions for SessionsView Integration

extension Notification.Name {
    static let startSchemeConnection = Notification.Name("StartSchemeConnection")
    static let executeActionFromScheme = Notification.Name("ExecuteActionFromScheme")
} 
