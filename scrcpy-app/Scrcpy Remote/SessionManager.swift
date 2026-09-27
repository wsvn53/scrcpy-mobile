//
//  SessionManager.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/14/24.
//

import KeychainSwift
import Foundation
import Security

// VNC压缩等级枚举
enum VNCCompressionLevel: String, Codable, CaseIterable {
    case none = "none"
    case standard = "standard"
    case maximum = "maximum"
    
    var displayName: String {
        switch self {
        case .none:
            return NSLocalizedString("VNC Compression None", comment: "VNC compression level option")
        case .standard:
            return NSLocalizedString("VNC Compression Standard", comment: "VNC compression level option")
        case .maximum:
            return NSLocalizedString("VNC Compression Maximum", comment: "VNC compression level option")
        }
    }
    
    var compressionValue: Int {
        switch self {
        case .none:
            return 0
        case .standard:
            return 6
        case .maximum:
            return 9
        }
    }
}

// VNC质量等级枚举
enum VNCQualityLevel: String, Codable, CaseIterable {
    case lowest = "lowest"      // rfbEncodingQualityLevel0
    case low = "low"           // rfbEncodingQualityLevel2
    case standard = "standard"  // rfbEncodingQualityLevel5
    case high = "high"         // rfbEncodingQualityLevel7
    case highest = "highest"    // rfbEncodingQualityLevel9
    
    var displayName: String {
        switch self {
        case .lowest:
            return NSLocalizedString("VNC Quality Lowest", comment: "VNC quality level option")
        case .low:
            return NSLocalizedString("VNC Quality Low", comment: "VNC quality level option")
        case .standard:
            return NSLocalizedString("VNC Quality Standard", comment: "VNC quality level option")
        case .high:
            return NSLocalizedString("VNC Quality High", comment: "VNC quality level option")
        case .highest:
            return NSLocalizedString("VNC Quality Highest", comment: "VNC quality level option")
        }
    }
    
    var qualityValue: Int {
        switch self {
        case .lowest:
            return 0
        case .low:
            return 2
        case .standard:
            return 5
        case .high:
            return 7
        case .highest:
            return 9
        }
    }
}

// VNC Session Model can be saved to AppStorage
struct VNCSessionOptions: Codable, Identifiable {
    var id = UUID()
    var vncUser: String = ""
    var vncPassword: String = ""
    var compressionLevel: VNCCompressionLevel = .standard
    var qualityLevel: VNCQualityLevel = .standard

    // VNC Audio Streaming Options
    var enableAudio: Bool = false
    var audioPort: String = ""  // Empty means default 4901
    var audioBufferMs: Int = 100  // Audio buffer time in milliseconds

    init() { }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.vncUser = try container.decodeIfPresent(String.self, forKey: .vncUser) ?? ""
        self.vncPassword = try container.decodeIfPresent(String.self, forKey: .vncPassword) ?? ""
        self.compressionLevel = try container.decodeIfPresent(VNCCompressionLevel.self, forKey: .compressionLevel) ?? .standard
        self.qualityLevel = try container.decodeIfPresent(VNCQualityLevel.self, forKey: .qualityLevel) ?? .standard
        self.enableAudio = try container.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? false
        self.audioPort = try container.decodeIfPresent(String.self, forKey: .audioPort) ?? ""
        self.audioBufferMs = try container.decodeIfPresent(Int.self, forKey: .audioBufferMs) ?? 100
    }
}

// Video Codec Enum for ADB Session
enum ADBVideoCodec: String, Codable, CaseIterable {
    case h264 = "h264"
    case h265 = "h265"
}

// Audio Codec Enum for ADB Session
enum ADBAudioCodec: String, Codable, CaseIterable {
    case opus = "opus"
    case aac = "aac"
    case flac = "flac"
    case raw = "raw"
}

// ADB Session Model can be saved to AppStorage
struct ADBSessionOptions: Codable, Identifiable {
    var id = UUID()
    var maxScreenSize: String = ""
    var bitRate: String = ""
    var videoCodec: ADBVideoCodec = .h264
    var videoEncoder: String = ""
    var audioCodec: ADBAudioCodec = .opus
    var audioEncoder: String = ""
    var maxFPS: String = "60"
    var enableAudio: Bool = false
    var enableClipboardSync: Bool = true
    var volumeScale: Double = 1.0
    
