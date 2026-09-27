//
//  SessionCreateView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI
import UIKit

struct SessionCreateView: View {
    @State var sessionModel = ScrcpySessionModel()
    // Local input state so device type reacts instantly
    @State private var hostInput: String = ""
    @State private var portInput: String = ""
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingTailscaleAuth = false
    @State private var returnedFromTailscaleAuth = false
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""
    @State private var forceVNCMode = false
    // Local state for picker selections to ensure UI refresh
    @State private var selectedCompressionLevel: VNCCompressionLevel = .standard
    @State private var selectedQualityLevel: VNCQualityLevel = .standard
    @State private var selectedVideoCodec: ADBVideoCodec = .h264
    @State private var selectedAudioCodec: ADBAudioCodec = .opus
    @State private var selectedVolumeScale: Double = 1.0
    // Local state for toggles that control show/hide to ensure UI refresh
    @State private var useTailscale: Bool = false
    @State private var enableVNCaudio: Bool = false
    @State private var enableADBaudio: Bool = false
    @State private var startNewDisplay: Bool = false
    private let isEditMode: Bool
    
    // Check if ADB is auto-selected based on input (not forced by user)
    private var isADBAutoSelected: Bool {
        // Only show force VNC option if:
        // 1. No explicit scheme in host
        // 2. Port would normally trigger ADB detection
        // 3. Not already in force VNC mode
        if hostInput.starts(with: "vnc://") || hostInput.starts(with: "adb://") {
            return false
        }
        if let portNumber = Int(portInput) {
            let wouldBeVNC = portNumber < 5555 ||
                           (portNumber >= 5900 && portNumber <= 5909) ||
                           (portNumber >= 15900 && portNumber <= 15909) ||
                           (portNumber >= 25900 && portNumber <= 25909)
            return !wouldBeVNC && !forceVNCMode
        }
        return false
    }
    
    // Get effective device type based on current input
    private var effectiveDeviceType: SessionDeviceType {
        let detected = detectDeviceType(host: hostInput, port: portInput)
        // Only allow force override when no explicit scheme and ADB would be selected
        let hasScheme = hostInput.starts(with: "vnc://") || hostInput.starts(with: "adb://")
        if !hasScheme && forceVNCMode && detected == .adb { return .vnc }
        return detected
    }
    
    init() {
        isEditMode = false
    }

    init(sessionModel: ScrcpySessionModel) {
        _sessionModel = State(initialValue: sessionModel)
        _hostInput = State(initialValue: sessionModel.host)
        _portInput = State(initialValue: sessionModel.port)
        _selectedCompressionLevel = State(initialValue: sessionModel.vncOptions.compressionLevel)
        _selectedQualityLevel = State(initialValue: sessionModel.vncOptions.qualityLevel)
        _selectedVideoCodec = State(initialValue: sessionModel.adbOptions.videoCodec)
        _selectedAudioCodec = State(initialValue: sessionModel.adbOptions.audioCodec)
        _selectedVolumeScale = State(initialValue: sessionModel.adbOptions.volumeScale)
        // Initialize toggle states
        _useTailscale = State(initialValue: sessionModel.useTailscale)
        _enableVNCaudio = State(initialValue: sessionModel.vncOptions.enableAudio)
        _enableADBaudio = State(initialValue: sessionModel.adbOptions.enableAudio)
        _startNewDisplay = State(initialValue: sessionModel.adbOptions.startNewDisplay)
        isEditMode = true
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Remote Device")) {
                    TextField("Session Name (Optional)", text: $sessionModel.sessionName)
                        .autocorrectionDisabled()
                    TextField("Host or vnc://host or adb://host", text: $hostInput)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    TextField("Port", text: $portInput)
                        .keyboardType(.numberPad)
                }
                
                // Show force VNC mode option when ADB is auto-selected
                if isADBAutoSelected {
                    Section {
                        Toggle("Force Switch to VNC mode", isOn: $forceVNCMode)
                    }
                }
                
