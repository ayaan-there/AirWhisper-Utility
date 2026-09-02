//
//  ContentView.swift
//  AirWhisperTrain
//
//  Created by Dhruv Chauhan on 30/08/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path = NavigationPath()
    @State private var showHowTo = false
    @State private var pendingLetter: String?

    var body: some View {
        NavigationStack(path: $path) {
            AlphabetGridContent(onHowTo: { showHowTo = true })
                .navigationTitle("Train Alphabet")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.importCSV) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .drawLetter(let letter):
                        DrawingView(letter: letter) { selected, drawing in
                            model.submitLetter(selected, drawing: drawing)
                            path.append(Route.recordings(selected))
                        }
                    case .recordings(let letter):
                        RecordingsListView(letter: letter, model: model)
                    case .importCSV:
                        CSVImportView(onImported: { rec in
                            path.append(rec)
                        })
                    case .howTo:
                        HowToView()
                    }
                }
                .navigationDestination(for: IMURecording.self) { rec in
                    VisualizationScreen(recording: rec)
                }
                .sheet(isPresented: $showHowTo) {
                    HowToView()
                }
        }
        .onReceive(model.$justReceivedLetter) { letter in
            guard let letter else { return }
            path.append(Route.recordings(letter))
        }
    }
}

enum Route: Hashable {
    case drawLetter(String)
    case recordings(String)
    case importCSV
    case howTo
}

struct AlphabetGridContent: View {
    let onHowTo: () -> Void

    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                grid
                howToButton
            }
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.brandBlue)
            Text("Air Whisper Trainer")
                .font(.title2.weight(.bold))
            Text("Pick a letter, draw it on screen, then record samples in the air wearing your Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(LetterGuide.alphabet, id: \.self) { letter in
                NavigationLink(value: route(for: letter)) {
                    letterCell(letter)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func route(for letter: String) -> Route {
        let localCount = model.store.recordings(for: letter).count
        if localCount == 0 { return .drawLetter(letter) }
        return .recordings(letter)
    }

    private func letterCell(_ letter: String) -> some View {
        let localCount = model.store.recordings(for: letter).count
        let isComplete = localCount >= RecordingStore.maxPerLetter
        let canSend = localCount >= 25

        return VStack(spacing: 6) {
            Text(letter)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(AppTheme.brandBlue)

            VStack(spacing: 2) {
                Text(progressText(for: letter))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(localCount >= RecordingStore.maxPerLetter ? .red : (localCount >= 25 ? .green : .secondary))

                if localCount > 0 {
                    HStack(spacing: 4) {
                        if localCount >= 25 {
                            Image(systemName: "paperplane.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if localCount >= RecordingStore.maxPerLetter {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    localCount >= RecordingStore.maxPerLetter ? Color.red.opacity(0.5) :
                    localCount >= 25 ? Color.green.opacity(0.5) :
                    AppTheme.brandBlue.opacity(0.18),
                    lineWidth: localCount > 0 ? 2 : 1
                )
        )
    }

    private func progressText(for letter: String) -> String {
        let localCount = model.store.recordings(for: letter).count
        if localCount == 0 { return "Not started" }
        if localCount >= RecordingStore.maxPerLetter { return "100/100 - Full" }
        if localCount >= 25 { return "\(localCount)/100 - Ready to send" }
        return "\(localCount)/100 (need \(25 - localCount) to send)"
    }

    private var howToButton: some View {
        Button(action: onHowTo) {
            HStack {
                Image(systemName: "info.circle")
                Text("How to use — Air Write")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.medium))
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel.shared)
}
