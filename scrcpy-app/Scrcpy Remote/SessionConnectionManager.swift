//
//  SessionConnectionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//
//  断开连接处理逻辑：
//  - 所有断开连接都静默处理，不显示给用户
//  - 只记录日志用于调试
//
//  架构优化 (2025-01-01)：
//  - Action 执行逻辑已重构，通过 ScrcpyClientWrapper 进行任务透传
//  - VNC Actions 通过 ScrcpyClientWrapper.executeVNCActions 执行，确保上下文一致性
//  - ADB Actions 通过 ScrcpyClientWrapper.executeADB* 方法执行，支持设备序列号精确定位
//  - 避免使用单例 (shared instances)，防止异常情况和不必要的单例创建
//  - SessionConnectionManager 专注于连接管理和协调，所有执行任务通过 clientWrapper 透传
//  - 提高了代码的可维护性、可测试性和架构一致性

import Foundation
import UIKit
import ActivityKit

// MARK: - VNCQuickAction Extension

extension VNCQuickAction {
    /// 将 Swift 的 VNCQuickAction 枚举转换为 Objective-C 的 VNCQuickActionType
    /// - Returns: 对应的 VNCQuickActionType 原始值
    func toVNCQuickActionType() -> Int {
        switch self {
        case .inputKeys:
            return 0 // VNCQuickActionTypeInputKeys
        case .syncClipboard:
            return 1 // VNCQuickActionTypeSyncClipboard
        }
    }
}

// MARK: - VNCKeyModifier Extension

extension VNCKeyModifier {
    /// 将 VNC 键修饰符转换为对应的键码
    /// - Returns: VNC 键修饰符对应的键码
    func toVNCKeyCode() -> Int {
        switch self {
        case .ctrl:
            return 65507  // XK_Control_L (左 Ctrl)
        case .alt:
            return 65513  // XK_Alt_L (左 Alt)
        case .shift:
            return 65505  // XK_Shift_L (左 Shift)
        case .cmd:
            return 65515  // XK_Super_L (左 Super/Cmd)
        }
    }
}

// MARK: - Connection Callback Types

/// 连接状态回调闭包类型
/// - Parameters:
///   - status: 连接状态
///   - message: 状态消息
///   - isConnecting: 是否正在连接中
typealias ConnectionStatusCallback = (ScrcpyStatus, String?, Bool) -> Void

/// 连接错误回调闭包类型
/// - Parameters:
///   - title: 错误标题
///   - message: 错误消息
typealias ConnectionErrorCallback = (String, String) -> Void

/// Action 确认回调闭包类型
/// - Parameters:
///   - action: 需要确认的动作
///   - confirmCallback: 确认后的回调
typealias ActionConfirmationCallback = (ScrcpyAction, @escaping () -> Void) -> Void

/// 管理当前连接会话的状态
@objc class SessionConnectionManager: NSObject, ObservableObject {
    @objc static let shared = SessionConnectionManager()
    
    // MARK: - Connection State
    
    /// 当前连接的会话信息
    @objc @Published var currentSession: ScrcpySessionModel?
    
    /// 正在连接中的会话信息（用于在等待当前连接断开时临时保存）
    @Published var connectingSession: ScrcpySessionModel?
    
    /// 当前连接状态
    @Published var connectionStatus: ScrcpyStatus = ScrcpyStatusDisconnected
    
    /// 实际连接的主机地址（解析后的，可能通过 Tailscale 代理）
    @Published var actualHost: String?
    
    /// 实际连接的端口（解析后的，可能通过 Tailscale 代理）
    @Published var actualPort: String?
    
    /// 是否使用 Tailscale 连接
    @Published var isUsingTailscale: Bool = false
    
    /// Tailscale 本地转发端口（如果使用）
    @Published var tailscaleLocalPort: Int?
    
    /// 是否正在连接中
    @Published var isConnecting: Bool = false
    
    /// 当前连接的开始时间
    @Published var connectionStartTime: Date?
    
    // MARK: - Private Properties
    
    /// 当前连接的回调闭包
    private var currentConnectionCallback: ConnectionStatusCallback?
    
    /// 当前错误回调闭包
    private var currentErrorCallback: ConnectionErrorCallback?
    
    /// 当前 Action 确认回调闭包
    private var currentActionConfirmationCallback: ActionConfirmationCallback?
    
    /// 当前等待确认的动作和回调
    private var pendingConfirmationAction: ScrcpyAction?
    private var pendingConfirmationCallback: (() -> Void)?
    
    /// Scrcpy 客户端包装器实例，用于直接管理连接
    private var scrcpyClientWrapper: ScrcpyClientWrapper?

    // Invalidates asynchronous cleanup from a previous connection, even if
    // the same saved session is reconnected before cleanup finishes.
    private var connectionInstanceID = UUID()
    
    /// 后台断开连接计时器
    private var backgroundDisconnectTimer: Timer?

