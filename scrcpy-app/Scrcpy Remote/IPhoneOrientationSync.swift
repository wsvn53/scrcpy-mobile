//
//  IPhoneOrientationSync.swift
//  Scrcpy Remote
//
//  Event-driven synchronization of the iPhone's physical orientation with an
//  Android ADB session. No polling and no changes to Android display size.
//

import Foundation
import UIKit

/// Keeps one ADB session in sync with the iPhone's physical orientation.
/// All mutable state is confined to the main queue. ADB callbacks return to
/// that queue before updating state.
final class IPhoneOrientationSync {
    static let shared = IPhoneOrientationSync()

    /// Snapshot the user's previous rotation policy using Android's own
    /// window-manager command, which reports either "free" or "lock N".
    enum OriginalRotation: Equatable {
        case automatic
        case locked(Int)

        static func parse(_ output: String) -> Self? {
            let parts = output.split(whereSeparator: \.isWhitespace)
            if parts.count == 1, parts[0] == "free" { return .automatic }
            if parts.count == 2, parts[0] == "lock",
               let angle = Int(parts[1]), (0...3).contains(angle) {
                return .locked(angle)
            }
            return nil
        }
    }

    private var sessionID: UUID?
    private var serial: String?
    private var observer: NSObjectProtocol?
    private var generation = UUID()
    private var originalRotation: OriginalRotation?
    private var ready = false
    private var stopping = false
    private var restoring = false
    private var sending = false
    private var attemptedChange = false
    private var desiredRotation: Int?
    private var appliedRotation: Int?
    private var pendingChange: DispatchWorkItem?
    private var snapshotTimeout: DispatchWorkItem?
    private var stopTimeout: DispatchWorkItem?
    private var stopCompletions: [() -> Void] = []

    private init() {}