    // 新虚拟显示器选项
    var startNewDisplay: Bool = false
    var displayWidth: String = ""
    var displayHeight: String = ""
    var displayDPI: String = "240"

    // Existing display selection (foldable / external secondary screens).
    // Empty = default (display 0). Mapped to scrcpy's --display-id, which
    // determines BOTH the captured video stream and the display that touch
    // events are injected into.
    var displayId: String = ""
    
    // 连接后关闭远程屏幕选项
    var turnScreenOff: Bool = true
    
    // 保持远程设备唤醒选项
    var stayAwake: Bool = false
    
    // 断开连接后关闭远程屏幕选项
    var powerOffOnClose: Bool = false

    // 断开连接后不清理选项（保持屏幕状态）
    var noCleanup: Bool = false

    // 强制 ADB 转发连接选项
    var forceAdbForward: Bool = false
    
    // 自定义标志字典，用于支持额外的 scrcpy 参数
    var customFlags: [String: String] = [:]
    
    // 硬件解码选项，默认启用
    var enableHardwareDecoding: Bool = true

    // 跟随远程设备方向变化选项，默认禁用
    var followRemoteOrientation: Bool = false

    // Keep the Android primary display aligned with the iPhone's physical orientation.
    var syncIPhoneOrientation: Bool = false

    init() { }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode with default values for backward compatibility
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.maxScreenSize = try container.decodeIfPresent(String.self, forKey: .maxScreenSize) ?? ""
        self.bitRate = try container.decodeIfPresent(String.self, forKey: .bitRate) ?? ""
        self.videoEncoder = try container.decodeIfPresent(String.self, forKey: .videoEncoder) ?? ""
        self.audioCodec = try container.decodeIfPresent(ADBAudioCodec.self, forKey: .audioCodec) ?? .opus
        self.audioEncoder = try container.decodeIfPresent(String.self, forKey: .audioEncoder) ?? ""
        self.maxFPS = try container.decodeIfPresent(String.self, forKey: .maxFPS) ?? "60"
        self.enableAudio = try container.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? false
        self.videoCodec = try container.decodeIfPresent(ADBVideoCodec.self, forKey: .videoCodec) ?? .h264
        self.enableClipboardSync = try container.decodeIfPresent(Bool.self, forKey: .enableClipboardSync) ?? true
        self.volumeScale = try container.decodeIfPresent(Double.self, forKey: .volumeScale) ?? 1.0
        
        // 解码新虚拟显示器选项
        self.startNewDisplay = try container.decodeIfPresent(Bool.self, forKey: .startNewDisplay) ?? false
        self.displayWidth = try container.decodeIfPresent(String.self, forKey: .displayWidth) ?? ""
        self.displayHeight = try container.decodeIfPresent(String.self, forKey: .displayHeight) ?? ""
        self.displayDPI = try container.decodeIfPresent(String.self, forKey: .displayDPI) ?? "240"

        // 解码已存在显示器 ID 选项（折叠屏/副屏），默认为空（主屏 0）
        self.displayId = try container.decodeIfPresent(String.self, forKey: .displayId) ?? ""
        
        // 解码连接后关闭远程屏幕选项，默认为 true
        self.turnScreenOff = try container.decodeIfPresent(Bool.self, forKey: .turnScreenOff) ?? true
        
        // 解码保持远程设备唤醒选项，默认为 false
        self.stayAwake = try container.decodeIfPresent(Bool.self, forKey: .stayAwake) ?? false
        
        // 解码断开连接后关闭远程屏幕选项，默认为 true
        self.powerOffOnClose = try container.decodeIfPresent(Bool.self, forKey: .powerOffOnClose) ?? true

        // 解码断开连接后不清理选项，默认为 false
        self.noCleanup = try container.decodeIfPresent(Bool.self, forKey: .noCleanup) ?? false

        // 解码强制 ADB 转发连接选项，默认为 false
        self.forceAdbForward = try container.decodeIfPresent(Bool.self, forKey: .forceAdbForward) ?? false
        
        // 解码自定义标志，默认为空字典
        self.customFlags = try container.decodeIfPresent([String: String].self, forKey: .customFlags) ?? [:]
        