                Section(header: Text("Connection Options")) {
                    Toggle("Connect over Tailscale", isOn: $useTailscale.animation())
                        .onChange(of: useTailscale) { newValue in
                            sessionModel.useTailscale = newValue
                            if newValue {
                                // Check if Tailscale Auth Key is set
                                if appSettings.tailscaleAuthKey.isEmpty {
                                    // If not set, show Tailscale Auth settings
                                    showingTailscaleAuth = true
                                    // Temporarily disable the toggle until auth is set
                                    useTailscale = false
                                    sessionModel.useTailscale = false
                                }
                            }
                        }

                    if !useTailscale {
                        Text("Please ensure you have a Tailscale account and the target device is connected to your Tailscale network.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }

                    if useTailscale {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Tailscale Authentication Configured")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Text("This session will connect through Tailscale network")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if effectiveDeviceType == .adb {
                        Toggle("Force Connect ADB Forward", isOn: $sessionModel.adbOptions.forceAdbForward)
                    }
                }
                
                if effectiveDeviceType == .vnc {
                    Section(header: Text("VNC Session Options")) {
                        TextField("VNC User (Optional)", text: $sessionModel.vncOptions.vncUser)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .autocorrectionDisabled(true)
                        SecureField("VNC Password", text: $sessionModel.vncOptions.vncPassword)
                            .textContentType(.password)

                        Picker("Compress Level", selection: $selectedCompressionLevel) {
                            ForEach(VNCCompressionLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedCompressionLevel) { newValue in
                            sessionModel.vncOptions.compressionLevel = newValue
                        }

                        Picker("Quality Level", selection: $selectedQualityLevel) {
                            ForEach(VNCQualityLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedQualityLevel) { newValue in
                            sessionModel.vncOptions.qualityLevel = newValue
                        }

                        Toggle("Enable Audio Streaming", isOn: $enableVNCaudio.animation())
                            .onChange(of: enableVNCaudio) { newValue in
                                sessionModel.vncOptions.enableAudio = newValue
                            }

                        if enableVNCaudio {
                            TextField("Audio Port (Default: 4901)", text: $sessionModel.vncOptions.audioPort)
                                .keyboardType(.numberPad)

                            Stepper(value: $sessionModel.vncOptions.audioBufferMs, in: 50...500, step: 50) {
                                Text("Buffer: \(sessionModel.vncOptions.audioBufferMs) ms")
                            }

                            Text("Receives MP3 audio stream over TCP. Increase buffer if audio breaks.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if effectiveDeviceType == .adb {
                    Section(header: Text("ADB Session Options")) {
                        TextField("Max Screen Size", text: $sessionModel.adbOptions.maxScreenSize)
                            .keyboardType(.numberPad)
                        TextField("Bit Rate, Default: 4M or 4000K", text: $sessionModel.adbOptions.bitRate)
                            .autocapitalization(.none)
                            .autocorrectionDisabled(true)
                            .onChange(of: sessionModel.adbOptions.bitRate) { newValue in
                                if !newValue.isEmpty {
                                    let filteredValue = filterBitRateInput(newValue)
                                    if filteredValue != newValue {
                                        sessionModel.adbOptions.bitRate = filteredValue
                                    }
                                }
                            }
                        Picker("Video Codec", selection: $selectedVideoCodec) {
                            ForEach(ADBVideoCodec.allCases, id: \.self) { codec in
                                Text(codec.rawValue)
                            }
                        }
                        .onChange(of: selectedVideoCodec) { newValue in
                            sessionModel.adbOptions.videoCodec = newValue
                        }
                        // navigation with link to baidu.com
                        if hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || portInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack {
                                Text("Video Encoder")
                                Spacer()
                                Text("Enter host and port first")
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.secondary)
                        } else {
                            NavigationLink(destination: VideoEncoderSelectionView(
                                selectedEncoder: $sessionModel.adbOptions.videoEncoder,
                                host: hostInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                port: Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5555
                            )) {
                                HStack {
                                    Text("Video Encoder")
                                    Spacer()
                                    Text(sessionModel.adbOptions.videoEncoder.isEmpty ? NSLocalizedString("Default", comment: "Default option label") : sessionModel.adbOptions.videoEncoder)
                                        .foregroundColor(sessionModel.adbOptions.videoEncoder.isEmpty ? .secondary : .primary)
                                }
                            }
                        }
                        TextField("Max FPS, Default: 60", text: $sessionModel.adbOptions.maxFPS)
                            .keyboardType(.numberPad)
                        Toggle("Enable Audio (Android 11+)", isOn: $enableADBaudio.animation())
                            .onChange(of: enableADBaudio) { newValue in
                                sessionModel.adbOptions.enableAudio = newValue
                            }
                        if enableADBaudio {
                            Picker("Audio Codec", selection: $selectedAudioCodec) {
                                ForEach(ADBAudioCodec.allCases, id: \.self) { codec in
                                    Text(codec.rawValue)
                                }
                            }
                            .onChange(of: selectedAudioCodec) { newValue in
                                sessionModel.adbOptions.audioCodec = newValue
                            }
                            if hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || portInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack {
                                    Text("Audio Encoder")
                                    Spacer()
                                    Text("Enter host and port first")
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(.secondary)
                            } else {
                                NavigationLink(destination: AudioEncoderSelectionView(
                                    selectedEncoder: $sessionModel.adbOptions.audioEncoder,
                                    host: hostInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                    port: Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5555
                                )) {
                                    HStack {
                                        Text("Audio Encoder")
                                        Spacer()
                                        Text(sessionModel.adbOptions.audioEncoder.isEmpty ? NSLocalizedString("Default", comment: "Default option label") : sessionModel.adbOptions.audioEncoder)
                                            .foregroundColor(sessionModel.adbOptions.audioEncoder.isEmpty ? .secondary : .primary)
                                    }
                                }
                            }
                            HStack {
                                Text("Volume Scale")
                                Spacer()
                                Text(String(format: "%.1fx", selectedVolumeScale))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $selectedVolumeScale, in: 0...50, step: 0.1)
                                .onChange(of: selectedVolumeScale) { newValue in
                                    sessionModel.adbOptions.volumeScale = newValue
                                }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Enable Clipboard Sync", isOn: $sessionModel.adbOptions.enableClipboardSync)
                            Text("Disable on rooted devices or custom ROMs if the connection drops immediately after connect (clipboard SecurityException).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Toggle("Turn Remote Screen Off After Connected", isOn: $sessionModel.adbOptions.turnScreenOff)
                        
                        Toggle("Lock Remote Screen After Disconnected (Press Power)", isOn: $sessionModel.adbOptions.powerOffOnClose)

                        Toggle("No Cleanup After Disconnected (Keep Screen State)", isOn: $sessionModel.adbOptions.noCleanup)

                        Toggle("Keep Remote Device Awake During Use", isOn: $sessionModel.adbOptions.stayAwake)
                        
                        Toggle("Enable Hardware Decoding", isOn: $sessionModel.adbOptions.enableHardwareDecoding)

                        Toggle("Follow Remote Orientation Change", isOn: $sessionModel.adbOptions.followRemoteOrientation)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Sync iPhone Orientation to Android", isOn: $sessionModel.adbOptions.syncIPhoneOrientation)
                                .disabled(startNewDisplay || (!sessionModel.adbOptions.displayId.isEmpty && sessionModel.adbOptions.displayId != "0"))
                            Text("Match the Android main display to your iPhone when connecting and rotating. Restores the Android rotation mode on normal disconnect. Does not change display resolution.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !startNewDisplay {
                            HStack {
                                Text("Display ID")
                                Spacer()
                                TextField("0", text: $sessionModel.adbOptions.displayId)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            }
                        }

                        Toggle("Start New Display", isOn: $startNewDisplay.animation())
                            .onChange(of: startNewDisplay) { newValue in
                                sessionModel.adbOptions.startNewDisplay = newValue
                            }

                        if startNewDisplay {
                            HStack {
                                Text("Size:")
                                TextField("Width", text: $sessionModel.adbOptions.displayWidth)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                Text("x")
                                    .foregroundColor(.secondary)
                                TextField("Height", text: $sessionModel.adbOptions.displayHeight)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                Button("Sync iPhone Size") {
                                    setLocalScreenSize()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                                .frame(minWidth: 140)
                                .multilineTextAlignment(.center)
                            }
                            TextField("Display DPI", text: $sessionModel.adbOptions.displayDPI)
                                .keyboardType(.numberPad)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        // Validate session before saving (using current input values)
                        if validateSession() {
                            // Sync inputs to model for saving
                            syncInputsToSessionModel()
                            // Apply force VNC mode to session if needed
                            applyForceVNCMode()
                            // Save session
                            SessionManager.shared.saveSession(sessionModel)
                            // Pop back
                            dismiss()
                        } else {
                            showingValidationError = true
                        }
                    }) {
                        Text("Save Session")
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationBarTitle(isEditMode ? "Edit Session" : "Create Session", displayMode: .inline)
            .onAppear {
                // Always initialize local inputs from session model when view appears.
                // This ensures values are populated when reopening the editor.
                hostInput = sessionModel.host
                portInput = sessionModel.port

                // Initialize picker state variables
                selectedCompressionLevel = sessionModel.vncOptions.compressionLevel
                selectedQualityLevel = sessionModel.vncOptions.qualityLevel
                selectedVideoCodec = sessionModel.adbOptions.videoCodec
                selectedAudioCodec = sessionModel.adbOptions.audioCodec
                selectedVolumeScale = sessionModel.adbOptions.volumeScale

                // Initialize toggle state variables
                useTailscale = sessionModel.useTailscale
                enableVNCaudio = sessionModel.vncOptions.enableAudio
                enableADBaudio = sessionModel.adbOptions.enableAudio
                startNewDisplay = sessionModel.adbOptions.startNewDisplay
            }
            .onChange(of: hostInput) { newValue in
                // If user types explicit scheme, ignore any previous force toggle
                let lower = newValue.lowercased()
                if lower.hasPrefix("adb://") || lower.hasPrefix("vnc://") {
                    forceVNCMode = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Validate session before saving
                        if validateSession() {
                            // Sync inputs to model for saving
                            syncInputsToSessionModel()
                            // Apply force VNC mode to session if needed
                            applyForceVNCMode()
                            
                            // Save session
                            SessionManager.shared.saveSession(sessionModel)
                            
                            // Pop back
                            dismiss()
                        } else {
                            showingValidationError = true
                        }
                    }
                    .font(.headline)
                }
            }
        }
        .sheet(isPresented: $showingTailscaleAuth) {
            NavigationView {
                TailscaleAuthSettingsView()
                    .navigationBarTitle("Tailscale Auth", displayMode: .inline)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingTailscaleAuth = false
                                returnedFromTailscaleAuth = true
                            }
                        }
                    }
            }
            .environmentObject(appSettings)
        }
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK") { }
        } message: {
            Text(validationErrorMessage)
        }
        .onChange(of: showingTailscaleAuth) { isShowing in
            if !isShowing && returnedFromTailscaleAuth {
                // Check if auth key was set after returning from Tailscale Auth
                if !appSettings.tailscaleAuthKey.isEmpty {
                    useTailscale = true
                    sessionModel.useTailscale = true
                }
                returnedFromTailscaleAuth = false
            }
        }
        .onAppear {
            // On view appear, if this is edit mode and Tailscale auth key is set,
            // keep the current useTailscale state. If it's create mode and auth key is set,
            // we can optionally suggest using Tailscale but don't force it.
            if isEditMode && sessionModel.useTailscale && appSettings.tailscaleAuthKey.isEmpty {
                // If editing a session that had Tailscale enabled but auth key is now missing,
                // disable Tailscale for safety
                useTailscale = false
                sessionModel.useTailscale = false
            }
        }
    }
    
    private func setLocalScreenSize() {
        // Set display dimensions based on current device screen
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale
        
        // Calculate pixel dimensions (points * scale = pixels)
        let pixelWidth = bounds.width * scale
        let pixelHeight = bounds.height * scale
        
        // Set the display dimensions to match local screen
        sessionModel.adbOptions.displayWidth = String(Int(pixelWidth))
        sessionModel.adbOptions.displayHeight = String(Int(pixelHeight))
    }
    
    private func setDefaultDisplayDimensions() {
        // Set default display dimensions based on current device screen
        let screen = UIScreen.main
        let bounds = screen.bounds
        
        // Calculate pixel dimensions (points * scale = pixels)
        let pixelWidth = bounds.width
        let pixelHeight = bounds.height
        
        // Set default values if they're empty
        if sessionModel.adbOptions.displayWidth.isEmpty {
            sessionModel.adbOptions.displayWidth = String(Int(pixelWidth))
        }
        if sessionModel.adbOptions.displayHeight.isEmpty {
            sessionModel.adbOptions.displayHeight = String(Int(pixelHeight))
        }
    }
    
    // MARK: - Validation Methods
    
    private func validateSession() -> Bool {
        // Check host
        if hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = NSLocalizedString("Please enter a valid host address.", comment: "Validation: invalid host")
            return false
        }
        
        // Check port
        if portInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = NSLocalizedString("Please enter a port number.", comment: "Validation: empty port")
            return false
        }
        
        if !isValidPort(portInput) {
            validationErrorMessage = NSLocalizedString("Please enter a valid port number (1-65535).", comment: "Validation: invalid port range")
            return false
        }
        
        // Check device-specific fields
        if effectiveDeviceType == .vnc {
            // VNC User is optional, only check password
            if sessionModel.vncOptions.vncPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationErrorMessage = NSLocalizedString("Please enter a VNC password.", comment: "Validation: empty VNC password")
                return false
            }
        }
        
        if effectiveDeviceType == .adb {
            // Validate new display settings if enabled
            if sessionModel.adbOptions.startNewDisplay {
                if sessionModel.adbOptions.displayWidth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !isValidPositiveInteger(sessionModel.adbOptions.displayWidth) {
                    validationErrorMessage = NSLocalizedString("Please enter a valid display width.", comment: "Validation: invalid width")
                    return false
                }
                
                if sessionModel.adbOptions.displayHeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !isValidPositiveInteger(sessionModel.adbOptions.displayHeight) {
                    validationErrorMessage = NSLocalizedString("Please enter a valid display height.", comment: "Validation: invalid height")
                    return false
                }
                
                if !sessionModel.adbOptions.displayDPI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !isValidPositiveInteger(sessionModel.adbOptions.displayDPI) {
                    validationErrorMessage = NSLocalizedString("Please enter a valid display DPI.", comment: "Validation: invalid DPI")
                    return false
                }
            }
            
            // Validate max FPS if provided
            if !sessionModel.adbOptions.maxFPS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !isValidPositiveInteger(sessionModel.adbOptions.maxFPS) {
                validationErrorMessage = NSLocalizedString("Please enter a valid max FPS value.", comment: "Validation: invalid fps")
                return false
            }
            
            // Validate max screen size if provided
            if !sessionModel.adbOptions.maxScreenSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !isValidPositiveInteger(sessionModel.adbOptions.maxScreenSize) {
                validationErrorMessage = NSLocalizedString("Please enter a valid max screen size.", comment: "Validation: invalid max screen size")
                return false
            }
        }
        
        // Check Tailscale configuration
        if sessionModel.useTailscale && appSettings.tailscaleAuthKey.isEmpty {
            validationErrorMessage = NSLocalizedString("Tailscale authentication is required but not configured.", comment: "Validation: tailscale not configured")
            return false
        }
        
        return true
    }
    
    private func isValidPort(_ port: String) -> Bool {
        guard let portNumber = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return portNumber >= 1 && portNumber <= 65535
    }
    
    private func isValidPositiveInteger(_ value: String) -> Bool {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return intValue > 0
    }
    
    private func detectDeviceType(host: String, port: String) -> SessionDeviceType {
        // Respect explicit scheme first
        if host.starts(with: "vnc://") { return .vnc }
        if host.starts(with: "adb://") { return .adb }
        // Fallback to port-based detection
        if let portNumber = Int(port) {
            if portNumber < 5555 ||
               (portNumber >= 5900 && portNumber <= 5909) ||
               (portNumber >= 15900 && portNumber <= 15909) ||
               (portNumber >= 25900 && portNumber <= 25909) {
                return .vnc
            }
            return .adb
        }
        return .vnc
    }
    
    private func syncInputsToSessionModel() {
        sessionModel.host = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionModel.port = portInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func applyForceVNCMode() {
        if forceVNCMode {
            // Add vnc:// prefix to force VNC mode in the saved session
            if !sessionModel.host.starts(with: "vnc://") && !sessionModel.host.starts(with: "adb://") {
                sessionModel.host = "vnc://" + sessionModel.host
            }
        }
    }
}

struct VideoEncoderSelectionView: View {
    @Binding var selectedEncoder: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var encoders: [ADBMediaEncoder] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // Get host and port from the session model - we need to pass these in
    let host: String
    let port: Int
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Detecting Video Encoders...")
                        .font(.headline)
                    Text(String(
                        format: NSLocalizedString("Connecting to %@:%d", comment: "Connecting to host:port"),
                        host, port
                    ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section(header: Text("Encoder Options")) {
                        HStack {
                            Text("Default Encoder")
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedEncoder.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Add haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            selectedEncoder = ""
                            dismiss()
                        }
                        .padding(.vertical, 8)
                        .background(
                            selectedEncoder.isEmpty ? 
                            Color.blue.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(8)
                        
                        TextField("Enter custom encoder name", text: $selectedEncoder)
                            .autocorrectionDisabled()
                    }
                    
                    if !encoders.isEmpty {
                        Section(header: Text("Detected Encoders")) {
                            ForEach(encoders, id: \.encoderName) { encoder in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(encoder.encoderName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(encoder.mediaType)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedEncoder == encoder.encoderName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Add haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    selectedEncoder = encoder.encoderName
                                    dismiss()
                                }
                                .padding(.vertical, 8)
                                .background(
                                    selectedEncoder == encoder.encoderName ? 
                                    Color.blue.opacity(0.1) : Color.clear
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Section {
                        Button("Refresh Encoders") {
                            detectEncoders()
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .navigationBarTitle("Select Video Encoder", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .disabled(isLoading)
            }
        }
        .alert("Detection Failed", isPresented: $showingError) {
            Button("OK") { }
            Button("Retry") {
                detectEncoders()
            }
        } message: {
            Text(errorMessage ?? NSLocalizedString("Failed to detect encoders", comment: "Fallback detection error message"))
        }
        .onAppear {
            detectEncoders()
        }
    }
    
    private func detectEncoders() {
        isLoading = true
        errorMessage = nil
        
        let detector = ADBMediaDetector()
        detector.detectMediaCodecs(forHost: host, port: Int32(port)) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if success {
                    // Filter to only show video encoders (mediaType starts with "video/")
                    encoders = detector.mediaEncoders.filter { encoder in
                        encoder.mediaType.lowercased().hasPrefix("video/")
                    }
                } else {
                    var fullErrorMessage = error?.localizedDescription ?? NSLocalizedString("Failed to detect encoders. Please check your connection and try again.", comment: "Detection failure default message")
                    
                    // Add raw ADB output for diagnostic purposes
                    if let nsError = error as NSError?,
                       let adbOutput = nsError.userInfo["ADBOutput"] as? String {
                        fullErrorMessage += "\n\n" + NSLocalizedString("Diagnostic info:", comment: "Label for additional diagnostic information") + "\n\(adbOutput)"
                    }
                    
                    errorMessage = fullErrorMessage
                    showingError = true
                }
            }
        }
    }
}

struct AudioEncoderSelectionView: View {
    @Binding var selectedEncoder: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var encoders: [ADBMediaEncoder] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    
    let host: String
    let port: Int
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Detecting Audio Encoders...")
                        .font(.headline)
                    Text(String(
                        format: NSLocalizedString("Connecting to %@:%d", comment: "Connecting to host:port"),
                        host, port
                    ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section(header: Text("Encoder Options")) {
                        HStack {
                            Text("Default Encoder")
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedEncoder.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Add haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            selectedEncoder = ""
                            dismiss()
                        }
                        .padding(.vertical, 8)
                        .background(
                            selectedEncoder.isEmpty ? 
                            Color.blue.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(8)
                        
                        TextField("Enter custom encoder name", text: $selectedEncoder)
                            .autocorrectionDisabled()
                    }
                    
                    if !encoders.isEmpty {
                        Section(header: Text("Detected Audio Encoders")) {
                            ForEach(encoders, id: \.encoderName) { encoder in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(encoder.encoderName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(encoder.mediaType)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedEncoder == encoder.encoderName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Add haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    selectedEncoder = encoder.encoderName
                                    dismiss()
                                }
                                .padding(.vertical, 8)
                                .background(
                                    selectedEncoder == encoder.encoderName ? 
                                    Color.blue.opacity(0.1) : Color.clear
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Section {
                        Button("Refresh Encoders") {
                            detectEncoders()
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .navigationBarTitle("Select Audio Encoder", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .disabled(isLoading)
            }
        }
        .alert("Detection Failed", isPresented: $showingError) {
            Button("OK") { }
            Button("Retry") {
                detectEncoders()
            }
        } message: {
            Text(errorMessage ?? NSLocalizedString("Failed to detect encoders", comment: "Fallback detection error message"))
        }
        .onAppear {
            detectEncoders()
        }
    }
    
    private func detectEncoders() {
        isLoading = true
        errorMessage = nil
        
        let detector = ADBMediaDetector()
        detector.detectMediaCodecs(forHost: host, port: Int32(port)) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if success {
                    // Filter to only show audio encoders (mediaType starts with "audio/")
                    encoders = detector.mediaEncoders.filter { encoder in
                        encoder.mediaType.lowercased().hasPrefix("audio/")
                    }
                } else {
                    var fullErrorMessage = error?.localizedDescription ?? NSLocalizedString("Failed to detect encoders. Please check your connection and try again.", comment: "Detection failure default message")
                    
                    // Add raw ADB output for diagnostic purposes
                    if let nsError = error as NSError?,
                       let adbOutput = nsError.userInfo["ADBOutput"] as? String {
                        fullErrorMessage += "\n\n" + NSLocalizedString("Diagnostic info:", comment: "Label for additional diagnostic information") + "\n\(adbOutput)"
                    }
                    
                    errorMessage = fullErrorMessage
                    showingError = true
                }
            }
        }
    }
}

struct CreateSessionView_Previews: PreviewProvider {
    static var previews: some View {
        SessionCreateView()
    }
}

private func filterBitRateInput(_ input: String) -> String {
    // If it's a valid number, return as is
    if let _ = Int(input) {
        return input
    }
    
    // Check if it ends with K or M (case insensitive)
    let upperInput = input.uppercased()
    if upperInput.hasSuffix("K") || upperInput.hasSuffix("M") {
        let numberPart = String(input.dropLast())
        if let _ = Int(numberPart) {
            return input
        }
    }
    
    // Filter out invalid characters, keeping only numbers and K/M
    let filtered = input.filter { char in
        char.isNumber || char.uppercased() == "K" || char.uppercased() == "M"
    }
    
    // If the filtered string ends with K or M, ensure there are numbers before it
    if filtered.uppercased().hasSuffix("K") || filtered.uppercased().hasSuffix("M") {
        let numberPart = String(filtered.dropLast())
        if let _ = Int(numberPart) {
            return filtered
        }
    }
    
    // If we have numbers, return just the numbers
    if let _ = Int(filtered) {
        return filtered
    }
    
    return ""
}
