//
//  AirWhisperTrain_WatchApp.swift
//  AirWhisperTrain-Watch Watch App
//
//  Created by Dhruv Chauhan on 30/08/26.
//

import SwiftUI

@main
struct AirWhisperTrain_Watch_Watch_AppApp: App {
    @StateObject private var connectivity = TrainWatchConnectivityClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}
