//
//  Detect_AFib_At_EdgeApp.swift
//  Detect-AFib-At-Edge Watch App
//

import SwiftUI
import WatchKit

@main
struct Detect_AFib_At_Edge_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = InferenceCoordinator.shared

    init() {
        WatchSessionManager.shared.activate()
        BackgroundScheduler.scheduleNext()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        BackgroundScheduler.scheduleNext()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task { @MainActor in
            BackgroundScheduler.handle(backgroundTasks)
        }
    }
}