    /// Live Activity 管理器
    private lazy var liveActivityManager: Any? = {
        if #available(iOS 16.1, *) {
            return ScrcpyLiveActivityManager.shared
        } else {
            return nil
        }
    }()

    /// 用于存储上次连接会话的 UserDefaults key
    private let lastSessionKey = "session_connection_manager.last_session"
    
    override private init() {
        super.init()
        setupNotificationObservers()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // 监听 scrcpy 状态更新
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrcpyStatusUpdate(_:)),
            name: Notification.Name("ScrcpyStatusUpdated"),
            object: nil
        )
        
        // 监听应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 监听应用即将进入前台（比 didBecomeActive 更早），尽早清除后台标志
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // 监听应用变为活跃
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleApplicationWillEnterForeground() {
        // Earliest foreground signal — clear the background flag right away.
        SetApplicationBackgroundState(false)
    }
    
    @objc private func handleScrcpyStatusUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let statusValue = userInfo["status"] as? Int else {
            print("⚠️ [SessionConnectionManager] Invalid notification: \(notification)")
            return
        }
        
        let statusMessage = userInfo["message"] as? String
        print("🔔 [SessionConnectionManager] Received status update: \(statusValue) from notification")
        
        DispatchQueue.main.async {
            let newStatus = ScrcpyStatus(UInt32(statusValue))
            self.connectionStatus = newStatus
            
            switch newStatus {
            case ScrcpyStatusConnecting:
                print("🔄 [SessionConnectionManager] Status: Connecting")
                self.isConnecting = true
                
            case ScrcpyStatusSDLWindowAppeared:
                print("✅ [SessionConnectionManager] Status: SDL Window Appeared")
                self.isConnecting = false

                // 记录连接开始时间
                if self.connectionStartTime == nil {
                    self.connectionStartTime = Date()
                    print("⏰ [SessionConnectionManager] Connection start time recorded: \(self.connectionStartTime!)")
                }

                // 启用后台保活的静音音频（在 SDL audio session 起来之后,
                // 我们用 .playback + .mixWithOthers 覆盖,与 scrcpy/VNC 音频共存）。
                BackgroundKeepAliveManager.shared.sessionConnected()
                self.startIPhoneOrientationSyncIfNeeded()

                // 连接成功后,如果启用了自动重连,保存当前会话
                self.saveCurrentSessionIfAutoReconnectEnabled()

                // 执行待执行的动作
                self.executePendingActionIfNeeded()

                // 连接成功后，延迟清理回调以避免 ConnectionStatusView 在后台运行
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.cleanupCallbacksAfterSuccess()
                }

            case ScrcpyStatusSDLWindowCreated:
                print("✅ [SessionConnectionManager] Status: SDL Window Created")
                self.isConnecting = false

                // 记录连接开始时间
                if self.connectionStartTime == nil {
                    self.connectionStartTime = Date()
                    print("⏰ [SessionConnectionManager] Connection start time recorded: \(self.connectionStartTime!)")
                }

                BackgroundKeepAliveManager.shared.sessionConnected()
                self.startIPhoneOrientationSyncIfNeeded()

                // 连接成功后,如果启用了自动重连,保存当前会话
                self.saveCurrentSessionIfAutoReconnectEnabled()

                // 延迟执行待执行的动作，确保界面完全显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    print("⏰ [SessionConnectionManager] Window created delay completed, executing pending action")
                    self.executePendingActionIfNeeded()
                }

                // 连接成功后，延迟清理回调以避免 ConnectionStatusView 在后台运行
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.cleanupCallbacksAfterSuccess()
                }
                
            case ScrcpyStatusConnected:
                self.startIPhoneOrientationSyncIfNeeded()

            case ScrcpyStatusDisconnected:
                print("❌ [SessionConnectionManager] Status: Disconnected - clearing session")
                if let disconnectMessage = statusMessage, !disconnectMessage.isEmpty {
                    print("ℹ️ [SessionConnectionManager] Disconnect message: \(disconnectMessage)")
                }
                
                // Check for ERROR in the last output and show alert if found
                self.checkForErrorsAndShowAlert()
                
                self.isConnecting = false
                // 如果正在执行带 action 的连接，不清除 pendingAction
                self.clearCurrentSession(clearPendingAction: !self.isConnectingWithAction)
                
            case ScrcpyStatusConnectingFailed:
                print("❌ [SessionConnectionManager] Status: Connection Failed")
                self.isConnecting = false
                
                // 错误信息现在通过状态回调传递到 ConnectionStatusView，不再调用错误回调
                if let errorMessage = statusMessage, !errorMessage.isEmpty {
                    print("📝 [SessionConnectionManager] Error message: \(errorMessage)")
                } else {
                    print("📝 [SessionConnectionManager] No specific error message, using default")
                }
                
                // 连接失败后，不自动清理，等待用户主动 dismiss
                // 只清理回调以避免重复调用
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.cleanupCallbacksAfterFailure()
                }
                
            default:
                print("🔄 [SessionConnectionManager] Status update: \(statusValue)")
            }
            
            // 调用状态回调
            if let callback = self.currentConnectionCallback {
                callback(newStatus, statusMessage, self.isConnecting)
            }
            
            // 更新 Live Activity
            self.updateLiveActivityIfNeeded(status: newStatus, message: statusMessage)
        }
    }
    
    @objc private func handleApplicationDidEnterBackground() {
        // Set the background flag synchronously, before anything else. The
        // VideoToolbox decode session dies the instant we background, and the
        // decoder thread can hit avcodec_receive_frame's error path within a
        // few ms. BackgroundKeepAlive.evaluate() also sets this, but it runs
        // async via Combine (.receive(on:)) — too late. This direct @objc
        // observer fires synchronously when iOS posts the notification.
        SetApplicationBackgroundState(true)

        print("📱 [SessionConnectionManager] ========================================")
        print("📱 [SessionConnectionManager] Application did enter background")
        print("📱 [SessionConnectionManager] ========================================")

        // 打印当前连接状态
        print("📊 [SessionConnectionManager] Current connection status:")
        print("   - Connection status: \(connectionStatus.description)")
        print("   - Is active: \(connectionStatus.isActive)")
        print("   - Is connecting: \(isConnecting)")
        print("   - Current session: \(currentSession?.sessionName ?? "nil")")

        // 如果启用了自动重连并且当前有活跃连接，保存当前会话
        let autoReconnectEnabled = UserDefaults.standard.bool(forKey: "settings.auto_reconnect.enabled")
        print("⚙️ [SessionConnectionManager] Auto reconnect enabled: \(autoReconnectEnabled)")

        if autoReconnectEnabled && connectionStatus.isActive, let session = currentSession {
            print("💾 [SessionConnectionManager] Re-saving current session on background...")
            print("   - Session name: \(session.sessionName)")
            print("   - Session host: \(session.hostReal)")
            print("   - Session port: \(session.port)")
            print("   - Device type: \(session.deviceType.rawValue)")
            saveLastSession(session)
            print("✅ [SessionConnectionManager] Session re-saved on background (backup)")
        } else {
            if !autoReconnectEnabled {
                print("⏭️ [SessionConnectionManager] Auto reconnect is disabled, skipping session save")
            } else if !connectionStatus.isActive {
                print("⏭️ [SessionConnectionManager] No active connection, skipping session save")
            } else {
                print("⏭️ [SessionConnectionManager] No current session, skipping session save")
            }
        }

        // 如果当前有活跃连接，启动 Live Activity
        startLiveActivityIfNeeded()

        // 若无活跃连接但仍存在旧的 Live Activity，则停止它，避免卡住
        if #available(iOS 16.1, *),
           let manager = liveActivityManager as? ScrcpyLiveActivityManager,
           manager.hasActiveActivity,
           !connectionStatus.isActive {
            print("🧹 [SessionConnectionManager] No active connection; stopping stale Live Activity in background")
            manager.stopActivity()
        }

        // 启动后台断开计时器
        startBackgroundDisconnectTimer()

        print("📱 [SessionConnectionManager] ========================================")
        print("📱 [SessionConnectionManager] Background handling completed")
        print("📱 [SessionConnectionManager] ========================================")
    }

    @objc private func handleApplicationDidBecomeActive() {
        // Clear the background flag synchronously and as early as possible, so
        // a genuine decode error right after foregrounding is not wrongly
        // suppressed as a background VT-session loss.
        SetApplicationBackgroundState(false)

        print("📱 [SessionConnectionManager] ========================================")
        print("📱 [SessionConnectionManager] Application did become active")
        print("📱 [SessionConnectionManager] ========================================")

        // 打印当前连接状态
        print("📊 [SessionConnectionManager] Current connection status:")
        print("   - Connection status: \(connectionStatus.description)")
        print("   - Is active: \(connectionStatus.isActive)")
        print("   - Is connecting: \(isConnecting)")
        print("   - Current session: \(currentSession?.sessionName ?? "nil")")

        // 取消后台断开计时器
        stopBackgroundDisconnectTimer()

        // Re-sync if the iPhone rotated while this app was in the background.
        if connectionStatus.isFullyConnected {
            IPhoneOrientationSync.shared.resume()
        }

        // 检查是否需要自动重连
        print("🔍 [SessionConnectionManager] Checking if auto reconnect is needed...")
        attemptAutoReconnectIfNeeded()

        print("📱 [SessionConnectionManager] ========================================")
        print("📱 [SessionConnectionManager] Foreground handling completed")
        print("📱 [SessionConnectionManager] ========================================")
    }

    // MARK: - Background Task Management

    private func startBackgroundDisconnectTimer() {
        guard connectionStatus.isActive, backgroundDisconnectTimer == nil else {
            return
        }

        let duration = AppSettings().backgroundActiveDuration
        guard let timeInterval = duration.seconds else {
            print("后台保持连接设置为永久，不启动断开计时器")
            return
        }

        print("Start the background disconnection timer, will disconnect after \(duration.rawValue)")

        backgroundDisconnectTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            print("后台时间到，断开连接")
            self?.disconnectCurrent()
        }
    }

    private func stopBackgroundDisconnectTimer() {
        if backgroundDisconnectTimer != nil {
            print("取消后台断开计时器")
            backgroundDisconnectTimer?.invalidate()
            backgroundDisconnectTimer = nil
        }
    }
    
    // MARK: - Connection Management
    
    /// 当前要执行的动作
    private var pendingAction: ScrcpyAction?
    
    /// 是否正在执行带 action 的连接（防止在重连过程中清除 pendingAction）
    private var isConnectingWithAction: Bool = false
    
    /// 是否已经执行过 pendingAction（防止重复执行）
    private var hasExecutedPendingAction: Bool = false
    
    /// 连接到指定会话
    /// - Parameters:
    ///   - session: 要连接的会话模型
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    func connectToSession(
        _ session: ScrcpySessionModel,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback
    ) {
        print("🚀 [SessionConnectionManager] Starting connection to session: \(session.sessionName)")
        
        // 保存将要连接的会话信息
        connectingSession = session
        
        // 保存回调闭包
        currentConnectionCallback = statusCallback
        currentErrorCallback = errorCallback
        
        // 如果当前状态不是 Disconnected，先断开现有连接
        if connectionStatus != ScrcpyStatusDisconnected {
            print("🔄 [SessionConnectionManager] Current status is \(connectionStatus.description), disconnecting first")
            disconnectCurrent { [weak self] in
                // Only reconnect once Android's previous rotation is restored
                // and the previous ADB client has started shutting down.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let self = self else { return }
                    // Disconnect cleanup clears callbacks. Install the new
                    // session's callbacks only after that cleanup has finished.
                    self.connectingSession = session
                    self.currentConnectionCallback = statusCallback
                    self.currentErrorCallback = errorCallback
                    self.performConnection(to: session, statusCallback: statusCallback, errorCallback: errorCallback)
                }
            }
        } else {
            // 直接开始连接
            performConnection(to: session, statusCallback: statusCallback, errorCallback: errorCallback)
        }
    }
    
    /// 连接到指定会话并执行动作
    /// - Parameters:
    ///   - session: 要连接的会话模型
    ///   - action: 要执行的动作
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    ///   - actionConfirmationCallback: Action 确认回调（可选）
    @objc func connectToSessionWithAction(
        _ session: ScrcpySessionModel,
        action: ScrcpyAction,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback,
        actionConfirmationCallback: ActionConfirmationCallback? = nil
    ) {
        print("🚀 [SessionConnectionManager] Starting connection with action: \(action.name) to session: \(session.sessionName)")
        print("📝 [SessionConnectionManager] Action details - Type: \(action.deviceType), Timing: \(action.executionTiming)")
        
        // 设置标志和保存要执行的动作
        isConnectingWithAction = true
        hasExecutedPendingAction = false
        pendingAction = action
        currentActionConfirmationCallback = actionConfirmationCallback
        print("💾 [SessionConnectionManager] Pending action saved: \(action.name)")
        
        // 调用原有的连接方法
        connectToSession(session, statusCallback: statusCallback, errorCallback: errorCallback)
    }
    
    /// 在当前会话上直接执行动作，不需要重新连接
    /// - Parameters:
    ///   - action: 要执行的动作
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    ///   - actionConfirmationCallback: Action 确认回调（可选）
    @objc func executeActionOnCurrentSession(
        _ action: ScrcpyAction,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback,
        actionConfirmationCallback: ActionConfirmationCallback? = nil
    ) {
        print("🎯 [SessionConnectionManager] Executing action on current session: \(action.name)")
        
        guard let currentSession = currentSession else {
            print("❌ [SessionConnectionManager] Cannot execute action: no current session")
            errorCallback("No Active Session", "No active session found. Please connect to a device first.")
            return
        }
        
        guard connectionStatus.isActive else {
            print("❌ [SessionConnectionManager] Cannot execute action: session not active (status: \(connectionStatus))")
            errorCallback("Session Not Active", "Current session is not active. Please ensure the connection is established.")
            return
        }
        
        print("✅ [SessionConnectionManager] Current session is connected, executing action immediately")
        statusCallback(ScrcpyStatusConnected, "Executing action on current session", false)
        
        // 根据动作的执行时机决定如何执行
        switch action.executionTiming {
        case .immediate:
            print("⚡ [SessionConnectionManager] Executing action immediately on current session")
            executeAction(action)
            statusCallback(ScrcpyStatusConnected, "Action executed successfully", false)
        case .delayed:
            print("⏰ [SessionConnectionManager] Executing action after \(action.delaySeconds) seconds delay on current session")
            statusCallback(ScrcpyStatusConnected, "Action will execute in \(action.delaySeconds) seconds", false)
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(action.delaySeconds)) {
                self.executeAction(action)
                statusCallback(ScrcpyStatusConnected, "Action executed successfully", false)
            }
        case .confirmation:
            print("❓ [SessionConnectionManager] Action requires confirmation on current session")
            if let confirmationCallback = actionConfirmationCallback {
                confirmationCallback(action) { [weak self] in
                    print("✅ [SessionConnectionManager] User confirmed action, executing on current session")
                    self?.executeAction(action)
                    statusCallback(ScrcpyStatusConnected, "Action executed successfully", false)
                }
            } else {
                print("⚠️ [SessionConnectionManager] No confirmation callback, executing directly on current session")
                executeAction(action)
                statusCallback(ScrcpyStatusConnected, "Action executed successfully", false)
            }
        }
    }
    
    /// 执行实际的连接逻辑
    /// - Parameters:
    ///   - session: 要连接的会话模型
    ///   - statusCallback: 连接状态回调
    ///   - errorCallback: 错误回调
    private func performConnection(
        to session: ScrcpySessionModel,
        statusCallback: @escaping ConnectionStatusCallback,
        errorCallback: @escaping ConnectionErrorCallback
    ) {
        print("🔗 [SessionConnectionManager] Performing connection to session: \(session.sessionName)")

        isConnecting = true
        statusCallback(ScrcpyStatusConnecting, "Preparing connection...", true)

        // Hook up SessionNetworking status callback for Tailscale/OAuth status updates
        SessionNetworking.shared.statusUpdateCallback = { [weak self] message in
            DispatchQueue.main.async {
                print("📡 [SessionConnectionManager] Network status: \(message)")
                statusCallback(ScrcpyStatusConnecting, message, true)
            }
        }

        Task {
            do {
                var connectionInfo = await SessionNetworking.shared.getConnectionInfo(for: session)
                
                // 如果是 Tailscale 连接且首次获取信息失败，则重试一次
                // 仅当 Tailscale 本身拨号失败（无法获取 IP）时重试
                if connectionInfo == nil && session.useTailscale {
                    print("⚠️ [SessionConnectionManager] Failed to get Tailscale connection info, retrying once...")
                    
                    // 停止当前转发并等待
                    _ = SessionNetworking.shared.stopForwarding(for: session.id)
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                    
                    // 再次尝试获取连接信息
                    connectionInfo = await SessionNetworking.shared.getConnectionInfo(for: session)
                }
                
                guard let finalConnectionInfo = connectionInfo else {
                    await MainActor.run {
                        // Clear the status callback on error
                        SessionNetworking.shared.statusUpdateCallback = nil
                        self.handleConnectionError(
                            title: "Connection Setup Failed",
                            message: "Failed to setup connection. Please check your network configuration and try again.",
                            errorCallback: errorCallback
                        )
                    }
                    return
                }
                
                print("📍 [SessionConnectionManager] Connection info obtained: \(finalConnectionInfo.description)")
                
                await MainActor.run {
                    self.setCurrentSession(session, connectionInfo: finalConnectionInfo)
                    
                    var sessionDict = session.toDict()
                    sessionDict["hostReal"] = finalConnectionInfo.host
                    sessionDict["port"] = finalConnectionInfo.port
                    
                    if finalConnectionInfo.isUsingTailscale {
                        // Carry the real remote target through so a failed local
                        // forward can produce a Tailscale-aware error instead of
                        // the misleading "accept the adb authorization" tip.
                        sessionDict["isUsingTailscale"] = true
                        sessionDict["tailscaleRemoteHost"] = finalConnectionInfo.originalHost
                        sessionDict["tailscaleRemotePort"] = finalConnectionInfo.originalPort
                        print("🔗 [SessionConnectionManager] Using Tailscale connection: \(finalConnectionInfo.originalHost):\(finalConnectionInfo.originalPort) -> \(finalConnectionInfo.host):\(finalConnectionInfo.port)")
                    } else {
                        sessionDict["host"] = finalConnectionInfo.host
                        print("🔌 [SessionConnectionManager] Using direct connection: \(finalConnectionInfo.host):\(finalConnectionInfo.port)")
                    }

                    // Clear the status callback as we're done with network setup
                    SessionNetworking.shared.statusUpdateCallback = nil

                    self.startScrcpyConnection(sessionDict: sessionDict, connectionInfo: finalConnectionInfo)
                }
                
            } catch {
                await MainActor.run {
                    // Clear the status callback on error
                    SessionNetworking.shared.statusUpdateCallback = nil
                    self.handleConnectionError(
                        title: "Connection Error",
                        message: "Failed to establish connection: \(error.localizedDescription)",
                        errorCallback: errorCallback
                    )
                }
            }
        }
    }
    
    /// 开始 Scrcpy 连接
    /// - Parameters:
    ///   - sessionDict: 会话字典
    ///   - connectionInfo: 连接信息
    private func startScrcpyConnection(sessionDict: [String: Any], connectionInfo: NetworkConnectionInfo) {
        print("🔗 [SessionConnectionManager] Starting Scrcpy client connection")
        
        // 创建或获取 ScrcpyClientWrapper 实例
        if scrcpyClientWrapper == nil {
            scrcpyClientWrapper = ScrcpyClientWrapper()
        }
        
        scrcpyClientWrapper?.startClient(sessionDict) { [weak self] statusCode, message in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch statusCode.rawValue {
                case ScrcpyStatusSDLWindowAppeared.rawValue:
                    print("✅ [SessionConnectionManager] Successfully connected to session")
                    
                case ScrcpyStatusConnectingFailed.rawValue:
                    print("❌ [SessionConnectionManager] Failed to connect to session")
                    // 重试逻辑已移至 performConnection，这里不再处理。
                    // 如果 Tailscale 已经成功分配 IP，但连接失败，通常是目标设备服务未运行或防火墙问题。
                    if connectionInfo.isUsingTailscale {
                        print("ℹ️ [SessionConnectionManager] Tailscale connection failed. This may be due to the target service not running or a network issue. No further retries will be attempted.")
                    }
                    
                default:
                    print("🔄 [SessionConnectionManager] Connection status: \(statusCode.description)")
                    if !message.isEmpty {
                        print("📝 [SessionConnectionManager] Status message: \(message)")
                    }
                }
            }
        }
    }
    
    /// 处理连接错误
    /// - Parameters:
    ///   - title: 错误标题
    ///   - message: 错误消息
    ///   - errorCallback: 错误回调（现在不再使用）
    private func handleConnectionError(title: String, message: String, errorCallback: ConnectionErrorCallback) {
        print("❌ [SessionConnectionManager] Connection error: \(title) - \(message)")
        
        isConnecting = false
        connectionStatus = ScrcpyStatusConnectingFailed
        
        // 清除连接中的会话信息，因为连接失败了
        connectingSession = nil
        
        // 通过状态回调传递错误信息到 ConnectionStatusView
        if let callback = currentConnectionCallback {
            callback(ScrcpyStatusConnectingFailed, message, false)
        }
        
        // 不自动清理当前会话，等待用户主动 dismiss
        
        print("📝 [SessionConnectionManager] Error message passed to ConnectionStatusView: \(message)")
    }
    
    /// 设置当前连接的会话
    /// - Parameters:
    ///   - session: 会话模型
    ///   - connectionInfo: 连接信息（包含实际的 host 和 port）
    func setCurrentSession(_ session: ScrcpySessionModel, connectionInfo: NetworkConnectionInfo?) {
        connectionInstanceID = UUID()
        currentSession = session
        
        // 清除连接中的会话信息，因为现在已经设置为当前会话
        connectingSession = nil
        
        if let info = connectionInfo {
            actualHost = info.host
            actualPort = info.port
            isUsingTailscale = info.isUsingTailscale
            tailscaleLocalPort = info.localForwardPort
        } else {
            actualHost = session.hostReal
            actualPort = session.port
            isUsingTailscale = false
            tailscaleLocalPort = nil
        }
        
        connectionStatus = ScrcpyStatusConnecting
        
        print("📱 [SessionConnectionManager] Current session set: \(session.sessionName)")
        print("📍 [SessionConnectionManager] Connection: \(actualHost ?? "unknown"):\(actualPort ?? "unknown")")
        if isUsingTailscale {
            print("🔗 [SessionConnectionManager] Using Tailscale (local port: \(tailscaleLocalPort ?? 0))")
        }
    }
    
    /// 清除当前会话信息
    func clearCurrentSession(clearPendingAction: Bool = true) {
        // Give the orientation controller a chance to restore Android before
        // releasing the ADB client / Tailscale forward on an unexpected exit.
        let endingConnectionID = connectionInstanceID
        IPhoneOrientationSync.shared.stop { [weak self] in
            guard let self = self, self.connectionInstanceID == endingConnectionID else { return }
            self.finishClearCurrentSession(clearPendingAction: clearPendingAction)
        }
    }

    private func finishClearCurrentSession(clearPendingAction: Bool) {
        connectionInstanceID = UUID() // Invalidate any duplicate disconnect callback.
        let wasConnected = currentSession != nil
        let previousHost = actualHost
        let previousPort = actualPort

        currentSession = nil
        actualHost = nil
        actualPort = nil
        isUsingTailscale = false
        tailscaleLocalPort = nil
        connectionStatus = ScrcpyStatusDisconnected
        isConnecting = false
        connectionStartTime = nil

        // Stop the silent-audio keep-alive engine if it was running —
        // there is nothing left to keep alive once the session is gone.
        BackgroundKeepAliveManager.shared.sessionDisconnected()

        // 当没有已连接的session时,清除保存的上次连接session
        // 避免下次重连了上次成功过但已经主动断开过的连接
        clearLastSession()

        // 清理待执行的动作（如果需要）
        if clearPendingAction {
            pendingAction = nil
            isConnectingWithAction = false
            hasExecutedPendingAction = false
            currentActionConfirmationCallback = nil
            pendingConfirmationAction = nil
            pendingConfirmationCallback = nil
            print("🧹 [SessionConnectionManager] Pending action cleared")
        } else {
            print("💾 [SessionConnectionManager] Pending action preserved for reconnection")
        }

        // 清理 ScrcpyClientWrapper 实例
        scrcpyClientWrapper = nil

        // 停止 Live Activity
        if #available(iOS 16.1, *),
           let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            manager.stopActivity()
        }

        // 保留状态回调，立即清除
        currentConnectionCallback = nil

        // 延迟清除错误回调，确保用户能看到可能的错误消息
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.currentErrorCallback = nil
        }

        if wasConnected {
            print("🧹 [SessionConnectionManager] Session cleared - was connected to \(previousHost ?? "unknown"):\(previousPort ?? "unknown")")
            print("⏰ [SessionConnectionManager] Connection time cleared")
        } else {
            print("🧹 [SessionConnectionManager] Session cleared - no previous connection")
        }
    }
    
    /// 连接成功后清理回调
    private func cleanupCallbacksAfterSuccess() {
        print("🧹 [SessionConnectionManager] Cleaning up callbacks after successful connection")
        
        // 清理状态回调，避免 ConnectionStatusView 继续接收更新
        currentConnectionCallback = nil
        
        // 清理错误回调
        currentErrorCallback = nil
        
        print("✅ [SessionConnectionManager] Callbacks cleaned up after successful connection")
    }
    
    /// 连接失败后清理回调
    private func cleanupCallbacksAfterFailure() {
        print("🧹 [SessionConnectionManager] Cleaning up callbacks after connection failure")
        
        // 清理状态回调
        currentConnectionCallback = nil
        
        // 错误回调已经在显示错误时处理，这里确保清理
        currentErrorCallback = nil
        
        print("❌ [SessionConnectionManager] Callbacks cleaned up after connection failure")
    }
    
    /// 检查是否需要重连到新会话
    /// - Parameters:
    ///   - newSession: 新的会话
    ///   - newConnectionInfo: 新会话的连接信息
    /// - Returns: 是否需要重连
    func shouldReconnect(to newSession: ScrcpySessionModel, with newConnectionInfo: NetworkConnectionInfo?) -> Bool {
        // 如果当前没有活跃连接，直接连接
        guard connectionStatus != ScrcpyStatusDisconnected else {
            print("🆕 [SessionConnectionManager] No active connection, will connect")
            return true
        }
        
        // 获取新会话的实际连接地址
        let newHost = newConnectionInfo?.host ?? newSession.hostReal
        let newPort = newConnectionInfo?.port ?? newSession.port
        
        // 检查连接地址是否相同
        if actualHost == newHost && actualPort == newPort {
            print("🔄 [SessionConnectionManager] Same connection (\(newHost):\(newPort)), no reconnection needed")
            return false
        }
        
        // 检查会话类型是否相同
        if let currentSession = currentSession {
            if currentSession.deviceType != newSession.deviceType {
                print("🔀 [SessionConnectionManager] Different device type (\(currentSession.deviceType.rawValue) → \(newSession.deviceType.rawValue)), will reconnect")
                return true
            }
        }
        
        print("🔀 [SessionConnectionManager] Different connection (\(actualHost ?? "unknown"):\(actualPort ?? "unknown") → \(newHost):\(newPort)), will reconnect")
        return true
    }
    
    /// 断开当前连接
    func disconnectCurrent() {
        disconnectCurrent(completion: {})
    }

    private func disconnectCurrent(completion: @escaping () -> Void) {
        guard connectionStatus != ScrcpyStatusDisconnected else {
            print("🚫 [SessionConnectionManager] Already disconnected, no action needed")
            completion()
            return
        }
        // Wait for restoration before closing the ADB connection.
        IPhoneOrientationSync.shared.stop { [weak self] in
            self?.finishDisconnectCurrent()
            completion()
        }
    }

    private func finishDisconnectCurrent() {
        guard connectionStatus != ScrcpyStatusDisconnected else { return }
        print("🔌 [SessionConnectionManager] Disconnecting current connection")
        
        // 使用 ScrcpyClientWrapper 的 disconnect 方法
        if let wrapper = scrcpyClientWrapper {
            wrapper.disconnectCurrentClient()
        } else {
            // 备用方案：发送断开通知（用于向后兼容）
            print("⚠️ [SessionConnectionManager] No ScrcpyClientWrapper available, using notification fallback")
            NotificationCenter.default.post(
                name: Notification.Name("ScrcpyRequestDisconnectNotification"),
                object: nil
            )
        }
        
        // 清理端口转发
        if isUsingTailscale {
            SessionNetworking.shared.stopAllForwarding()
        }

        // 主动同步 Live Activity 状态并结束（在后台计时器断开时不会收到状态通知）
        if #available(iOS 16.1, *),
           let manager = liveActivityManager as? ScrcpyLiveActivityManager,
           manager.hasActiveActivity {
            let duration = connectionDuration
            print("🎭 [SessionConnectionManager] Sync Live Activity on background disconnect, duration: \(duration)s")
            manager.updateActivity(status: ScrcpyStatusDisconnected, statusMessage: "Disconnected in background", connectionDuration: duration)
        }

        // 清理当前会话并停止相关资源（其中包含停止 Live Activity 的保障）
        clearCurrentSession(clearPendingAction: true)
    }
    
    private func startIPhoneOrientationSyncIfNeeded() {
        guard let session = currentSession, session.deviceType == .adb,
              session.adbOptions.syncIPhoneOrientation else { return }
        // Rotation of secondary and virtual displays is not supported.
        guard !session.adbOptions.startNewDisplay,
              session.adbOptions.displayId.isEmpty || session.adbOptions.displayId == "0" else {
            print("[iPhoneOrientationSync] Secondary/virtual displays are not supported.")
            return
        }
        guard let serial = getADBDeviceSerial() else { return }
        IPhoneOrientationSync.shared.start(sessionID: session.id, serial: serial)
    }

    // MARK: - Utility Methods
    
    /// 获取当前连接的描述信息
    var connectionDescription: String {
        guard let session = currentSession else {
            return "No active connection"
        }
        
        let deviceType = session.deviceType.rawValue.uppercased()
        let sessionName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
        let connectionInfo = "\(actualHost ?? "unknown"):\(actualPort ?? "unknown")"
        
        var description = "[\(deviceType)] \(sessionName)"
        
        if isUsingTailscale {
            description += " via Tailscale (\(connectionInfo))"
        } else if actualHost != session.hostReal || actualPort != session.port {
            description += " → \(connectionInfo)"
        }
        
        return description
    }
    
    /// 获取连接状态的描述
    var statusDescription: String {
        return connectionStatus.description
    }
    
    /// 获取当前连接的持续时间（秒）
    var connectionDuration: TimeInterval {
        guard let startTime = connectionStartTime else {
            return 0
        }
        return Date().timeIntervalSince(startTime)
    }
    
    /// 获取格式化的连接持续时间字符串
    var formattedConnectionDuration: String {
        let duration = connectionDuration
        let minutes = Int(duration / 60)
        
        if minutes < 1 {
            return "< 1m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Debug Methods
    
    /// 测试通知系统是否正常工作
    func testNotificationSystem() {
        print("🧪 [SessionConnectionManager] Testing notification system...")
        
        // 发送一个测试通知
        NotificationCenter.default.post(
            name: Notification.Name("ScrcpyStatusUpdated"),
            object: nil,
            userInfo: ["status": 0] // ScrcpyStatusDisconnected
        )
        
        print("🧪 [SessionConnectionManager] Test notification sent")
    }
    
    // MARK: - Live Activity Integration
    
    /// 如果需要，启动 Live Activity
    private func startLiveActivityIfNeeded() {
        guard #available(iOS 16.1, *) else { return }
        
        // 检查用户是否启用了 Live Activity
        let liveActivityEnabled = UserDefaults.standard.object(forKey: "settings.live_activity.enabled") as? Bool ?? true
        guard liveActivityEnabled else {
            print("ℹ️ [SessionConnectionManager] Live Activity disabled by user")
            return
        }
        
        guard let session = currentSession,
              connectionStatus.isActive else {
            print("ℹ️ [SessionConnectionManager] Live Activity not needed")
            return
        }
        
        guard let manager = liveActivityManager as? ScrcpyLiveActivityManager else {
            print("ℹ️ [SessionConnectionManager] Live Activity manager not available")
            return
        }
        
        guard !manager.hasActiveActivity else {
            print("ℹ️ [SessionConnectionManager] Live Activity already active")
            return
        }
        
        print("🎭 [SessionConnectionManager] Starting Live Activity for background session")
        
        let sessionName = session.sessionName.isEmpty ? "\(session.hostReal):\(session.port)" : session.sessionName
        let deviceType = session.deviceType.rawValue
        let host = actualHost ?? session.hostReal
        let port = actualPort ?? session.port
        
        // 如果已经连接，使用实际的连接开始时间
        let actualStartTime = connectionStartTime ?? Date()
        
        manager.startActivity(
            sessionName: sessionName,
            deviceType: deviceType,
            hostAddress: host,
            port: port,
            initialStatus: connectionStatus,
            isUsingTailscale: isUsingTailscale,
            connectionStartTime: actualStartTime
        )
    }
    
    /// 如果需要，更新 Live Activity
    private func updateLiveActivityIfNeeded(status: ScrcpyStatus, message: String?) {
        guard #available(iOS 16.1, *) else { return }
        
        guard let manager = liveActivityManager as? ScrcpyLiveActivityManager else {
            return
        }
        
        guard manager.hasActiveActivity else {
            print("ℹ️ [SessionConnectionManager] No active Live Activity to update")
            return
        }
        
        let actualDuration = connectionDuration
        print("🔄 [SessionConnectionManager] Updating Live Activity with status: \(status.description), duration: \(actualDuration)s")
        manager.updateActivity(status: status, statusMessage: message, connectionDuration: actualDuration)
    }
    
    /// 检查 Live Activity 是否可用
    @available(iOS 16.1, *)
    var isLiveActivityAvailable: Bool {
        if let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            return manager.isActivityAvailable
        }
        return false
    }
    
    /// 手动启动 Live Activity（用于测试或用户主动启动）
    @available(iOS 16.1, *)
    func startLiveActivity() {
        startLiveActivityIfNeeded()
    }
    
    /// 手动停止 Live Activity
    @available(iOS 16.1, *)
    func stopLiveActivity() {
        if let manager = liveActivityManager as? ScrcpyLiveActivityManager {
            manager.stopActivity()
        }
    }
    
    // MARK: - Action Execution Methods
    
    /// 执行待执行的动作（如果有）
    private func executePendingActionIfNeeded() {
        print("🔍 [SessionConnectionManager] Checking for pending action...")
        print("📊 [SessionConnectionManager] isConnectingWithAction: \(isConnectingWithAction)")
        print("📋 [SessionConnectionManager] pendingAction: \(pendingAction?.name ?? "nil")")
        print("✅ [SessionConnectionManager] hasExecutedPendingAction: \(hasExecutedPendingAction)")
        
        guard let action = pendingAction else {
            print("ℹ️ [SessionConnectionManager] No pending action to execute")
            return
        }
        
        guard !hasExecutedPendingAction else {
            print("⚠️ [SessionConnectionManager] Pending action already executed, skipping")
            return
        }
        
        print("🎬 [SessionConnectionManager] Executing pending action: \(action.name)")
        hasExecutedPendingAction = true
        
        switch action.executionTiming {
        case .immediate:
            print("⚡ [SessionConnectionManager] Executing action immediately")
            executeAction(action)
        case .delayed:
            print("⏰ [SessionConnectionManager] Executing action after \(action.delaySeconds) seconds delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(action.delaySeconds)) {
                self.executeAction(action)
            }
        case .confirmation:
            print("❓ [SessionConnectionManager] Action requires confirmation after connection")
            // 如果有确认回调，调用它；否则直接执行（兼容性）
            if let confirmationCallback = currentActionConfirmationCallback {
                confirmationCallback(action) { [weak self] in
                    print("✅ [SessionConnectionManager] User confirmed action, executing")
                    self?.executeAction(action)
                }
            } else {
                print("⚠️ [SessionConnectionManager] No confirmation callback, executing directly")
                executeAction(action)
            }
        }
        
        // 清理待执行的动作和标志
        pendingAction = nil
        isConnectingWithAction = false
        hasExecutedPendingAction = false
        currentActionConfirmationCallback = nil
        pendingConfirmationAction = nil
        pendingConfirmationCallback = nil
    }
    
    /// 执行具体的动作
    /// - Parameter action: 要执行的动作
    private func executeAction(_ action: ScrcpyAction) {
        guard let currentSession = currentSession else {
            print("❌ [SessionConnectionManager] Cannot execute action: no current session")
            return
        }
        
        print("🚀 [SessionConnectionManager] Executing action: \(action.name)")
        print("🔧 [SessionConnectionManager] Device type: \(currentSession.deviceType)")
        
        switch currentSession.deviceType {
        case .vnc:
            print("🖥️ [SessionConnectionManager] Delegating VNC actions to VNC client")
            executeVNCActionsUsingClient(action)
        case .adb:
            print("📱 [SessionConnectionManager] Delegating ADB action to ADB client")
            executeADBActionUsingClient(action)
        @unknown default:
            print("⚠️ [SessionConnectionManager] Unknown device type: \(currentSession.deviceType)")
        }
        
        print("✅ [SessionConnectionManager] Action execution delegated successfully")
    }
    
    // MARK: - VNC Action Execution via Client
    
    /// 使用 ScrcpyClientWrapper 执行 VNC 动作
    /// - Parameter action: VNC 动作
    private func executeVNCActionsUsingClient(_ action: ScrcpyAction) {
        guard !action.vncQuickActions.isEmpty else {
            print("ℹ️ [SessionConnectionManager] No VNC actions to execute")
            return
        }
        
        guard let clientWrapper = scrcpyClientWrapper else {
            print("❌ [SessionConnectionManager] Cannot execute VNC actions: no ScrcpyClientWrapper available")
            return
        }
        
        print("🖥️ [SessionConnectionManager] Executing \(action.vncQuickActions.count) VNC actions via ScrcpyClientWrapper")
        
        // 检查是否包含 Input Keys 动作且需要键配置
        let hasInputKeys = action.vncQuickActions.contains(.inputKeys)
        if hasInputKeys && !action.vncInputKeysConfig.keys.isEmpty {
            // 执行带有键配置的 VNC 动作
            executeVNCActionsWithKeyConfig(action)
        } else {
            // 执行基本的 VNC 快捷动作
            let actionNumbers = action.vncQuickActions.compactMap { vncAction -> NSNumber? in
                return NSNumber(value: vncAction.toVNCQuickActionType())
            }
            
            clientWrapper.executeVNCActions(actionNumbers) { success, error  in
                DispatchQueue.main.async {
                    if success {
                        print("✅ [SessionConnectionManager] VNC actions executed successfully")
                    } else {
                        print("❌ [SessionConnectionManager] VNC actions execution failed: \(error ?? "Unknown error")")
                    }
                }
            }
        }
    }
    
    /// 执行带有键配置的 VNC 动作
    /// - Parameter action: 包含键配置的 VNC 动作
    private func executeVNCActionsWithKeyConfig(_ action: ScrcpyAction) {
        guard let clientWrapper = scrcpyClientWrapper else {
            print("❌ [SessionConnectionManager] Cannot execute VNC key actions: no ScrcpyClientWrapper available")
            return
        }
        
        print("🔧 [SessionConnectionManager] Executing VNC actions with \(action.vncInputKeysConfig.keys.count) configured keys")
        
        // 构建键动作序列
        var keyActions: [[String: Any]] = []
        
        // 处理每个配置的键
        for vncKeyAction in action.vncInputKeysConfig.keys {
            if !vncKeyAction.modifiers.isEmpty {
                // 处理带修饰符的键
                for modifier in vncKeyAction.modifiers {
                    let modifierAction = [
                        "type": "key",
                        "keyCode": String(modifier.toVNCKeyCode()),
                        "action": "down" // 按下修饰符
                    ]
                    keyActions.append(modifierAction)
                }
                
                // 按下主键
                let mainKeyAction = [
                    "type": "key",
                    "keyCode": String(vncKeyAction.keyCode),
                    "action": "press" // 完整按键
                ]
                keyActions.append(mainKeyAction)
                
                // 释放修饰符（逆序）
                for modifier in vncKeyAction.modifiers.reversed() {
                    let modifierReleaseAction = [
                        "type": "key",
                        "keyCode": String(modifier.toVNCKeyCode()),
                        "action": "up" // 释放修饰符
                    ]
                    keyActions.append(modifierReleaseAction)
                }
            } else {
                // 处理简单键
                let keyAction = [
                    "type": "key",
                    "keyCode": String(vncKeyAction.keyCode),
                    "action": "press"
                ]
                keyActions.append(keyAction)
            }
        }
        
        // 如果还有其他 VNC 快捷动作（如 Sync Clipboard），也要执行
        let otherActions = action.vncQuickActions.filter { $0 != .inputKeys }
        if !otherActions.isEmpty {
            let actionNumbers = otherActions.compactMap { vncAction -> NSNumber? in
                return NSNumber(value: vncAction.toVNCQuickActionType())
            }
            
            // 先执行键动作，再执行其他快捷动作
            executeVNCKeyActionsDirectly(keyActions, intervalMs: action.vncInputKeysConfig.intervalMs) { success, error in
                if success {
                    print("✅ [SessionConnectionManager] VNC key actions executed successfully")
                    // 执行其他快捷动作
                    clientWrapper.executeVNCActions(actionNumbers) { success2, error2 in
                        DispatchQueue.main.async {
                            if success2 {
                                print("✅ [SessionConnectionManager] All VNC actions executed successfully")
                            } else {
                                print("❌ [SessionConnectionManager] VNC other actions failed: \(error2 ?? "Unknown error")")
                            }
                        }
                    }
                } else {
                    print("❌ [SessionConnectionManager] VNC key actions failed: \(error ?? "Unknown error")")
                }
            }
        } else {
            // 只执行键动作
            executeVNCKeyActionsDirectly(keyActions, intervalMs: action.vncInputKeysConfig.intervalMs) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ [SessionConnectionManager] VNC key actions executed successfully")
                    } else {
                        print("❌ [SessionConnectionManager] VNC key actions failed: \(error ?? "Unknown error")")
                    }
                }
            }
        }
    }
    
    /// 直接执行 VNC 键动作（使用字典格式）
    /// - Parameters:
    ///   - keyActions: 键动作字典数组
    ///   - completion: 完成回调
    private func executeVNCKeyActionsDirectly(_ keyActions: [[String: Any]], intervalMs: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let clientWrapper = scrcpyClientWrapper else {
            completion(false, "No ScrcpyClientWrapper available")
            return
        }
        // 实际发送键事件到 VNC 客户端（通过通知）
        // 参照 ScrcpyVNCClient.m 中的 handleVNCKeyboardEvent -> sendKeyEvent 实现
        let notificationName = Notification.Name("ScrcpyVNCKeyboardEventNotification")
        let typeKey = "type" // kKeyType
        let keyCodeKey = "keyCode" // kKeyKeyCode
        let keyDown = "keyDown" // kKeyboardEventTypeKeyDown
        let keyUp = "keyUp"     // kKeyboardEventTypeKeyUp

        // 打印调试信息
        print("🔧 [SessionConnectionManager] Executing \(keyActions.count) VNC key actions (interval: \(intervalMs)ms)")

        // 事件调度：按顺序依次发送，支持 press/down/up
        let intervalSec = max(0, Double(intervalMs)) / 1000.0
        let pressHoldSec = min(0.06, max(0.02, intervalSec / 2.0)) // 按下到抬起的最小保持时间

        var cumulativeDelay: TimeInterval = 0

        for (index, keyAction) in keyActions.enumerated() {
            guard let codeStr = keyAction["keyCode"] as? String,
                  let code = Int(codeStr) else {
                print("⚠️ [SessionConnectionManager] Invalid key action (missing/invalid keyCode): \(keyAction)")
                continue
            }

            let action = (keyAction["action"] as? String ?? "press").lowercased()

            // 发送 keyDown
            if action == "down" || action == "press" {
                let delay = cumulativeDelay
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                    NotificationCenter.default.post(name: notificationName, object: nil, userInfo: [typeKey: keyDown, keyCodeKey: NSNumber(value: code)])
                    print("⌨️ [SessionConnectionManager] -> keyDown \(code) (step \(index + 1))")
                }
            }

            // 发送 keyUp
            if action == "up" || action == "press" {
                let upDelay = cumulativeDelay + (action == "press" ? pressHoldSec : 0)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + upDelay) {
                    NotificationCenter.default.post(name: notificationName, object: nil, userInfo: [typeKey: keyUp, keyCodeKey: NSNumber(value: code)])
                    print("⌨️ [SessionConnectionManager] -> keyUp \(code) (step \(index + 1))")
                }
            }

            // 累计间隔用于下一个按键
            cumulativeDelay += max(intervalSec, pressHoldSec)
        }

        // 在最后一个事件完成后回调完成
        let completionDelay = cumulativeDelay + 0.05
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + completionDelay) {
            completion(true, nil)
        }
    }
    
    // MARK: - ADB Action Execution via Client
    
    /// 使用 ScrcpyClientWrapper 执行 ADB 动作
    /// - Parameter action: ADB 动作
    private func executeADBActionUsingClient(_ action: ScrcpyAction) {
        guard let deviceSerial = getADBDeviceSerial() else {
            print("❌ [SessionConnectionManager] Cannot execute ADB action: no ADB device serial available")
            return
        }
        
        guard let clientWrapper = scrcpyClientWrapper else {
            print("❌ [SessionConnectionManager] Cannot execute ADB action: no ScrcpyClientWrapper available")
            return
        }
        
        print("📱 [SessionConnectionManager] Executing ADB action type: \(action.adbActionType.rawValue)")
        print("🎯 [SessionConnectionManager] Target ADB device serial: \(deviceSerial)")
        
        switch action.adbActionType {
        case .homeKey:
            print("🏠 [SessionConnectionManager] Executing Home key via ScrcpyClientWrapper")
            clientWrapper.executeADBHomeKey(onDevice: deviceSerial) { output, returnCode in
                DispatchQueue.main.async {
                    if returnCode == 0 {
                        print("✅ [SessionConnectionManager] Home key executed successfully on device: \(deviceSerial)")
                    } else {
                        print("❌ [SessionConnectionManager] Home key execution failed on device: \(deviceSerial), output: \(output ?? "N/A")")
                    }
                }
            }
            
        case .switchKey:
            print("🔀 [SessionConnectionManager] Executing Switch key via ScrcpyClientWrapper")
            clientWrapper.executeADBSwitchKey(onDevice: deviceSerial) { output, returnCode in
                DispatchQueue.main.async {
                    if returnCode == 0 {
                        print("✅ [SessionConnectionManager] Switch key executed successfully on device: \(deviceSerial)")
                    } else {
                        print("❌ [SessionConnectionManager] Switch key execution failed on device: \(deviceSerial), output: \(output ?? "N/A")")
                    }
                }
            }
            
        case .inputKeys:
            print("⌨️ [SessionConnectionManager] Executing input keys via ScrcpyClientWrapper")
            let keyCodes = action.adbInputKeysConfig.keys.map { NSNumber(value: $0.keyCode) }
            clientWrapper.executeADBKeySequence(keyCodes, onDevice: deviceSerial, interval: action.adbInputKeysConfig.intervalMs) { successCount, totalCount in
                DispatchQueue.main.async {
                    print("✅ [SessionConnectionManager] Key sequence execution completed: \(successCount)/\(totalCount) successful on device: \(deviceSerial)")
                }
            }
            
        case .shellCommands:
            print("💻 [SessionConnectionManager] Executing shell commands via ScrcpyClientWrapper")
            let commandLines = action.adbShellConfig.commands.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            clientWrapper.executeADBShellCommands(commandLines, onDevice: deviceSerial, interval: action.adbShellConfig.intervalMs) { successCount, totalCount in
                DispatchQueue.main.async {
                    print("✅ [SessionConnectionManager] Shell commands execution completed: \(successCount)/\(totalCount) successful on device: \(deviceSerial)")
                }
            }
        }
    }
    

    
    /// 获取当前设备地址（host:port格式）
    /// - Returns: 设备地址字符串，如果不可用则返回nil
    private func getDeviceAddress() -> String? {
        // 优先使用实际连接的地址（可能经过Tailscale代理）
        if let actualHost = actualHost, let actualPort = actualPort {
            return "\(actualHost):\(actualPort)"
        }
        
        // 备用方案：使用session中的原始地址
        if let session = currentSession {
            return "\(session.hostReal):\(session.port)"
        }
        
        return nil
    }
    
    /// 获取当前 ADB 设备的序列号（用于 ADB 命令执行）
    /// - Returns: ADB 设备序列号字符串，如果不可用则返回nil
    private func getADBDeviceSerial() -> String? {
        guard let session = currentSession, session.deviceType == .adb else {
            print("❌ [SessionConnectionManager] Cannot get ADB serial: no ADB session")
            return nil
        }
        
        // 如果通过 Tailscale 连接，使用 Tailscale 的本地转发地址作为设备序列号
        // 否则，使用原始的 host:port 作为设备序列号
        let adbSerial: String
        if isUsingTailscale, let host = actualHost, let port = actualPort {
            adbSerial = "\(host):\(port)"
            print("🔍 [SessionConnectionManager] ADB device serial (via Tailscale): \(adbSerial)")
        } else {
            adbSerial = "\(session.hostReal):\(session.port)"
            print("🔍 [SessionConnectionManager] ADB device serial: \(adbSerial)")
            if let actualHost = actualHost, let actualPort = actualPort,
               (actualHost != session.hostReal || actualPort != session.port) {
                print("🔗 [SessionConnectionManager] Connection via proxy: \(actualHost):\(actualPort)")
            }
        }
        
        return adbSerial
    }
    
    /// 设置等待确认的动作
    /// - Parameters:
    ///   - action: 等待确认的动作
    ///   - callback: 确认后的回调
    func setConfirmationAction(_ action: ScrcpyAction, callback: @escaping () -> Void) {
        pendingConfirmationAction = action
        pendingConfirmationCallback = callback
        print("💾 [SessionConnectionManager] Confirmation action set: \(action.name)")
    }
    
    /// 执行确认的动作
    func executeConfirmedAction() {
        guard let callback = pendingConfirmationCallback else {
            print("⚠️ [SessionConnectionManager] No pending confirmation callback")
            return
        }
        
        print("✅ [SessionConnectionManager] Executing confirmed action")
        callback()
        
        // 清理确认状态
        pendingConfirmationAction = nil
        pendingConfirmationCallback = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Objective-C Bridge Methods
    
    /// 获取当前连接的设备类型，供Objective-C代码调用
    /// - Returns: 设备类型字符串，"adb"或"vnc"，如果没有连接则返回nil
    @objc public func getCurrentDeviceType() -> String? {
        return currentSession?.deviceType.rawValue
    }
    
    /// 检查是否有当前活跃的连接，供Objective-C代码调用
    /// - Returns: 是否有活跃连接
    @objc public func hasActiveConnection() -> Bool {
        return currentSession != nil && connectionStatus.isActive
    }
    
    // MARK: - Error Detection Methods
    
    /// 检查scrcpy进程的最后输出中是否包含ERROR关键字，如果有则显示Alert
    private func checkForErrorsAndShowAlert() {
        // 调用C接口获取最后的输出
        guard let lastOutputCStr = scrcpy_process_get_last_output() else {
            print("ℹ️ [SessionConnectionManager] No last output available from scrcpy process")
            return
        }
        
        let lastOutput = String(cString: lastOutputCStr)
        print("📝 [SessionConnectionManager] Last scrcpy output: \(lastOutput)")
        
        // 检查输出中是否包含错误关键字（不区分大小写）
        let errorKeywords = ["ERROR:", "FATAL:", "CRITICAL:", "FAILED:"]
        let upperOutput = lastOutput.uppercased()
        
        if let foundKeyword = errorKeywords.first(where: { upperOutput.contains($0) }) {
            print("🚨 [SessionConnectionManager] Found \(foundKeyword) in scrcpy output, showing alert to user")
            
            // 提取错误相关的行
            let errorLines = extractErrorLines(from: lastOutput, keyword: foundKeyword)
            
            // 在主线程显示Alert
            DispatchQueue.main.async {
                self.showErrorAlert(with: errorLines)
            }
        } else {
            print("✅ [SessionConnectionManager] No error keywords found in scrcpy output")
        }
    }
    
    /// 从输出中提取包含错误关键字的行
    /// - Parameters:
    ///   - output: 完整的输出文本
    ///   - keyword: 找到的错误关键字
    /// - Returns: 包含错误的行组成的字符串
    private func extractErrorLines(from output: String, keyword: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorKeywords = ["ERROR:", "FATAL:", "CRITICAL:", "FAILED:"]
        
        // 查找包含任何错误关键字的行
        let errorLines = lines.filter { line in
            let upperLine = line.uppercased()
            return errorKeywords.contains { keyword in
                upperLine.contains(keyword)
            }
        }
        
        if errorLines.isEmpty {
            // 如果没有找到具体的错误行，返回整个输出的最后几行
            let lastLines = Array(lines.suffix(5)).joined(separator: "\n")
            return lastLines.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // 返回错误行，但限制最多5行以免Alert过长
            let limitedErrorLines = Array(errorLines.prefix(5))
            return limitedErrorLines.joined(separator: "\n")
        }
    }
    
    /// 显示错误Alert给用户
    /// - Parameter errorMessage: 错误消息
    private func showErrorAlert(with errorMessage: String) {
        guard let frontmostWindow = getFrontmostWindow() else {
            print("❌ [SessionConnectionManager] No frontmost window found, cannot show error alert")
            return
        }
        
        print("🚨 [SessionConnectionManager] Showing error alert to user")
        
        // 限制错误消息长度，避免Alert过大
        let maxLength = 500
        let truncatedMessage = errorMessage.count > maxLength ? 
            String(errorMessage.prefix(maxLength)) + "..." : errorMessage
        
        let alert = UIAlertController(
            title: NSLocalizedString("Scrcpy Connection Error", comment: "Alert title when scrcpy connection fails"),
            message: String(
                format: NSLocalizedString("The connection was terminated due to an error:\n\n%@", comment: "Alert message for scrcpy connection error with details"),
                truncatedMessage
            ),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default) { _ in
            print("✅ [SessionConnectionManager] User acknowledged error alert")
        })
        
        // 如果消息被截断，添加"查看详情"按钮
        if errorMessage.count > maxLength {
            alert.addAction(UIAlertAction(title: NSLocalizedString("View Details", comment: "View details button"), style: .default) { _ in
                print("📋 [SessionConnectionManager] User requested full error details")
                self.showDetailedErrorAlert(with: errorMessage)
            })
        }
        
        // 从最前显示的窗口的根视图控制器展示Alert
        if let rootViewController = frontmostWindow.rootViewController {
            var topViewController = rootViewController
            
            // 找到最顶层的视图控制器
            while let presentedViewController = topViewController.presentedViewController {
                topViewController = presentedViewController
            }
            
            topViewController.present(alert, animated: true) {
                print("🎯 [SessionConnectionManager] Error alert presented successfully")
            }
        } else {
            print("❌ [SessionConnectionManager] No root view controller found on frontmost window")
        }
    }
    
    /// 获取最前显示的窗口
    /// - Returns: 最前显示的UIWindow实例
    private func getFrontmostWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            // iOS 13+ 从活跃的 UIWindowScene 中获取关键窗口
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene,
                      windowScene.activationState == .foregroundActive else {
                    continue
                }
                
                // 获取该场景中的关键窗口
                for window in windowScene.windows {
                    if window.isKeyWindow {
                        return window
                    }
                }
                
                // 如果没有关键窗口，返回第一个可见窗口
                return windowScene.windows.first { $0.isHidden == false }
            }
        } else {
            // iOS 12 及以下使用传统方式
            if let keyWindow = UIApplication.shared.keyWindow {
                return keyWindow
            }
            return UIApplication.shared.windows.first { $0.isHidden == false }
        }
        
        return nil
    }
    
    /// 显示详细错误信息Alert
    /// - Parameter errorMessage: 完整的错误消息
    private func showDetailedErrorAlert(with errorMessage: String) {
        guard let frontmostWindow = getFrontmostWindow() else {
            print("❌ [SessionConnectionManager] No frontmost window found for detailed error alert")
            return
        }
        
        print("📋 [SessionConnectionManager] Showing detailed error alert")
        
        let alert = UIAlertController(
            title: NSLocalizedString("Detailed Error Information", comment: "Title for detailed error info alert"),
            message: errorMessage,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default) { _ in
            print("✅ [SessionConnectionManager] User closed detailed error alert")
        })
        
        // 从最前显示的窗口的根视图控制器展示Alert
        if let rootViewController = frontmostWindow.rootViewController {
            var topViewController = rootViewController
            
            // 找到最顶层的视图控制器
            while let presentedViewController = topViewController.presentedViewController {
                topViewController = presentedViewController
            }
            
            topViewController.present(alert, animated: true) {
                print("📋 [SessionConnectionManager] Detailed error alert presented successfully")
            }
        }
    }

    // MARK: - Auto Reconnect Methods

    /// 保存当前会话(如果启用了自动重连)
    private func saveCurrentSessionIfAutoReconnectEnabled() {
        let autoReconnectEnabled = UserDefaults.standard.bool(forKey: "settings.auto_reconnect.enabled")
        guard autoReconnectEnabled else {
            print("ℹ️ [SessionConnectionManager] Auto reconnect disabled, skip saving session on connect")
            return
        }

        guard let session = currentSession else {
            print("⚠️ [SessionConnectionManager] No current session to save on connect")
            return
        }

        print("💾 [SessionConnectionManager] Connection successful, saving session for auto-reconnect...")
        print("   - Session name: \(session.sessionName)")
        print("   - Session host: \(session.hostReal)")
        print("   - Session port: \(session.port)")
        print("   - Device type: \(session.deviceType.rawValue)")
        saveLastSession(session)
    }

    /// 保存上次连接的会话到 UserDefaults
    /// - Parameter session: 要保存的会话
    private func saveLastSession(_ session: ScrcpySessionModel) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(session)
            UserDefaults.standard.set(data, forKey: lastSessionKey)
            print("✅ [SessionConnectionManager] Last session saved successfully to UserDefaults")
        } catch {
            print("❌ [SessionConnectionManager] Failed to save last session: \(error)")
        }
    }

    /// 从 UserDefaults 恢复上次连接的会话
    /// - Returns: 上次连接的会话,如果不存在或解析失败则返回 nil
    private func loadLastSession() -> ScrcpySessionModel? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionKey) else {
            print("ℹ️ [SessionConnectionManager] No saved last session found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let session = try decoder.decode(ScrcpySessionModel.self, from: data)
            print("📂 [SessionConnectionManager] Last session loaded successfully: \(session.sessionName)")
            return session
        } catch {
            print("❌ [SessionConnectionManager] Failed to load last session: \(error)")
            return nil
        }
    }

    /// 清除保存的上次连接会话
    private func clearLastSession() {
        UserDefaults.standard.removeObject(forKey: lastSessionKey)
        print("🧹 [SessionConnectionManager] Last session cleared")
    }

    /// 尝试自动重连(如果需要)
    private func attemptAutoReconnectIfNeeded() {
        print("🔍 [SessionConnectionManager] --- Auto Reconnect Check Start ---")

        // 检查是否有待处理的 URL scheme,如果有则优先处理 URL scheme
        if AppSchemeManagerV2.shared.pendingScheme != nil {
            print("⏭️ [SessionConnectionManager] URL scheme is pending, skipping auto reconnect")
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")
            return
        }

        // 检查是否启用了自动重连
        let autoReconnectEnabled = UserDefaults.standard.bool(forKey: "settings.auto_reconnect.enabled")
        print("⚙️ [SessionConnectionManager] Auto reconnect setting: \(autoReconnectEnabled)")

        guard autoReconnectEnabled else {
            print("⏭️ [SessionConnectionManager] Auto reconnect is disabled, skipping")
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")
            return
        }

        // 如果当前已经有活跃连接,不需要重连
        print("📊 [SessionConnectionManager] Checking current connection state...")
        print("   - Is active: \(connectionStatus.isActive)")
        print("   - Is connecting: \(isConnecting)")

        guard !connectionStatus.isActive else {
            print("✅ [SessionConnectionManager] Already connected, no need to reconnect")
            print("🧹 [SessionConnectionManager] Clearing saved session to avoid duplicate")
            clearLastSession()
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")
            return
        }

        // 如果正在连接中,不尝试重连
        guard !isConnecting else {
            print("🔄 [SessionConnectionManager] Already connecting, skip auto reconnect")
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")
            return
        }

        // 尝试加载上次保存的会话
        print("📂 [SessionConnectionManager] Loading saved session...")
        guard let lastSession = loadLastSession() else {
            print("ℹ️ [SessionConnectionManager] No saved session found, nothing to reconnect")
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")
            return
        }

        print("✅ [SessionConnectionManager] Found saved session to reconnect:")
        print("   - Session name: \(lastSession.sessionName)")
        print("   - Session host: \(lastSession.hostReal)")
        print("   - Session port: \(lastSession.port)")
        print("   - Device type: \(lastSession.deviceType.rawValue)")
        print("⏰ [SessionConnectionManager] Will attempt reconnect after 0.5 second delay...")

        // 延迟一小段时间再重连,避免在应用启动过程中立即连接
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            print("⏰ [SessionConnectionManager] Delay completed, rechecking connection state...")

            // 再次检查连接状态,确保在延迟期间没有建立连接
            guard !self.connectionStatus.isActive && !self.isConnecting else {
                print("✅ [SessionConnectionManager] Connection already established during delay")
                print("🧹 [SessionConnectionManager] Clearing saved session")
                self.clearLastSession()
                print("🔍 [SessionConnectionManager] --- Auto Reconnect Attempt Cancelled ---")
                return
            }

            print("🚀 [SessionConnectionManager] Starting auto reconnect...")
            print("🔍 [SessionConnectionManager] --- Auto Reconnect Check End ---")

            // 执行自动重连
            self.connectToSession(lastSession,
                statusCallback: { status, message, isConnecting in
                    print("🔄 [SessionConnectionManager] Auto reconnect status update:")
                    print("   - Status: \(status.description)")
                    print("   - Is connecting: \(isConnecting)")
                    if let msg = message {
                        print("   - Message: \(msg)")
                    }
                },
                errorCallback: { title, message in
                    print("❌ [SessionConnectionManager] Auto reconnect failed:")
                    print("   - Title: \(title)")
                    print("   - Message: \(message)")
                    print("🧹 [SessionConnectionManager] Clearing saved session after failure")
                    self.clearLastSession()
                }
            )
        }
    }
}