        // 解码硬件解码选项，默认为 true
        self.enableHardwareDecoding = try container.decodeIfPresent(Bool.self, forKey: .enableHardwareDecoding) ?? true

        // 解码跟随远程设备方向变化选项，默认为 false
        self.followRemoteOrientation = try container.decodeIfPresent(Bool.self, forKey: .followRemoteOrientation) ?? false
        self.syncIPhoneOrientation = try container.decodeIfPresent(Bool.self, forKey: .syncIPhoneOrientation) ?? false
    }
}

// Enum for device types
enum SessionDeviceType: String, Codable, CaseIterable {
    case vnc = "vnc"
    case adb = "adb"
    
    // Objective-C compatible integer representation
    var intValue: Int {
        switch self {
        case .vnc: return 0
        case .adb: return 1
        }
    }
    
    // Create from integer value (for Objective-C bridge)
    init?(intValue: Int) {
        switch intValue {
        case 0: self = .vnc
        case 1: self = .adb
        default: return nil
        }
    }
}

// A ScrcpySession Model can be saved to AppStorage
@objc class ScrcpySessionModel: NSObject, Codable, Identifiable {
    @objc var id = UUID()
    @objc var deviceId = UUID()
    @objc var host: String
    @objc var port: String
    @objc var sessionName: String = ""
    @objc var useTailscale: Bool = false
    
    var hostReal: String {
        get {
            // Strip vnc:// and adb://
            return host.replacingOccurrences(of: "vnc://", with: "").replacingOccurrences(of: "adb://", with: "")
        }
    }

    // Objective-C compatible accessor for hostReal
    @objc var hostRealValue: String {
        return hostReal
    }

    var deviceType: SessionDeviceType {
        get {
            // If host has explicit scheme prefix, use it
            if host.starts(with: "vnc://") {
                return .vnc
            }
            if host.starts(with: "adb://") {
                return .adb
            }

            // Auto-detect based on port number
            if let portNumber = Int(port) {
                // VNC ports: < 5555, 590x (5900-5909), 1590x (15900-15909), or 2590x (25900-25909)
                if portNumber < 5555 ||
                   (portNumber >= 5900 && portNumber <= 5909) ||
                   (portNumber >= 15900 && portNumber <= 15909) ||
                   (portNumber >= 25900 && portNumber <= 25909) {
                    return .vnc
                }
                // All other ports default to ADB
                return .adb
            }

            // Default fallback to VNC if port is not a valid number
            return .vnc
        }
    }

    // Objective-C compatible accessor for device type
    @objc var deviceTypeIntValue: Int {
        return deviceType.intValue
    }

    var vncOptions: VNCSessionOptions = VNCSessionOptions()
    var adbOptions: ADBSessionOptions = ADBSessionOptions()
    
    override init() {
        host = ""
        port = ""
        sessionName = ""
        useTailscale = false
        vncOptions = VNCSessionOptions()
        adbOptions = ADBSessionOptions()
        super.init()
    }
    
    init(host: String, port: String) {
        self.host = host
        self.port = port
        self.sessionName = ""
        self.useTailscale = false
        self.vncOptions = VNCSessionOptions()
        self.adbOptions = ADBSessionOptions()
        super.init()
    }
    
    init(host: String, port: String, sessionName: String = "") {
        self.host = host
        self.port = port
        self.sessionName = sessionName
        self.useTailscale = false
        self.vncOptions = VNCSessionOptions()
        self.adbOptions = ADBSessionOptions()
        super.init()
    }
    
    // Custom decoder for backward compatibility
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        self.id = try container.decode(UUID.self, forKey: .id)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(String.self, forKey: .port)
        
        // Decode optional fields with default values for backward compatibility
        // For backward compatibility: if deviceId is not present, use the existing id as deviceId
        self.deviceId = try container.decodeIfPresent(UUID.self, forKey: .deviceId) ?? self.id
        self.sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        self.useTailscale = try container.decodeIfPresent(Bool.self, forKey: .useTailscale) ?? false
        
        // Decode nested objects with error handling
        do {
            self.vncOptions = try container.decode(VNCSessionOptions.self, forKey: .vncOptions)
        } catch {
            self.vncOptions = VNCSessionOptions()
        }
        
        do {
            self.adbOptions = try container.decode(ADBSessionOptions.self, forKey: .adbOptions)
        } catch {
            self.adbOptions = ADBSessionOptions()
        }
        
