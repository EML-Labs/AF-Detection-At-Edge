//
//  Detect_AFib_At_EdgeApp.swift
//  Detect-AFib-At-Edge
//

import SwiftUI

@main
struct Detect_AFib_At_EdgeApp: App {
    @StateObject private var session = PhoneSessionManager.shared

    init() {
        PhoneSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
