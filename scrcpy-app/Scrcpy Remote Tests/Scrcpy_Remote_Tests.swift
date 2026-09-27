//
//  Scrcpy_Remote_Tests.swift
//  Scrcpy Remote Tests
//
//  Created by Ethan on 12/14/24.
//

import Testing
import UIKit
@testable import Scrcpy_Remote

struct Scrcpy_Remote_Tests {

    @Test func iphoneOrientationMapping() {
        #expect(IPhoneOrientationSync.rotation(for: .portrait) == 0)
        #expect(IPhoneOrientationSync.rotation(for: .landscapeLeft) == 1)
        #expect(IPhoneOrientationSync.rotation(for: .portraitUpsideDown) == 2)
        #expect(IPhoneOrientationSync.rotation(for: .landscapeRight) == 3)
        #expect(IPhoneOrientationSync.rotation(for: .faceUp) == nil)
        #expect(IPhoneOrientationSync.rotation(for: .unknown) == nil)
    }

    @Test func rotationSnapshotParsing() {
        #expect(IPhoneOrientationSync.OriginalRotation.parse("free\\n") == .automatic)
        #expect(IPhoneOrientationSync.OriginalRotation.parse("lock 0\\n") == .locked(0))
        #expect(IPhoneOrientationSync.OriginalRotation.parse("lock 1\\r\\n") == .locked(1))
        #expect(IPhoneOrientationSync.OriginalRotation.parse("lock 3") == .locked(3))
        #expect(IPhoneOrientationSync.OriginalRotation.parse("lock 4") == nil)
        #expect(IPhoneOrientationSync.OriginalRotation.parse("lock foo") == nil)
        #expect(IPhoneOrientationSync.OriginalRotation.parse("") == nil)
    }

    @Test func iphoneOrientationOptionBackwardsCompatible() throws {
        var options = ADBSessionOptions()
        options.syncIPhoneOrientation = true
        let data = try JSONEncoder().encode(options)
        let roundTrip = try JSONDecoder().decode(ADBSessionOptions.self, from: data)
        #expect(roundTrip.syncIPhoneOrientation)

        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "syncIPhoneOrientation")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decodedLegacy = try JSONDecoder().decode(ADBSessionOptions.self, from: legacyData)
        #expect(!decodedLegacy.syncIPhoneOrientation)
    }

    @Test func sessionManager_save() async throws {
        let sessionManager = SessionManager.shared
        var session = ScrcpySessionModel()
        session.host = "127.0.0.1"
        session.port = "5901"
        session.vncOptions.vncUser = "user"
        session.vncOptions.vncPassword = "password"
        sessionManager.saveSession(session)
        
        print("Saved session:", session)
    }
    
    @Test func sessionManager_load() async throws {
        let sessionManager = SessionManager.shared
        let sessions = sessionManager.loadSessions()
        print("Loaded sessions:", sessions)
    }

}
