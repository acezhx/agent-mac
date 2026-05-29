//
//  AgentMacApp.swift
//  AgentMac
//
//  Created by 张玺 on 2026/5/25.
//

import SwiftUI
import ComposableArchitecture

@main
struct AgentMacApp: App {
    private let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    private let agentStore = Store(initialState: AgentFeature.State()) {
        AgentFeature()
    }
    private let resourceStore = Store(initialState: ResourceFeature.State()) {
        ResourceFeature()
    }
    private let settingsStore = Store(initialState: SettingsFeature.State()) {
        SettingsFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }

        Window(AppWindowID.agentLibrary.title, id: AppWindowID.agentLibrary.rawValue) {
            AgentView(store: agentStore)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1000, height: 640)

        Window(AppWindowID.resourceLibrary.title, id: AppWindowID.resourceLibrary.rawValue) {
            ResourceView(store: resourceStore)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 680)

        Window(AppWindowID.settings.title, id: AppWindowID.settings.rawValue) {
            SettingsView(store: settingsStore)
                .frame(minWidth: 520, minHeight: 420)
        }
        .defaultSize(width: 560, height: 480)
    }
}
