//
//  ContentView.swift
//  Detect-AFib-At-Edge Watch App
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: InferenceCoordinator

    var body: some View {
        MonitoringView(coordinator: coordinator)
    }
}

#Preview {
    ContentView()
        .environmentObject(InferenceCoordinator.shared)
}
