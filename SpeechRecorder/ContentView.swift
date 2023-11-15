//
//  ContentView.swift
//  SpeechRecorder
//
//  Created by Ian Dundas on 15/11/2023.
//

import SwiftUI
import Speech

struct ContentView: View {

    let speechTranscriber = SpeechTranscriber()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Text(speechTranscriber.state.description)

            if let hasPermission = speechTranscriber.hasPermission {
                if hasPermission {

                    recordPanel

                    Text("Speech permission granted").foregroundStyle(Color.green)


                } else {
                    Text("Speech permission rejected").foregroundStyle(Color.red)
                }
            } else {
                Button("Request speech permission") {
                    Task {
                        do {
                            try await speechTranscriber.requestPermission()
                        } catch {
                            print("Error getting permission: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        .padding()
    }

    @State var locale = Locale(identifier: "en-US") {
        didSet {
            print("Set locale: \(locale.identifier)")
        }
    }

    @ViewBuilder
    var recordPanel: some View {

        if speechTranscriber.state.isIdle {
            Button("Start Recording") {
                speechTranscriber.startRecording(locale: locale)
            }
        }
        else if speechTranscriber.state.isRecording {
            Button("Stop Recording") {
                speechTranscriber.stopRecording()
            }

            Button("Change locale") {
                speechTranscriber.stopRecording()

                if locale.identifier == "en-US" {
                    locale = Locale(identifier: "nl-NL")
                } else {
                    locale = Locale(identifier: "en-US")
                }
                speechTranscriber.startRecording(locale: locale)
            }
        }
    }
}
