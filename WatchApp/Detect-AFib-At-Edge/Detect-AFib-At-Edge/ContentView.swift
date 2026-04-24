//
//  ContentView.swift
//  Detect-AFib-At-Edge
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CompanionDashboardView()
    }
}

#Preview {
    ContentView()
        .environmentObject(PhoneSessionManager.shared)
}
