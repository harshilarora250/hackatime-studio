//
//  ContentView.swift
//  Hackatime Studio
//
//  Created by Harshil on 2026-11-17.
//

import SwiftUI

/// Root layout: custom sidebar + routed page, with setup and toasts layered on top.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)
            ZStack {
                Theme.canvas
                page
                    .id(model.route)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            .animation(Theme.Motion.page, value: model.route)
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
        .overlay {
            if let flow = model.setupFlow {
                OnboardingView(flow: flow)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.page, value: model.setupFlow)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.toast = nil }
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(toast.style == .error ? 9 : 6))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast?.id)
    }

    @ViewBuilder private var page: some View {
        switch model.route {
        case .dashboard: DashboardView()
        case .configuration: ConfigurationView()
        case .folders: FoldersView()
        case .editors: EditorsView()
        case .diagnostics: DiagnosticsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView().environment(AppModel())
}