        super.init()
    }
    
    func toDict() -> [String: Any] {
        do {
            let jsonData = try JSONEncoder().encode(self)
            guard var dictionary = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] else {
                return [:]
            }
            dictionary["hostReal"] = hostReal
            dictionary["deviceType"] = deviceType.rawValue
            dictionary["deviceId"] = deviceId.uuidString
            return dictionary
        } catch {
            print("Error encoding or serializing: \(error)")
            return [:]
        }
    }
}

class SessionManager {
    static let shared = SessionManager()
    private let keychain = KeychainSwift()
    
    private let sessionKey = "scrcpy.sessions"
    private let migrationKey = "scrcpy.migration.completed"
    
    private init() {
        keychain.synchronizable = true
        checkAndPerformMigration()
    }
    
    func saveSession(_ session: ScrcpySessionModel) {
        // Save session to keychain
        var sessions = loadSessions()
        
        // Check if session already exists
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            print("Updating session at index:", index)
            sessions[index] = session
            let data = try! JSONEncoder().encode(sessions)
            keychain.set(data, forKey: sessionKey)
            return
        }
        
        sessions.append(session)
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func loadSessions() -> [ScrcpySessionModel] {
        // Load saved sessions from keychain
        if let data = keychain.getData(sessionKey) {
            do {
                let sessions = try JSONDecoder().decode([ScrcpySessionModel].self, from: data)
                return sessions
            } catch {
                print("Failed to decode sessions:", error)
                return []
            }
        }
        print("No sessions found")
        return []
    }
    
    func getSession(at index: Int) -> ScrcpySessionModel? {
        // Get session at index
        let sessions = loadSessions()
        if index < sessions.count {
            return sessions[index]
        }
        return nil
    }
    
    func getSession(id: UUID) -> ScrcpySessionModel? {
        // Get session by id
        let sessions = loadSessions()
        return sessions.first { $0.id == id }
    }
    
    func getSession(byName name: String) -> ScrcpySessionModel? {
        // Get session by name
        let sessions = loadSessions()
        return sessions.first { $0.sessionName.lowercased() == name.lowercased() }
    }
    
    func getSessions(host: String, port: String) -> [ScrcpySessionModel] {
        // Get sessions by host and port
        let sessions = loadSessions()
        return sessions.filter { $0.host == host && $0.port == port }
    }
    