    /// Starts after the ADB video window is connected. Repeated calls for the
    /// same session (e.g. window-created and window-appeared events) are safe.
    func start(sessionID: UUID, serial: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start(sessionID: sessionID, serial: serial) }
            return
        }

        if self.sessionID == sessionID, self.serial == serial, !stopping {
            return  // Duplicate window-created/appeared notifications.
        }

        guard self.sessionID == nil else {
            stop { [weak self] in self?.start(sessionID: sessionID, serial: serial) }
            return
        }

        self.sessionID = sessionID
        self.serial = serial
        generation = UUID()
        ready = false
        stopping = false
        restoring = false
        sending = false
        attemptedChange = false
        appliedRotation = nil
        desiredRotation = nil
        originalRotation = nil

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deviceOrientationChanged()
        }

        // Snapshot BEFORE modifying Android. This is one round trip even over
        // Tailscale, and reads the same policy that our rotation commands edit.
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token, !self.ready, !self.stopping else { return }
            self.failToStart("Timed out reading the original Android rotation")
        }
        snapshotTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

        execute(["-s", serial, "shell", "cmd", "window", "user-rotation"]) { [weak self] output, code in
            guard let self = self, self.generation == token, !self.stopping else { return }
            self.snapshotTimeout?.cancel()
            self.snapshotTimeout = nil
            guard code == 0, let original = OriginalRotation.parse(output ?? "") else {
                self.failToStart("Cannot read Android's original rotation policy")
                return
            }
            self.originalRotation = original
            self.ready = true
            self.synchronizeNow(force: true)
        }
    }

    /// Called on foreground/reopen; re-applies the current iPhone orientation
    /// in case the remote device changed while the app was suspended.
    func resume() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resume() }
            return
        }
        synchronizeNow(force: true)
    }

    /// Finishes pending rotation before restoring Android's previous mode.
    /// The completion runs only after the restoration attempt, so callers can
    /// close the ADB connection without racing the final command.
    func stop(completion: @escaping () -> Void = {}) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { completion(); return }
                self.stop(completion: completion)
            }
            return
        }
        guard sessionID != nil else {
            completion()
            return
        }
        stopCompletions.append(completion)
        guard !stopping else { return }

        stopping = true
        snapshotTimeout?.cancel()
        snapshotTimeout = nil
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token, self.stopping else { return }
            print("[iPhoneOrientationSync] Timed out restoring rotation; disconnecting without blocking.")
            self.completeStop()
        }
        stopTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        pendingChange?.cancel()
        pendingChange = nil
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        if !sending {
            finishStop()
        }
    }

    private func failToStart(_ reason: String) {
        print("[iPhoneOrientationSync] \(reason); leaving Android rotation unchanged.")
        stop()
    }

    private func deviceOrientationChanged() {
        guard !stopping, ready, UIApplication.shared.applicationState == .active,
              let rotation = Self.rotation(for: UIDevice.current.orientation) else { return }

        // Ignore face-up, face-down and unknown readings, and coalesce a burst
        // of sensor notifications into one ADB command.
        pendingChange?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token, self.ready, !self.stopping else { return }
            self.desiredRotation = rotation
            self.sendIfNeeded()
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    private func synchronizeNow(force: Bool) {
        guard ready, !stopping, UIApplication.shared.applicationState == .active else { return }
        pendingChange?.cancel()
        pendingChange = nil
        if force { appliedRotation = nil }

        // At startup the sensor can be .unknown; use the visible scene's
        // orientation as a fallback, then portrait if neither is available.
        desiredRotation = Self.rotation(for: UIDevice.current.orientation)
            ?? Self.currentInterfaceRotation()
            ?? 0
        sendIfNeeded()
    }

    private func sendIfNeeded() {
        guard ready, !stopping, !sending,
              let rotation = desiredRotation, rotation != appliedRotation,
              let serial = serial else { return }

        sending = true
        attemptedChange = true
        let token = generation
        execute(["-s", serial, "shell", "cmd", "window", "user-rotation", "lock", String(rotation)]) { [weak self] output, code in
            guard let self = self, self.generation == token else { return }
            self.sending = false
            if code == 0 {
                self.appliedRotation = rotation
            } else {
                print("[iPhoneOrientationSync] Rotation command failed: \(output ?? "unknown error")")
            }

            if self.stopping {
                self.finishStop()
            } else if self.desiredRotation != rotation {
                // A newer orientation arrived during the in-flight command;
                // send it even if the earlier command failed.
                self.sendIfNeeded()
            }
        }
    }

    private func finishStop() {
        guard stopping, !sending, !restoring else { return }
        restoring = true
        guard attemptedChange, let restoreSerial = serial,
              let restoreState = originalRotation else {
            completeStop()
            return
        }

        let arguments: [String]
        switch restoreState {
        case .automatic:
            arguments = ["-s", restoreSerial, "shell", "cmd", "window", "user-rotation", "free"]
        case .locked(let rotation):
            arguments = ["-s", restoreSerial, "shell", "cmd", "window", "user-rotation", "lock", String(rotation)]
        }
        let token = generation
        execute(arguments) { [weak self] output, code in
            guard let self = self, self.generation == token, self.stopping else { return }
            if code != 0 {
                print("[iPhoneOrientationSync] Could not restore Android rotation: \(output ?? "unknown error")")
            }
            self.completeStop()
        }
    }

    private func completeStop() {
        snapshotTimeout?.cancel()
        snapshotTimeout = nil
        stopTimeout?.cancel()
        stopTimeout = nil
        let callbacks = stopCompletions
        stopCompletions = []
        sessionID = nil
        serial = nil
        originalRotation = nil
        desiredRotation = nil
        appliedRotation = nil
        ready = false
        stopping = false
        restoring = false
        attemptedChange = false
        generation = UUID()
        callbacks.forEach { $0() }
    }

    private func execute(_ arguments: [String], completion: @escaping (String?, Int32) -> Void) {
        ADBClient.shared().executeADBCommandAsync(arguments) { output, returnCode in
            DispatchQueue.main.async {
                completion(output, Int32(returnCode))
            }
        }
    }

    /// Android Surface.ROTATION_* values for physical iPhone orientations.
    static func rotation(for orientation: UIDeviceOrientation) -> Int? {
        switch orientation {
        case .portrait: return 0
        case .landscapeLeft: return 1
        case .portraitUpsideDown: return 2
        case .landscapeRight: return 3
        default: return nil
        }
    }

    private static func currentInterfaceRotation() -> Int? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        switch scene?.interfaceOrientation {
        case .portrait: return 0
        case .landscapeRight: return 1
        case .portraitUpsideDown: return 2
        case .landscapeLeft: return 3
        default: return nil
        }
    }
}
