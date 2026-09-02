//
//  AirWhisperTrainApp.swift
//  AirWhisperTrain
//
//  Created by Dhruv Chauhan on 30/08/26.
//

import SwiftUI

@main
struct AirWhisperTrainApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