    func deleteSession(id: UUID) {
        // Delete session by id
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func deleteSession(at index: Int) {
        // Delete session at index
        var sessions = loadSessions()
        sessions.remove(at: index)
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func updateSession(at index: Int, with session: ScrcpySessionModel) {
        // Update session at index
        var sessions = loadSessions()
        sessions[index] = session
        let data = try! JSONEncoder().encode(sessions)
        keychain.set(data, forKey: sessionKey)
    }
    
    func clearSessions() {
        // Clear all saved sessions
        keychain.delete(sessionKey)
    }
    
    // MARK: - Migration Logic
    
    private func checkAndPerformMigration() {
        // Check if migration has already been completed or declined
        if keychain.getBool(migrationKey) == true {
            print("📱 [SessionManager] Migration already processed, skipping")
            return
        }
        
        print("📱 [SessionManager] Checking for old scrcpy-ios data...")
        
        // Check if legacy data exists but don't auto-migrate
        if hasLegacyData() {
            print("📱 [SessionManager] Found legacy data, waiting for user decision...")
            // Don't auto-migrate, let UI handle the user prompt
        } else {
            print("📱 [SessionManager] No legacy data found")
            // Mark as processed to avoid future checks
            keychain.set(true, forKey: migrationKey)
        }
    }
    
    private func hasLegacyData() -> Bool {
        // Check for legacy keychain keys that indicate old scrcpy-ios data
        let legacyKeys = ["adb-host", "adb-port", "max-size", "video-bit-rate", "max-fps"]
        
        for key in legacyKeys {
            if getLegacyKeychainValue(for: key) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func performMigration() {
        // Extract legacy settings from keychain using old KFKeychain format
        let legacyHost = getLegacyKeychainValue(for: "adb-host") ?? ""
        let legacyPort = getLegacyKeychainValue(for: "adb-port") ?? "5555"
        
        // Only create migration session if we have meaningful host data
        guard !legacyHost.isEmpty else {
            print("📱 [SessionManager] No valid host found in legacy data, skipping migration")
            return
        }
        
        print("📱 [SessionManager] Migrating legacy device: \(legacyHost):\(legacyPort)")
        
        // Create new ADB session from legacy data
        var migratedSession = ScrcpySessionModel(
            host: "adb://\(legacyHost)",
            port: legacyPort,
            sessionName: "Migrated Device"
        )
        
        // Migrate ADB options
        migratedSession.adbOptions = createADBOptionsFromLegacy()
        
        // Save the migrated session
        saveSession(migratedSession)
        
        print("📱 [SessionManager] Successfully created migrated session: \(migratedSession.sessionName)")
    }
    
    private func createADBOptionsFromLegacy() -> ADBSessionOptions {
        var adbOptions = ADBSessionOptions()
        
        // Migrate text-based settings with defaults using legacy keychain format
        adbOptions.maxScreenSize = getLegacyKeychainValue(for: "max-size") ?? ""
        adbOptions.bitRate = getLegacyKeychainValue(for: "video-bit-rate") ?? ""
        adbOptions.maxFPS = getLegacyKeychainValue(for: "max-fps") ?? "60"
        
        // Migrate boolean settings using legacy keychain format
        adbOptions.turnScreenOff = getLegacyBoolFromKeychain("turn-screen-off", defaultValue: true)
        adbOptions.stayAwake = getLegacyBoolFromKeychain("stay-awake", defaultValue: false)
        adbOptions.forceAdbForward = getLegacyBoolFromKeychain("force-adb-forward", defaultValue: false)
        adbOptions.powerOffOnClose = getLegacyBoolFromKeychain("power-off-on-close", defaultValue: false)
        adbOptions.enableAudio = getLegacyBoolFromKeychain("enable-audio", defaultValue: false)
        adbOptions.enableClipboardSync = true // Default for new sessions
        
        return adbOptions
    }
    
    private func getBoolFromKeychain(_ key: String, defaultValue: Bool) -> Bool {
        if let stringValue = keychain.get(key) {
            // Handle both string and number representations
            if stringValue.lowercased() == "true" || stringValue == "1" {
                return true
            } else if stringValue.lowercased() == "false" || stringValue == "0" {
                return false
            }
        }
        return defaultValue
    }
    
    // MARK: - Public Migration Methods
    
    func shouldShowMigrationPrompt() -> Bool {
        // Show prompt if migration hasn't been processed and legacy data exists
        return keychain.getBool(migrationKey) != true && hasLegacyData()
    }
    
    func getLegacyDeviceInfo() -> (host: String, port: String)? {
        guard hasLegacyData() else { return nil }
        
        let host = getLegacyKeychainValue(for: "adb-host") ?? ""
        let port = getLegacyKeychainValue(for: "adb-port") ?? "5555"
        
        guard !host.isEmpty else { return nil }
        
        return (host: host, port: port)
    }
    
    func performUserRequestedMigration() {
        guard hasLegacyData() else {
            print("📱 [SessionManager] No legacy data to migrate")
            return
        }
        
        print("📱 [SessionManager] User requested migration, performing...")
        performMigration()
        
        // Mark migration as completed
        keychain.set(true, forKey: migrationKey)
        print("📱 [SessionManager] User-requested migration completed successfully")
    }
    
    func declineMigration() {
        // Mark migration as processed (declined) to avoid showing prompt again
        keychain.set(true, forKey: migrationKey)
        print("📱 [SessionManager] User declined migration")
    }
    
    // MARK: - Legacy Keychain Access (KFKeychain compatible)
    
    private func getLegacyKeychainValue(for key: String) -> String? {
        let query = createLegacyKeychainQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        // Try to unarchive the data using NSKeyedUnarchiver (like KFKeychain does)
        do {
            if let unarchivedObject = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) {
                return unarchivedObject as? String
            }
        } catch {
            // If unarchiving fails, try to read as plain string
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    private func getLegacyBoolFromKeychain(_ key: String, defaultValue: Bool) -> Bool {
        if let value = getLegacyKeychainValue(for: key) {
            // Handle both string and number representations
            if value.lowercased() == "true" || value == "1" {
                return true
            } else if value.lowercased() == "false" || value == "0" {
                return false
            }
        }
        return defaultValue
    }
    
    private func createLegacyKeychainQuery(for key: String) -> NSMutableDictionary {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}

// MARK: - Action Manager

@objc class ActionManager: NSObject, ObservableObject {
    @objc static let shared = ActionManager()
    
    private let actionsKey = "ScrcpyActions"
    
    @Published var actions: [ScrcpyAction] = []
    
    private override init() {
        super.init()
        loadActions()
    }
    
    func loadActions() {
        if let data = UserDefaults.standard.data(forKey: actionsKey) {
            do {
                let decoder = JSONDecoder()
                actions = try decoder.decode([ScrcpyAction].self, from: data)
                print("📋 [ActionManager] Loaded \(actions.count) actions")
                
                // Debug: Print all loaded action names and IDs
                for (index, action) in actions.enumerated() {
                    print("📋 [ActionManager] Loaded Action[\(index)]: '\(action.name)' (ID: \(action.id))")
                }
                
                // Fix duplicate IDs if any exist
                fixDuplicateIds()
                
            } catch {
                print("❌ [ActionManager] Failed to decode actions: \(error)")
                actions = []
            }
        } else {
            print("📋 [ActionManager] No saved actions found, starting with empty array")
            actions = []
        }
    }
    
    private func fixDuplicateIds() {
        var seenIds = Set<UUID>()
        var needsSave = false
        
        for action in actions {
            if seenIds.contains(action.id) {
                let oldId = action.id
                action.id = UUID()
                print("🔧 [ActionManager] Fixed duplicate ID for '\(action.name)': \(oldId) -> \(action.id)")
                needsSave = true
            } else {
                seenIds.insert(action.id)
            }
        }
        
        if needsSave {
            print("🔧 [ActionManager] Saving actions after fixing duplicate IDs")
            saveActions()
        }
    }
    
    func saveAction(_ action: ScrcpyAction) {
        print("📝 [ActionManager] saveAction called with: '\(action.name)' (ID: \(action.id), deviceId: \(action.deviceId?.uuidString ?? "nil"))")

        // Ensure we're on the main thread for @Published to work properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update existing action or add new one
            if let index = self.actions.firstIndex(where: { $0.id == action.id }) {
                print("📝 [ActionManager] Updating existing action at index \(index): '\(action.name)' (ID: \(action.id))")
                print("📝 [ActionManager] Old deviceId: \(self.actions[index].deviceId?.uuidString ?? "nil"), New deviceId: \(action.deviceId?.uuidString ?? "nil")")

                // Replace with new action object
                self.actions[index] = action
            } else {
                print("📝 [ActionManager] Adding new action: '\(action.name)' (ID: \(action.id))")
                self.actions.append(action)
            }

            // Save to persistent storage
            self.saveActions()

            // Verify the save immediately
            if let savedAction = self.actions.first(where: { $0.id == action.id }) {
                print("✅ [ActionManager] Action in memory: '\(savedAction.name)' (deviceId: \(savedAction.deviceId?.uuidString ?? "nil"))")
            } else {
                print("❌ [ActionManager] Failed to find saved action with ID: \(action.id)")
            }

            // Force SwiftUI to detect the change by triggering objectWillChange
            self.objectWillChange.send()

            print("🔄 [ActionManager] Triggered objectWillChange to force UI refresh")
        }
    }
    
    func deleteAction(id: UUID) {
        actions.removeAll { $0.id == id }
        saveActions()
        
        // Force UI refresh by creating a new array reference
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let currentActions = self.actions
            self.actions = []  // Clear first
            self.actions = currentActions  // Then reassign to trigger @Published
            print("🔄 [ActionManager] Forced UI refresh after deletion")
        }
    }

    func duplicateAction(_ action: ScrcpyAction) {
        // Create a deep copy using JSON encoding/decoding
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(action)
            
            let decoder = JSONDecoder()
            let newAction = try decoder.decode(ScrcpyAction.self, from: data)
            
            // Assign new unique properties
            let oldId = newAction.id
            newAction.id = UUID() // Assign a new ID
            let newId = newAction.id
            print("🆔 [ActionManager] Changing ID from \(oldId) to \(newId)")
            
            newAction.name = findNextAvailableName(for: action.name, excluding: action.id)
            newAction.createdAt = Date() // Update creation date
            
            print("📋 [ActionManager] Duplicating: '\(action.name)' -> '\(newAction.name)' (New ID: \(newAction.id))")
            
            actions.append(newAction)
            saveActions()
            
            // Force UI refresh by creating a new array reference
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let currentActions = self.actions
                self.actions = []  // Clear first
                self.actions = currentActions  // Then reassign to trigger @Published
                print("🔄 [ActionManager] Forced UI refresh after duplication")
            }
            
            print("📋 [ActionManager] Successfully duplicated action: '\(action.name)' -> '\(newAction.name)'")
        } catch {
            print("❌ [ActionManager] Failed to duplicate action: \(error)")
        }
    }

    private func findNextAvailableName(for baseName: String, excluding excludeId: UUID? = nil) -> String {
        // Filter out the action being duplicated to avoid self-reference
        let existingNames = Set(actions.compactMap { action -> String? in
            if let excludeId = excludeId, action.id == excludeId {
                return nil // Exclude the original action
            }
            return action.name
        })
        
        // Regex to find a number suffix like " (1)"
        let regex = try! NSRegularExpression(pattern: "^(.*?)(?:\\s*\\(\\d+\\))?$")
        let baseNameMatches = regex.matches(in: baseName, range: NSRange(baseName.startIndex..., in: baseName))
        
        var coreName = baseName
        if let match = baseNameMatches.first {
            if let coreRange = Range(match.range(at: 1), in: baseName) {
                coreName = String(baseName[coreRange])
            }
        }
        
        // Clean up trailing spaces from the core name
        coreName = coreName.trimmingCharacters(in: .whitespaces)
        
        // For duplication, always start with (1) suffix
        var counter = 1
        var newName: String
        
        while true {
            newName = "\(coreName) (\(counter))"
            
            if !existingNames.contains(newName) {
                return newName
            }
            counter += 1
        }
    }
    
    private func saveActions() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(actions)
            UserDefaults.standard.set(data, forKey: actionsKey)
            print("💾 [ActionManager] Saved \(actions.count) actions")
            
            // Debug: Print all action names and IDs
            for (index, action) in actions.enumerated() {
                print("💾 [ActionManager] Action[\(index)]: '\(action.name)' (ID: \(action.id))")
            }
        } catch {
            print("❌ [ActionManager] Failed to encode actions: \(error)")
        }
    }
    
    @objc func getActionBy(_ id: UUID) -> ScrcpyAction? {
        return actions.first { $0.id == id }
    }

    @objc func getActionsFor(_ deviceId: UUID) -> [ScrcpyAction] {
        return actions.filter { $0.deviceId == deviceId }
    }

    /// Get actions for a specific device plus "any device" actions that match the device type
    func getActionsForDeviceAndType(_ deviceId: UUID, deviceType: SessionDeviceType) -> [ScrcpyAction] {
        return actions.filter { action in
            // Include if action is for this specific device
            if action.deviceId == deviceId {
                return true
            }
            // Include if action is an "any device" action matching this device type
            if action.deviceId == nil && action.deviceType == deviceType {
                return true
            }
            return false
        }
    }

    /// Get "any device" actions for a specific device type
    func getAnyDeviceActionsFor(deviceType: SessionDeviceType) -> [ScrcpyAction] {
        return actions.filter { $0.deviceId == nil && $0.deviceType == deviceType }
    }

    /// Get "any device" actions by device type using Int (for ObjC bridge)
    @objc func getAnyDeviceActionsForType(_ deviceTypeInt: Int) -> [ScrcpyAction] {
        guard let deviceType = SessionDeviceType(intValue: deviceTypeInt) else {
            return []
        }
        return getAnyDeviceActionsFor(deviceType: deviceType)
    }

    /// Get actions for a specific device plus "any device" actions using Int (for ObjC bridge)
    @objc func getActionsForDeviceAndTypeInt(_ deviceId: UUID, deviceTypeInt: Int) -> [ScrcpyAction] {
        guard let deviceType = SessionDeviceType(intValue: deviceTypeInt) else {
            return getActionsFor(deviceId)
        }
        return getActionsForDeviceAndType(deviceId, deviceType: deviceType)
    }
}
